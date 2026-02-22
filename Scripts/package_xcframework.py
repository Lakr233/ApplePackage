#!/usr/bin/env python3

import pathlib
import stat
import sys
import zipfile


def build_zip(xcframework_path: pathlib.Path, output_zip: pathlib.Path) -> None:
    if not xcframework_path.exists():
        raise FileNotFoundError(f"XCFramework does not exist: {xcframework_path}")

    output_zip.parent.mkdir(parents=True, exist_ok=True)

    entries = sorted(
        [p for p in xcframework_path.rglob("*") if p.is_file()],
        key=lambda p: str(p.relative_to(xcframework_path.parent)),
    )

    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file_path in entries:
            relative = file_path.relative_to(xcframework_path.parent)
            arcname = str(relative).replace("\\", "/")

            info = zipfile.ZipInfo(filename=arcname)
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3

            mode = file_path.stat().st_mode
            info.external_attr = (stat.S_IMODE(mode) | stat.S_IFREG) << 16

            with file_path.open("rb") as handle:
                archive.writestr(info, handle.read())


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: package_xcframework.py <xcframework-path> <output-zip>", file=sys.stderr)
        return 1

    xcframework_path = pathlib.Path(sys.argv[1]).resolve()
    output_zip = pathlib.Path(sys.argv[2]).resolve()
    build_zip(xcframework_path, output_zip)
    print(output_zip)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
