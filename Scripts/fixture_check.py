#!/usr/bin/env python3

import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import uuid


CARD_PROPERTIES = {
    "schema_version",
    "request_id",
    "verdict",
    "headline",
    "answer",
    "scope",
    "claims",
    "open_questions",
}
EXPECTED_VERDICTS = {"verified", "contradicted", "not_found"}
BANNED_FIXTURE_TEXT = (
    "BEGIN PRIVATE KEY",
    "api_key",
    "client_secret",
    "Claude",
    "Codex",
    "Zoom",
)


class FixtureError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FixtureError(message)


def load_json(path: pathlib.Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise FixtureError(f"missing fixture file: {path}") from error
    except json.JSONDecodeError as error:
        raise FixtureError(f"invalid JSON fixture: {path}: {error}") from error


def run(arguments: list[str], cwd: pathlib.Path) -> str:
    result = subprocess.run(arguments, cwd=cwd, capture_output=True, check=False, text=True)
    if result.returncode != 0:
        output = (result.stdout or "") + (result.stderr or "")
        raise FixtureError(f"command failed ({result.returncode}): {' '.join(arguments)}\n{output}")
    return result.stdout.strip()


def directory_revision(root: pathlib.Path) -> tuple[str, list[str]]:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    digest = hashlib.sha256()
    relative_paths: list[str] = []
    for path in files:
        relative = path.relative_to(root).as_posix()
        relative_paths.append(relative)
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest(), relative_paths


def build_repository_twice(
    repo_root: pathlib.Path,
    manifest: dict[str, object],
) -> tuple[str, pathlib.Path, tempfile.TemporaryDirectory[str]]:
    temporary = tempfile.TemporaryDirectory(prefix="meeting-insight-fixture-")
    temporary_root = pathlib.Path(temporary.name)
    script = repo_root / "Scripts" / "make-demo-repo.sh"
    first = temporary_root / "first" / "DemoRepo"
    second = temporary_root / "second" / "DemoRepo"

    run([str(script), str(first)], repo_root)
    run([str(script), str(second)], repo_root)

    first_sha = run(["/usr/bin/git", "rev-parse", "HEAD"], first)
    second_sha = run(["/usr/bin/git", "rev-parse", "HEAD"], second)
    require(first_sha == second_sha, "DemoRepo generation produced different commits")
    require(first_sha == manifest["expected_commit_sha"], "DemoRepo commit differs from manifest")

    tracked = run(["/usr/bin/git", "ls-files"], first).splitlines()
    require(tracked == manifest["tracked_files"], "DemoRepo tracked files differ from manifest")
    source_root = repo_root / str(manifest["source_path"])
    source_files = sorted(path.relative_to(source_root).as_posix() for path in source_root.rglob("*") if path.is_file())
    require(source_files == tracked, "DemoRepo source files differ from manifest")

    run(
        [
            "/usr/bin/xcrun",
            "swift",
            "test",
            "--disable-sandbox",
            "--package-path",
            str(first),
            "--cache-path",
            str(temporary_root / "swift-cache"),
            "--scratch-path",
            str(temporary_root / "swift-build"),
        ],
        repo_root,
    )
    require(not run(["/usr/bin/git", "status", "--porcelain=v1"], first), "DemoRepo is dirty")
    return first_sha, first, temporary


def quoted_lines(path: pathlib.Path, line_start: int, line_end: int) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    require(1 <= line_start <= line_end <= len(lines), f"invalid evidence range: {path}")
    return "\n".join(lines[line_start - 1 : line_end])


def verify_evidence(
    evidence: dict[str, object],
    generated_repo: pathlib.Path,
    wiki_root: pathlib.Path,
    repo_sha: str,
    wiki_revision: str,
) -> None:
    source_name = evidence["source_name"]
    relative = pathlib.PurePosixPath(str(evidence["path"]))
    require(not relative.is_absolute() and ".." not in relative.parts, "unsafe evidence path")

    if source_name == "DemoRepo":
        source_root = generated_repo
        require(evidence["source_revision"] == repo_sha, "repository evidence revision mismatch")
    elif source_name == "DemoWiki":
        source_root = wiki_root
        require(evidence["source_revision"] == wiki_revision, "wiki evidence revision mismatch")
    else:
        raise FixtureError(f"unknown fixture evidence source: {source_name}")

    source = source_root.joinpath(*relative.parts)
    require(source.is_file(), f"evidence source is missing: {relative}")
    quote = quoted_lines(source, int(evidence["line_start"]), int(evidence["line_end"]))
    require(evidence["quote"] == quote, f"evidence quote differs from source: {relative}")
    actual_hash = hashlib.sha256(quote.encode("utf-8")).hexdigest()
    require(evidence["quote_sha256"] == actual_hash, f"evidence quote hash mismatch: {relative}")


def verify_scenarios(
    repo_root: pathlib.Path,
    manifest: dict[str, object],
    generated_repo: pathlib.Path,
    repo_sha: str,
    wiki_revision: str,
) -> int:
    questions_path = repo_root / str(manifest["questions_path"])
    questions_document = load_json(questions_path)
    require(isinstance(questions_document, dict), "questions fixture must be an object")
    questions = questions_document.get("scenarios")
    require(isinstance(questions, list) and len(questions) == 3, "exactly three scenarios are required")

    actual_verdicts: set[str] = set()
    request_ids: set[str] = set()
    wiki_root = repo_root / str(manifest["demo_wiki"]["root_path"])
    for scenario in questions:
        require(isinstance(scenario, dict), "scenario must be an object")
        card_path = repo_root / str(scenario["expected_card"])
        card = load_json(card_path)
        require(isinstance(card, dict), f"card must be an object: {card_path}")
        require(set(card) == CARD_PROPERTIES, f"card properties differ from schema: {card_path}")
        require(card["schema_version"] == 1, f"unsupported card schema: {card_path}")
        uuid.UUID(str(card["request_id"]))
        require(card["request_id"] == scenario["request_id"], f"request id mismatch: {card_path}")
        require(card["verdict"] == scenario["expected_verdict"], f"verdict mismatch: {card_path}")
        require(card["request_id"] not in request_ids, "scenario request IDs must be unique")
        request_ids.add(str(card["request_id"]))
        actual_verdicts.add(str(card["verdict"]))

        scope = card["scope"]
        repositories = scope["repositories"]
        require(len(repositories) == 1, f"fixture card must select one repository: {card_path}")
        require(repositories[0]["commit_sha"] == repo_sha, f"card repository SHA mismatch: {card_path}")
        knowledge_roots = scope["knowledge_roots"]
        require(len(knowledge_roots) == 1, f"fixture card must include DemoWiki: {card_path}")
        require(knowledge_roots[0]["revision"] == wiki_revision, f"card wiki revision mismatch: {card_path}")

        evidence_paths: set[str] = set()
        for claim in card["claims"]:
            for evidence in claim["evidence"]:
                evidence_paths.add(str(evidence["path"]))
                verify_evidence(evidence, generated_repo, wiki_root, repo_sha, wiki_revision)

        require(
            evidence_paths == set(scenario["required_evidence_paths"]),
            f"required evidence paths differ from card: {card_path}",
        )
        require(
            all(isinstance(claim, str) and claim for claim in scenario["forbidden_claims"]),
            f"forbidden claims must be non-empty strings: {questions_path}",
        )

        if card["verdict"] == "not_found":
            require(not card["claims"], "not_found fixture must not invent claims")

    require(actual_verdicts == EXPECTED_VERDICTS, "fixtures must cover verified, contradicted, and not_found")
    return len(questions)


def verify_synthetic_content(repo_root: pathlib.Path) -> None:
    fixture_roots = [
        repo_root / "Fixtures" / "DemoRepo",
        repo_root / "Fixtures" / "DemoWiki",
        repo_root / "Fixtures" / "ExpectedCards",
    ]
    for fixture_root in fixture_roots:
        for path in fixture_root.rglob("*"):
            if not path.is_file():
                continue
            text = path.read_text(encoding="utf-8")
            for banned in BANNED_FIXTURE_TEXT:
                require(banned not in text, f"fixture contains banned real or sensitive term: {path}: {banned}")

    questions = (repo_root / "Fixtures" / "questions.json").read_text(encoding="utf-8")
    for banned in BANNED_FIXTURE_TEXT:
        require(banned not in questions, f"questions fixture contains banned real or sensitive term: {banned}")


def main() -> int:
    repo_root = pathlib.Path(__file__).resolve().parent.parent
    try:
        manifest_document = load_json(repo_root / "Fixtures" / "fixture-manifest.json")
        require(isinstance(manifest_document, dict), "fixture manifest must be an object")
        manifest = manifest_document

        repository_manifest = manifest["demo_repository"]
        require(isinstance(repository_manifest, dict), "demo_repository manifest must be an object")
        repo_sha, generated_repo, temporary = build_repository_twice(
            repo_root,
            repository_manifest,
        )
        try:
            wiki_manifest = manifest["demo_wiki"]
            require(isinstance(wiki_manifest, dict), "demo_wiki manifest must be an object")
            wiki_root = repo_root / str(wiki_manifest["root_path"])
            wiki_revision, wiki_files = directory_revision(wiki_root)
            require(wiki_revision == wiki_manifest["expected_revision"], "DemoWiki revision differs from manifest")
            require(wiki_files == wiki_manifest["files"], "DemoWiki files differ from manifest")

            scenario_count = verify_scenarios(
                repo_root,
                manifest,
                generated_repo,
                repo_sha,
                wiki_revision,
            )
            verify_synthetic_content(repo_root)
        finally:
            temporary.cleanup()

        report = {
            "schema_version": 1,
            "demo_repository_commit": repo_sha,
            "demo_wiki_revision": wiki_revision,
            "scenario_count": scenario_count,
            "verdicts": sorted(EXPECTED_VERDICTS),
        }
        report_path = repo_root / ".artifacts" / "fixtures" / "latest.json"
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"fixture_sha: {repo_sha}")
        print(f"wiki_revision: {wiki_revision}")
        print("fixture contract checks passed")
        return 0
    except (FixtureError, KeyError, TypeError, ValueError) as error:
        print(f"fixture contract failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
