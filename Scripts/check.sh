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
    -packageCachePath "$artifacts_root/cache/xcode-packages" \
    CODE_SIGNING_ALLOWED=NO \
    build
}

test_package() {
  /usr/bin/xcrun swift test "${swift_arguments[@]}"
}

test_package_filter() {
  /usr/bin/xcrun swift test "${swift_arguments[@]}" --filter "$1"
}

test_app() {
  /usr/bin/xcodebuild \
    -project "$repo_root/MeetingInsight.xcodeproj" \
    -scheme MeetingInsight \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifacts_root/DerivedData" \
    -packageCachePath "$artifacts_root/cache/xcode-packages" \
    CODE_SIGNING_ALLOWED=NO \
    test
}

test_app_shell() {
  /usr/bin/xcodebuild \
    -project "$repo_root/MeetingInsight.xcodeproj" \
    -scheme MeetingInsight \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifacts_root/DerivedData" \
    -packageCachePath "$artifacts_root/cache/xcode-packages" \
    CODE_SIGNING_ALLOWED=NO \
    test \
    -only-testing:MeetingInsightAppTests
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
  fixture)
    /usr/bin/python3 "$repo_root/Scripts/fixture_check.py"
    ;;
  scope-containment)
    test_package_filter LocalKnowledgeContainmentTests
    ;;
  scope-source)
    test_package_filter 'RepositorySnapshotTests|RepoResolverTests|ResearchScopeStoreTests|GitProcessTests'
    ;;
  knowledge-snapshot)
    test_package_filter KnowledgeSnapshotTests
    ;;
  evidence-integrity)
    test_package_filter 'EvidenceValidatorTests|ConfidenceCalculatorTests'
    ;;
  agent-readonly)
    test_package_filter 'CodexCommandBuilderTests|AgentPromptBuilderTests|CodexProcessRunnerTests|CodexExecutableResolverTests|CodexDoctorTests'
    ;;
  agent-source-policy)
    test_package_filter 'CodexEventDecoderTests|CodexSourcePolicyTests'
    ;;
  vertical-slice)
    test_package_filter 'EvidenceVerticalSliceTests|MeetingInsightCLIApplication'
    ;;
  app-shell)
    test_app_shell
    ;;
  app-service)
    test_package_filter 'AppSettingsStoreTests|MeetingInsightAppService'
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
    print -u2 "usage: Scripts/check.sh [build|test|fixture|scope-containment|scope-source|knowledge-snapshot|evidence-integrity|agent-readonly|agent-source-policy|vertical-slice|app-shell|app-service|architecture|privacy|cli]"
    exit 64
    ;;
esac
