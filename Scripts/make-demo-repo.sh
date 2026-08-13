#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
source_root="$repo_root/Fixtures/DemoRepo"
output_path="${1:-$repo_root/.artifacts/fixtures/DemoRepo}"
output_path="${output_path:A}"

if [[ ! -d "$source_root" ]]; then
  print -u2 "DemoRepo source is missing: $source_root"
  exit 1
fi

if [[ -e "$output_path" ]]; then
  print -u2 "output already exists: $output_path"
  exit 1
fi

/bin/mkdir -p "${output_path:h}"
/bin/mkdir "$output_path"
/bin/cp "$source_root/Package.swift" "$source_root/README.md" "$output_path/"
/bin/cp -R "$source_root/Config" "$source_root/Sources" "$source_root/Tests" "$output_path/"

/usr/bin/git -C "$output_path" init --quiet --initial-branch=main
/usr/bin/git -C "$output_path" config core.autocrlf false
/usr/bin/git -C "$output_path" config core.filemode true
/usr/bin/git -C "$output_path" config core.excludesFile /dev/null
/usr/bin/git -C "$output_path" add --all

/usr/bin/env \
  GIT_AUTHOR_NAME="Demo Fixture" \
  GIT_AUTHOR_EMAIL="fixture@example.invalid" \
  GIT_AUTHOR_DATE="2026-01-01T00:00:00+0000" \
  GIT_COMMITTER_NAME="Demo Fixture" \
  GIT_COMMITTER_EMAIL="fixture@example.invalid" \
  GIT_COMMITTER_DATE="2026-01-01T00:00:00+0000" \
  /usr/bin/git -C "$output_path" \
    -c commit.gpgSign=false \
    commit --quiet --no-gpg-sign --cleanup=verbatim \
    --message="Create deterministic synthetic repository"

/usr/bin/git -C "$output_path" rev-parse HEAD
