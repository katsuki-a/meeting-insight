#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
package_root="$repo_root/Packages/MeetingInsightKit"
rules_path="$repo_root/Harness/architecture-rules.json"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$repo_root/.artifacts/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.artifacts/cache/swiftpm-module"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

/usr/bin/python3 "$repo_root/Scripts/architecture_check.py" \
  --package-root "$package_root" \
  --rules "$rules_path" \
  "$@"
