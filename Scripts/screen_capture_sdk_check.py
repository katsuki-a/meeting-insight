#!/usr/bin/env python3

import json
import pathlib
import subprocess
import sys


def main() -> int:
    repository_root = pathlib.Path(__file__).resolve().parent.parent
    fixture_path = repository_root / "Fixtures/SDK/ScreenCaptureKit-26.2.json"
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    sdk_path = pathlib.Path(
        subprocess.run(
            ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    )
    header_path = (
        sdk_path
        / "System/Library/Frameworks/ScreenCaptureKit.framework/Versions/A/Headers/SCStream.h"
    )
    if not header_path.is_file():
        print(f"ScreenCaptureKit header is missing: {header_path}", file=sys.stderr)
        return 1

    header = header_path.read_text(encoding="utf-8")
    missing = [token for token in fixture["required_header_tokens"] if token not in header]
    if missing:
        for token in missing:
            print(f"ScreenCaptureKit SDK drift: missing {token!r}", file=sys.stderr)
        return 1

    print(
        "ScreenCaptureKit SDK contract passed "
        f"(fixture macOS {fixture['sdk_version']}, current {sdk_path.name})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
