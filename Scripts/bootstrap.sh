#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

/usr/bin/xcodebuild -version
/usr/bin/xcrun swift --version
"$repo_root/Scripts/architecture-check.sh"
/usr/bin/xcodebuild -project "$repo_root/MeetingInsight.xcodeproj" -list

print "Meeting Insight bootstrap prerequisites are available."
