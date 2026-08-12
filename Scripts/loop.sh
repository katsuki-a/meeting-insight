#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
work_package="${1:-}"

if [[ ! "$work_package" =~ '^WP-[0-9]{2}$' ]]; then
  print -u2 "usage: Scripts/loop.sh WP-00 [agent-command ...]"
  exit 64
fi

shift
iteration_limit="${MEETING_INSIGHT_LOOP_LIMIT:-3}"

for iteration in {1..$iteration_limit}; do
  print "[$work_package] fitness iteration $iteration/$iteration_limit"
  if "$repo_root/Scripts/fitness.sh" fast; then
    print "[$work_package] fitness fast passed"
    exit 0
  fi

  if (( $# == 0 )); then
    print -u2 "fitness failed; inspect .artifacts/fitness/latest.json"
    exit 1
  fi

  "$@" "Implement $work_package using the repository plan. Inspect the latest fitness report, make one minimal fix, and run the targeted check."
done

print -u2 "[$work_package] stopped after $iteration_limit unsuccessful iterations"
exit 1
