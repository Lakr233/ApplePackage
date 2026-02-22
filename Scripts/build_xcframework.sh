#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WRAPPER_DIR="$ROOT_DIR/GoIPAToolWrapper"
BUILD_DIR="$ROOT_DIR/.build/goipatool"
OUTPUT_DIR="$ROOT_DIR/Binaries"
OUTPUT_XCFRAMEWORK="$OUTPUT_DIR/GoIPAToolBindings.xcframework"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[!] Missing required command: $1" >&2
        exit 1
    fi
}

require_command go
require_command xcodebuild
require_command xcrun
require_command lipo
require_command python3

if [ ! -d "$WRAPPER_DIR" ]; then
    echo "[!] Wrapper directory does not exist: $WRAPPER_DIR" >&2
    exit 1
fi

build_slice() {
    local name="$1"
    local sdk="$2"
    local goos="$3"
    local goarch="$4"
    local clang_arch="$5"
    local min_flag="$6"

    local slice_dir="$BUILD_DIR/$name"
    local include_dir="$slice_dir/include"

    rm -rf "$slice_dir"
    mkdir -p "$include_dir"

    local cc
    cc="$(xcrun --sdk "$sdk" --find clang)"
    local sdk_path
    sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"

    echo "[*] Building $name (GOOS=$goos GOARCH=$goarch)..."
    (
        cd "$WRAPPER_DIR"
        env \
            CGO_ENABLED=1 \
            GOOS="$goos" \
            GOARCH="$goarch" \
            CC="$cc" \
            ZERO_AR_DATE=1 \
            CGO_CFLAGS="-isysroot $sdk_path $min_flag -arch $clang_arch" \
            CGO_LDFLAGS="-isysroot $sdk_path $min_flag -arch $clang_arch" \
            go build \
                -trimpath \
                -buildvcs=false \
                -buildmode=c-archive \
                -ldflags='-s -w -buildid=' \
                -o "$slice_dir/libgoipatool.a" \
                .
    )

    cp "$slice_dir/libgoipatool.h" "$include_dir/goipatool.h"

    cat > "$include_dir/module.modulemap" <<'MAP'
module GoIPAToolBindings {
    header "goipatool.h"
    export *
}
MAP
}

rm -rf "$BUILD_DIR" "$OUTPUT_XCFRAMEWORK"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

build_slice "ios-device-arm64" "iphoneos" "ios" "arm64" "arm64" "-miphoneos-version-min=15.0"
build_slice "ios-sim-arm64" "iphonesimulator" "ios" "arm64" "arm64" "-mios-simulator-version-min=15.0"

if build_slice "ios-sim-amd64" "iphonesimulator" "ios" "amd64" "x86_64" "-mios-simulator-version-min=15.0"; then
    echo "[*] Built optional iOS simulator x86_64 slice"
else
    echo "[*] Skipping optional iOS simulator x86_64 slice"
fi

build_slice "tvos-device-arm64" "appletvos" "ios" "arm64" "arm64" "-target arm64-apple-tvos17.0"
build_slice "tvos-sim-arm64" "appletvsimulator" "ios" "arm64" "arm64" "-target arm64-apple-tvos17.0-simulator"

if build_slice "tvos-sim-amd64" "appletvsimulator" "ios" "amd64" "x86_64" "-target x86_64-apple-tvos17.0-simulator"; then
    echo "[*] Built optional tvOS simulator x86_64 slice"
else
    echo "[*] Skipping optional tvOS simulator x86_64 slice"
fi

build_slice "xros-device-arm64" "xros" "ios" "arm64" "arm64" "-target arm64-apple-xros1.0"
build_slice "xros-sim-arm64" "xrsimulator" "ios" "arm64" "arm64" "-target arm64-apple-xros1.0-simulator"

if build_slice "xros-sim-amd64" "xrsimulator" "ios" "amd64" "x86_64" "-target x86_64-apple-xros1.0-simulator"; then
    echo "[*] Built optional visionOS simulator x86_64 slice"
else
    echo "[*] Skipping optional visionOS simulator x86_64 slice"
fi

build_slice "macos-arm64" "macosx" "darwin" "arm64" "arm64" "-mmacosx-version-min=12.0"
build_slice "macos-amd64" "macosx" "darwin" "amd64" "x86_64" "-mmacosx-version-min=12.0"
build_slice "catalyst-arm64" "macosx" "ios" "arm64" "arm64" "-target arm64-apple-ios14.0-macabi"
build_slice "catalyst-amd64" "macosx" "ios" "amd64" "x86_64" "-target x86_64-apple-ios14.0-macabi"

mkdir -p \
    "$BUILD_DIR/ios-simulator/include" \
    "$BUILD_DIR/tvos/include" \
    "$BUILD_DIR/tvos-simulator/include" \
    "$BUILD_DIR/xros/include" \
    "$BUILD_DIR/xros-simulator/include" \
    "$BUILD_DIR/macos/include" \
    "$BUILD_DIR/catalyst/include"
cp "$BUILD_DIR/ios-sim-arm64/include/goipatool.h" "$BUILD_DIR/ios-simulator/include/goipatool.h"
cp "$BUILD_DIR/ios-sim-arm64/include/module.modulemap" "$BUILD_DIR/ios-simulator/include/module.modulemap"
cp "$BUILD_DIR/tvos-device-arm64/include/goipatool.h" "$BUILD_DIR/tvos/include/goipatool.h"
cp "$BUILD_DIR/tvos-device-arm64/include/module.modulemap" "$BUILD_DIR/tvos/include/module.modulemap"
cp "$BUILD_DIR/tvos-sim-arm64/include/goipatool.h" "$BUILD_DIR/tvos-simulator/include/goipatool.h"
cp "$BUILD_DIR/tvos-sim-arm64/include/module.modulemap" "$BUILD_DIR/tvos-simulator/include/module.modulemap"
cp "$BUILD_DIR/xros-device-arm64/include/goipatool.h" "$BUILD_DIR/xros/include/goipatool.h"
cp "$BUILD_DIR/xros-device-arm64/include/module.modulemap" "$BUILD_DIR/xros/include/module.modulemap"
cp "$BUILD_DIR/xros-sim-arm64/include/goipatool.h" "$BUILD_DIR/xros-simulator/include/goipatool.h"
cp "$BUILD_DIR/xros-sim-arm64/include/module.modulemap" "$BUILD_DIR/xros-simulator/include/module.modulemap"
cp "$BUILD_DIR/macos-arm64/include/goipatool.h" "$BUILD_DIR/macos/include/goipatool.h"
cp "$BUILD_DIR/macos-arm64/include/module.modulemap" "$BUILD_DIR/macos/include/module.modulemap"
cp "$BUILD_DIR/catalyst-arm64/include/goipatool.h" "$BUILD_DIR/catalyst/include/goipatool.h"
cp "$BUILD_DIR/catalyst-arm64/include/module.modulemap" "$BUILD_DIR/catalyst/include/module.modulemap"

SIM_LIBS=("$BUILD_DIR/ios-sim-arm64/libgoipatool.a")
if [ -f "$BUILD_DIR/ios-sim-amd64/libgoipatool.a" ]; then
    SIM_LIBS+=("$BUILD_DIR/ios-sim-amd64/libgoipatool.a")
fi
lipo -create "${SIM_LIBS[@]}" -output "$BUILD_DIR/ios-simulator/libgoipatool.a"

TVOS_SIM_LIBS=("$BUILD_DIR/tvos-sim-arm64/libgoipatool.a")
if [ -f "$BUILD_DIR/tvos-sim-amd64/libgoipatool.a" ]; then
    TVOS_SIM_LIBS+=("$BUILD_DIR/tvos-sim-amd64/libgoipatool.a")
fi
lipo -create "${TVOS_SIM_LIBS[@]}" -output "$BUILD_DIR/tvos-simulator/libgoipatool.a"

XROS_SIM_LIBS=("$BUILD_DIR/xros-sim-arm64/libgoipatool.a")
if [ -f "$BUILD_DIR/xros-sim-amd64/libgoipatool.a" ]; then
    XROS_SIM_LIBS+=("$BUILD_DIR/xros-sim-amd64/libgoipatool.a")
fi
lipo -create "${XROS_SIM_LIBS[@]}" -output "$BUILD_DIR/xros-simulator/libgoipatool.a"

cp "$BUILD_DIR/tvos-device-arm64/libgoipatool.a" "$BUILD_DIR/tvos/libgoipatool.a"
cp "$BUILD_DIR/xros-device-arm64/libgoipatool.a" "$BUILD_DIR/xros/libgoipatool.a"

lipo -create \
    "$BUILD_DIR/macos-arm64/libgoipatool.a" \
    "$BUILD_DIR/macos-amd64/libgoipatool.a" \
    -output "$BUILD_DIR/macos/libgoipatool.a"

lipo -create \
    "$BUILD_DIR/catalyst-arm64/libgoipatool.a" \
    "$BUILD_DIR/catalyst-amd64/libgoipatool.a" \
    -output "$BUILD_DIR/catalyst/libgoipatool.a"

xcodebuild -create-xcframework \
    -library "$BUILD_DIR/ios-device-arm64/libgoipatool.a" -headers "$BUILD_DIR/ios-device-arm64/include" \
    -library "$BUILD_DIR/ios-simulator/libgoipatool.a" -headers "$BUILD_DIR/ios-simulator/include" \
    -library "$BUILD_DIR/tvos/libgoipatool.a" -headers "$BUILD_DIR/tvos/include" \
    -library "$BUILD_DIR/tvos-simulator/libgoipatool.a" -headers "$BUILD_DIR/tvos-simulator/include" \
    -library "$BUILD_DIR/xros/libgoipatool.a" -headers "$BUILD_DIR/xros/include" \
    -library "$BUILD_DIR/xros-simulator/libgoipatool.a" -headers "$BUILD_DIR/xros-simulator/include" \
    -library "$BUILD_DIR/macos/libgoipatool.a" -headers "$BUILD_DIR/macos/include" \
    -library "$BUILD_DIR/catalyst/libgoipatool.a" -headers "$BUILD_DIR/catalyst/include" \
    -output "$OUTPUT_XCFRAMEWORK"

python3 - <<'PY' "$OUTPUT_XCFRAMEWORK/Info.plist"
import pathlib
import plistlib
import sys

plist_path = pathlib.Path(sys.argv[1])
with plist_path.open("rb") as f:
    data = plistlib.load(f)

libraries = data.get("AvailableLibraries", [])
data["AvailableLibraries"] = sorted(
    libraries,
    key=lambda item: item.get("LibraryIdentifier", ""),
)

with plist_path.open("wb") as f:
    plistlib.dump(data, f, sort_keys=True)
PY

echo "[*] XCFramework generated at: $OUTPUT_XCFRAMEWORK"
