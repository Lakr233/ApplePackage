#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER_DIR="$ROOT_DIR/GoIPAToolWrapper"
OUTPUT_XCFRAMEWORK="$ROOT_DIR/Binaries/GoIPAToolBindings.xcframework"
OUTPUT_ZIP="$ROOT_DIR/Binaries/GoIPAToolBindings.xcframework.zip"
METADATA_FILE="$WRAPPER_DIR/bindings-metadata.json"
MODULE="github.com/majd/ipatool/v2"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[!] Missing required command: $1" >&2
        exit 1
    fi
}

require_command go
require_command swift
require_command python3

if [ ! -d "$WRAPPER_DIR" ]; then
    echo "[!] Wrapper directory does not exist: $WRAPPER_DIR" >&2
    exit 1
fi

TARGET_VERSION="${1:-latest}"
RELEASE_TAG_OVERRIDE="${2:-}"

read_existing_metadata_repository() {
    python3 - "$METADATA_FILE" <<'PY'
import json
import pathlib
import sys

metadata_path = pathlib.Path(sys.argv[1])
if not metadata_path.exists():
    raise SystemExit(0)

try:
    payload = json.loads(metadata_path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)

value = payload.get("repository")
if isinstance(value, str):
    value = value.strip()
    if value:
        print(value)
PY
}

resolve_repository_slug() {
    if [ -n "${APPLEPACKAGE_GITHUB_REPOSITORY:-}" ]; then
        echo "$APPLEPACKAGE_GITHUB_REPOSITORY"
        return
    fi

    local upstream_remote_url origin_remote_url existing_metadata_repository resolved
    upstream_remote_url="$(git -C "$ROOT_DIR" remote get-url upstream 2>/dev/null || true)"
    origin_remote_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    existing_metadata_repository="$(read_existing_metadata_repository)"

    resolved="$(python3 - "$upstream_remote_url" "$origin_remote_url" "$existing_metadata_repository" <<'PY'
import re
import sys

upstream = sys.argv[1].strip()
origin = sys.argv[2].strip()
metadata_repository = sys.argv[3].strip()

def parse_remote(remote: str) -> str:
    patterns = [
        r"^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?$",
        r"^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$",
        r"^ssh://git@github\.com/([^/]+)/([^/]+?)(?:\.git)?$",
        r"^git://github\.com/([^/]+)/([^/]+?)(?:\.git)?$",
    ]

    for pattern in patterns:
        match = re.match(pattern, remote)
        if match:
            return f"{match.group(1)}/{match.group(2)}"
    return ""

def is_valid_slug(value: str) -> bool:
    if "/" not in value:
        return False
    owner, repo = value.split("/", 1)
    if not owner or not repo:
        return False
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    return all(ch in allowed for ch in owner) and all(ch in allowed for ch in repo)

for candidate in [parse_remote(upstream), metadata_repository, parse_remote(origin)]:
    if candidate and is_valid_slug(candidate):
        print(candidate)
        raise SystemExit(0)

print("")
PY
)"

    if [ -z "$resolved" ]; then
        echo "[!] Unable to determine repository slug." >&2
        echo "    Set APPLEPACKAGE_GITHUB_REPOSITORY=<owner>/<repo> or configure git upstream/origin remotes." >&2
        exit 1
    fi

    echo "$resolved"
}

REPOSITORY_SLUG="$(resolve_repository_slug)"

echo "[*] Updating $MODULE to $TARGET_VERSION"
(
    cd "$WRAPPER_DIR"
    go get "$MODULE@$TARGET_VERSION"
    go mod tidy
)

PINNED_VERSION="$(cd "$WRAPPER_DIR" && go list -m -f '{{.Version}}' "$MODULE")"
echo "[*] Pinned ipatool version: $PINNED_VERSION"

"$ROOT_DIR/Scripts/build_xcframework.sh"
"$ROOT_DIR/Scripts/package_xcframework.py" "$OUTPUT_XCFRAMEWORK" "$OUTPUT_ZIP" >/dev/null

CHECKSUM="$(cd "$ROOT_DIR" && swift package compute-checksum "$OUTPUT_ZIP")"

if [ -n "$RELEASE_TAG_OVERRIDE" ]; then
    RELEASE_TAG="$RELEASE_TAG_OVERRIDE"
else
    RELEASE_TAG="go-ipatool-${PINNED_VERSION}-${CHECKSUM:0:12}"
fi

python3 - "$METADATA_FILE" "$MODULE" "$PINNED_VERSION" "$RELEASE_TAG" "$CHECKSUM" "$REPOSITORY_SLUG" <<'PY'
import json
import pathlib
import sys

metadata_path = pathlib.Path(sys.argv[1])
module = sys.argv[2]
ipatool_version = sys.argv[3]
release_tag = sys.argv[4]
checksum = sys.argv[5]
repository = sys.argv[6]

payload = {
    "assetName": "GoIPAToolBindings.xcframework.zip",
    "checksum": checksum,
    "ipatoolModule": module,
    "ipatoolVersion": ipatool_version,
    "releaseTag": release_tag,
    "repository": repository,
}

metadata_path.parent.mkdir(parents=True, exist_ok=True)
metadata_path.write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "[*] Wrote metadata: $METADATA_FILE"
echo "    repository: $REPOSITORY_SLUG"
echo "    releaseTag: $RELEASE_TAG"
echo "    checksum: $CHECKSUM"
echo "    asset: $(basename "$OUTPUT_ZIP")"
