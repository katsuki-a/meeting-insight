#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
package_root="$repo_root/Packages/MeetingInsightKit"
artifacts_root="$repo_root/.artifacts"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$artifacts_root/cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$artifacts_root/cache/swiftpm-module"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

swift_arguments=(
  --disable-sandbox
  --package-path "$package_root"
  --cache-path "$artifacts_root/cache/swiftpm"
  --scratch-path "$artifacts_root/swiftpm-build"
)

build_package() {
  /usr/bin/xcrun swift build "${swift_arguments[@]}"
}

build_app() {
  /usr/bin/xcodebuild \
    -project "$repo_root/MeetingInsight.xcodeproj" \
    -scheme MeetingInsight \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifacts_root/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

test_package() {
  /usr/bin/xcrun swift test "${swift_arguments[@]}"
}

test_app() {
  /usr/bin/xcodebuild \
    -project "$repo_root/MeetingInsight.xcodeproj" \
    -scheme MeetingInsight \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifacts_root/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    test
}

case "${1:-}" in
  "")
    exec /usr/bin/python3 "$repo_root/Scripts/check_runner.py"
    ;;
  build)
    build_package
    build_app
    ;;
  test)
    test_package
    test_app
    ;;
  architecture)
    "$repo_root/Scripts/architecture-check.sh"
    ;;
  privacy)
    /usr/bin/python3 "$repo_root/Scripts/privacy_check.py" "$repo_root"
    ;;
  cli)
    build_package
    "$artifacts_root/swiftpm-build/debug/meeting-insight" --help
    ;;
  *)
    print -u2 "usage: Scripts/check.sh [build|test|architecture|privacy|cli]"
    exit 64
    ;;
esac
