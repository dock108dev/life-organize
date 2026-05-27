#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/verify-common.sh"
source "$SCRIPT_DIR/simulator-common.sh"

ROOT_DIR="$(script_root)"
PROJECT="${IOS_PROJECT:-LifeOrganize.xcodeproj}"
SCHEME="${IOS_SCHEME:-LifeOrganize}"
DEVICE_NAME="${IOS_DEVICE_NAME:-iPhone 17 Pro}"
DEVICE_OS="${IOS_DEVICE_OS:-26.2}"
RESULT_BUNDLE="${IOS_RESULT_BUNDLE:-BuildArtifacts/LifeOrganizeTests.xcresult}"
DERIVED_DATA="${IOS_DERIVED_DATA:-BuildArtifacts/DerivedData}"
COVERAGE_THRESHOLD="${IOS_COVERAGE_THRESHOLD:-0.80}"
SKIP_COVERAGE_GATE="${IOS_SKIP_COVERAGE_GATE:-0}"

if [[ -n "${IOS_DESTINATION:-}" ]]; then
  DESTINATION="$IOS_DESTINATION"
else
  SIMULATOR_UDID="$(simulator_udid_for "$DEVICE_NAME" "$DEVICE_OS")"
  configure_simulator_for_ui_capture "$SIMULATOR_UDID" light large
  DESTINATION="platform=iOS Simulator,id=$SIMULATOR_UDID"
fi

cd "$ROOT_DIR"
mkdir -p "$(dirname "$RESULT_BUNDLE")"
rm -rf "$RESULT_BUNDLE"

printf 'iOS verification configuration:\n'
printf '  IOS_DEVICE_NAME=%s\n' "$DEVICE_NAME"
printf '  IOS_DEVICE_OS=%s\n' "$DEVICE_OS"
printf '  IOS_DESTINATION=%s\n' "$DESTINATION"
printf '  IOS_RESULT_BUNDLE=%s\n' "$RESULT_BUNDLE"
printf '  IOS_DERIVED_DATA=%s\n' "$DERIVED_DATA"
printf '  IOS_COVERAGE_THRESHOLD=%s\n' "$COVERAGE_THRESHOLD"
printf '  IOS_SKIP_COVERAGE_GATE=%s\n' "$SKIP_COVERAGE_GATE"
printf '  Failure artifact: %s\n' "$RESULT_BUNDLE"

run "$ROOT_DIR/Scripts/ios_static_layout_guard.py"

xcodebuild_result_bundle_passed() {
  local bundle="$1"
  [[ -f "$bundle/Info.plist" ]] || return 1

  local test_summary
  local build_summary
  test_summary="$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null)" || return 1
  build_summary="$(xcrun xcresulttool get build-results --path "$bundle" --format json 2>/dev/null)" || return 1

  TEST_SUMMARY_JSON="$test_summary" BUILD_SUMMARY_JSON="$build_summary" python3 - <<'PY'
import json
import os
import sys

tests = json.loads(os.environ["TEST_SUMMARY_JSON"])
build = json.loads(os.environ["BUILD_SUMMARY_JSON"])

tests_passed = (
    tests.get("result") == "Passed"
    and int(tests.get("failedTests") or 0) == 0
    and not tests.get("testFailures")
)
build_passed = (
    build.get("status") == "succeeded"
    and int(build.get("errorCount") or 0) == 0
    and not build.get("errors")
)
sys.exit(0 if tests_passed and build_passed else 1)
PY
}

printf '\n==> xcodebuild test\n'
set +e
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -enableCodeCoverage YES \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=
xcodebuild_status=$?
set -e

if [[ "$xcodebuild_status" -ne 0 ]]; then
  if xcodebuild_result_bundle_passed "$RESULT_BUNDLE"; then
    printf 'xcodebuild exited %s, but %s reports passed tests and a succeeded build; continuing.\n' "$xcodebuild_status" "$RESULT_BUNDLE" >&2
  else
    exit "$xcodebuild_status"
  fi
fi

if [[ "$SKIP_COVERAGE_GATE" != "1" ]]; then
  run "$ROOT_DIR/Scripts/ios_coverage_gate.py" "$RESULT_BUNDLE" --threshold "$COVERAGE_THRESHOLD"
fi
