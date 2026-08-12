#!/usr/bin/env python3

import argparse
import datetime
import json
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import time
import uuid


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
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=pathlib.Path)
    parser.add_argument("--manifest", required=True, type=pathlib.Path)
    parser.add_argument("--profile", required=True)
    arguments = parser.parse_args()

    repo_root = arguments.repo_root.resolve()
    manifest = json.loads(arguments.manifest.read_text(encoding="utf-8"))
    if arguments.profile not in manifest["profiles"]:
        print(f"unknown fitness profile: {arguments.profile}", file=sys.stderr)
        return 64

    checks_by_id = {check["id"]: check for check in manifest["checks"]}
    selected_ids = manifest["profiles"][arguments.profile]
    run_id = str(uuid.uuid4())
    started_at = datetime.datetime.now(datetime.timezone.utc)
    fitness_root = repo_root / ".artifacts" / "fitness"
    evidence_root = fitness_root / run_id
    evidence_root.mkdir(parents=True, exist_ok=True)

    check_results: list[dict[str, object]] = []
    failed: list[str] = []
    combined_log: list[str] = []
    process_environment = os.environ.copy()
    process_environment["DEVELOPER_DIR"] = process_environment.get(
        "DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"
    )

    for check_id in selected_ids:
        check = checks_by_id[check_id]
        started = time.monotonic()
        result = subprocess.run(
            shlex.split(check["runner"]),
            cwd=repo_root,
            capture_output=True,
            check=False,
            env=process_environment,
            text=True,
        )
        duration_ms = round((time.monotonic() - started) * 1000)
        status = "passed" if result.returncode == check["expect"]["exit_code"] else "failed"
        if status == "failed":
            failed.append(check_id)
        output = (result.stdout or "") + (result.stderr or "")
        evidence_relative = pathlib.Path(".artifacts") / "fitness" / run_id / f"{check_id}.log"
        (repo_root / evidence_relative).write_text(output, encoding="utf-8")
        summary = f"exit code {result.returncode}"
        check_results.append(
            {
                "id": check_id,
                "status": status,
                "duration_ms": duration_ms,
                "summary": summary,
                "evidence_path": str(evidence_relative),
            }
        )
        combined_log.append(f"{check_id}: {status} ({summary})")
        print(f"{check_id}: {status}")

    report = {
        "schema_version": 1,
        "run_id": run_id,
        "profile": arguments.profile,
        "started_at": started_at.isoformat().replace("+00:00", "Z"),
        "environment": environment(repo_root),
        "git": git_state(repo_root),
        "eligible": not failed,
        "checks": check_results,
        "fitness_vector": {},
        "failed_hard_gates": failed,
    }
    payload = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    write_atomic(fitness_root / f"{run_id}.json", payload)
    write_atomic(fitness_root / "latest.json", payload)
    write_atomic(fitness_root / f"{run_id}.log", "\n".join(combined_log) + "\n")
    print("report: .artifacts/fitness/latest.json")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
