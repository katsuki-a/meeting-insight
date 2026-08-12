#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
profile="${1:-fast}"

exec /usr/bin/python3 "$repo_root/Scripts/fitness_runner.py" \
  --repo-root "$repo_root" \
  --manifest "$repo_root/Harness/fitness.json" \
  --profile "$profile"
