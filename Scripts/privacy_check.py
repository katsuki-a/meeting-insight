#!/usr/bin/env python3

import pathlib
import re
import sys


def main() -> int:
    root = pathlib.Path(sys.argv[1])
    source_roots = [root / "App", root / "Packages" / "MeetingInsightKit" / "Sources"]
    log_pattern = re.compile(
        r"(?:Logger|os_log).*?(?:transcript|question|quote|token|rootPath|absolutePath)",
        re.IGNORECASE,
    )
    errors: list[str] = []

    for source_root in source_roots:
        for source in source_root.glob("**/*.swift"):
            text = source.read_text(encoding="utf-8")
            if log_pattern.search(text):
                errors.append(f"sensitive logging pattern: {source.relative_to(root)}")

    for module in ("MeetingInsightCapture", "MeetingInsightTranscription"):
        module_root = root / "Packages" / "MeetingInsightKit" / "Sources" / module
        for source in module_root.glob("**/*.swift"):
            text = source.read_text(encoding="utf-8")
            if "AVAudioFile" in text or "write(to:" in text:
                errors.append(f"raw audio persistence pattern: {source.relative_to(root)}")

    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("privacy lint checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
