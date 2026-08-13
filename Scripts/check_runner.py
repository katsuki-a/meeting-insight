#!/usr/bin/env python3

import datetime
import json
import os
import pathlib
import subprocess
import time


def command_output(arguments: list[str], cwd: pathlib.Path) -> str:
    result = subprocess.run(arguments, cwd=cwd, capture_output=True, check=False, text=True)
    return (result.stdout or result.stderr).strip()


def environment(repo_root: pathlib.Path) -> dict[str, str]:
    os_version = command_output(["/usr/bin/sw_vers", "-productVersion"], repo_root)
    xcode = command_output(["/usr/bin/xcodebuild", "-version"], repo_root).splitlines()[0]
    swift = command_output(["/usr/bin/xcrun", "swift", "--version"], repo_root).splitlines()[0]
    codex_path = pathlib.Path("/Applications/ChatGPT.app/Contents/Resources/codex")
    codex = "unavailable"
    if codex_path.is_file():
        codex = command_output([str(codex_path), "--version"], repo_root).splitlines()[0]
    return {"os": f"macOS {os_version}", "xcode": xcode, "swift": swift, "codex": codex}


def git_state(repo_root: pathlib.Path) -> dict[str, object]:
    commit = command_output(["/usr/bin/git", "rev-parse", "HEAD"], repo_root)
    dirty = bool(command_output(["/usr/bin/git", "status", "--porcelain=v1"], repo_root))
    return {"commit": commit, "dirty": dirty}


def write_atomic(path: pathlib.Path, payload: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(payload, encoding="utf-8")
    os.replace(temporary, path)


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parent.parent
    manifest_path = repo_root / "Harness" / "checks.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    started_at = datetime.datetime.now(datetime.timezone.utc)
    reports_root = repo_root / ".artifacts" / "checks"
    reports_root.mkdir(parents=True, exist_ok=True)

    check_results: list[dict[str, object]] = []
    failed: list[str] = []
    process_environment = os.environ.copy()
    process_environment["DEVELOPER_DIR"] = process_environment.get(
        "DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"
    )

    for check in manifest["checks"]:
        check_id = check["id"]
        started = time.monotonic()
        result = subprocess.run(
            check["command"],
            cwd=repo_root,
            capture_output=True,
            check=False,
            env=process_environment,
            text=True,
        )
        duration_ms = round((time.monotonic() - started) * 1000)
        status = "passed" if result.returncode == 0 else "failed"
        if status == "failed":
            failed.append(check_id)

        output = (result.stdout or "") + (result.stderr or "")
        log_relative = pathlib.Path(".artifacts") / "checks" / f"{check_id}.log"
        (repo_root / log_relative).write_text(output, encoding="utf-8")
        check_results.append(
            {
                "id": check_id,
                "status": status,
                "exit_code": result.returncode,
                "duration_ms": duration_ms,
                "log_path": str(log_relative),
            }
        )
        print(f"{check_id}: {status}")

    report = {
        "schema_version": 1,
        "started_at": started_at.isoformat().replace("+00:00", "Z"),
        "environment": environment(repo_root),
        "git": git_state(repo_root),
        "passed": not failed,
        "checks": check_results,
        "failed_checks": failed,
    }
    payload = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    write_atomic(reports_root / "latest.json", payload)
    print("report: .artifacts/checks/latest.json")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
