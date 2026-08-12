#!/usr/bin/env python3

import argparse
import json
import pathlib
import os
import subprocess
import sys


def load_package(package_root: pathlib.Path) -> dict:
    if not package_root.is_dir():
        print("MeetingInsightKit package is missing", file=sys.stderr)
        raise SystemExit(1)
    result = subprocess.run(
        [
            "/usr/bin/xcrun",
            "swift",
            "package",
            "--disable-sandbox",
            "--cache-path",
            str(package_root.parent.parent / ".artifacts" / "cache" / "swiftpm"),
            "dump-package",
        ],
        cwd=package_root,
        capture_output=True,
        check=False,
        env=os.environ,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr.strip() or "swift package dump-package failed", file=sys.stderr)
        raise SystemExit(result.returncode or 1)
    return json.loads(result.stdout)


def target_dependencies(target: dict) -> set[str]:
    dependencies: set[str] = set()
    for dependency in target.get("dependencies", []):
        if "byName" in dependency:
            dependencies.add(dependency["byName"][0])
        elif "target" in dependency:
            dependencies.add(dependency["target"][0])
    return dependencies


def validate_package(package: dict, package_root: pathlib.Path, rules: dict) -> list[str]:
    targets = {target["name"]: target for target in package["targets"]}
    errors: list[str] = []

    for module, allowed in rules["allowed_dependencies"].items():
        target = targets.get(module)
        if target is None:
            errors.append(f"missing target: {module}")
            continue
        actual = target_dependencies(target)
        unexpected = sorted(actual - set(allowed))
        if unexpected:
            errors.append(f"{module} has forbidden dependencies: {', '.join(unexpected)}")

    sources_root = package_root / "Sources"
    for module, imports in rules["forbidden_imports"].items():
        for source in (sources_root / module).glob("**/*.swift"):
            text = source.read_text(encoding="utf-8")
            for module_name in imports:
                if f"import {module_name}" in text:
                    errors.append(f"{module} imports forbidden module {module_name}")

    for rule in rules["forbidden_patterns"]:
        for module in rule["modules"]:
            for source in (sources_root / module).glob("**/*.swift"):
                text = source.read_text(encoding="utf-8")
                for pattern in rule["patterns"]:
                    if pattern in text:
                        errors.append(f"{rule['id']} matched in {module}")

    return errors


def validate(package_root: pathlib.Path, rules: dict) -> list[str]:
    return validate_package(load_package(package_root), package_root, rules)


def run_self_test(package_root: pathlib.Path, rules: dict) -> list[str]:
    package = load_package(package_root)
    broken = json.loads(json.dumps(rules))
    broken["allowed_dependencies"]["MissingSelfTestTarget"] = []
    detected = validate_package(package, package_root, broken)
    if "missing target: MissingSelfTestTarget" not in detected:
        return ["self-test did not reject an invalid architecture"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=pathlib.Path, required=True)
    parser.add_argument("--rules", type=pathlib.Path, required=True)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    rules = json.loads(arguments.rules.read_text(encoding="utf-8"))
    errors = validate(arguments.package_root, rules)
    if arguments.self_test:
        errors.extend(run_self_test(arguments.package_root, rules))

    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print("architecture checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
