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
  if ! test_summary="$(xcrun xcresulttool get test-results summary --path "$bundle" --compact 2>/dev/null)"; then
    printf 'Unable to read xcresult test summary from %s.\n' "$bundle" >&2
    return 1
  fi
  if ! build_summary="$(xcrun xcresulttool get build-results --path "$bundle" --format json 2>/dev/null)"; then
    build_summary='{}'
  fi

  TEST_SUMMARY_JSON="$test_summary" BUILD_SUMMARY_JSON="$build_summary" python3 - <<'PY'
import json
import os
import sys

tests = json.loads(os.environ["TEST_SUMMARY_JSON"])
build = json.loads(os.environ["BUILD_SUMMARY_JSON"])

def int_value(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0

def collect_values(node, key):
    values = []
    if isinstance(node, dict):
        if key in node:
            values.append(node[key])
        for value in node.values():
            values.extend(collect_values(value, key))
    elif isinstance(node, list):
        for value in node:
            values.extend(collect_values(value, key))
    return values

def has_nonempty_collection(node, keys):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in keys and value:
                return True
            if has_nonempty_collection(value, keys):
                return True
    elif isinstance(node, list):
        return any(has_nonempty_collection(value, keys) for value in node)
    return False

passed_count = max([int_value(value) for value in collect_values(tests, "passedTests")] or [0])
failed_count = max([int_value(value) for value in collect_values(tests, "failedTests")] or [0])
skipped_count = max([int_value(value) for value in collect_values(tests, "skippedTests")] or [0])
total_count = max([int_value(value) for value in collect_values(tests, "totalTestCount")] or [0])
executed_count = max(passed_count, total_count - skipped_count)
has_failure_details = has_nonempty_collection(
    tests,
    {"testFailures", "failureSummaries", "failures", "failedTestIdentifiers"},
)
tests_passed = (
    executed_count > 0
    and failed_count == 0
    and not has_failure_details
)
no_build_errors = int(build.get("errorCount") or 0) == 0 and not build.get("errors")
if not tests_passed:
    print("xcresult test summary did not report a clean pass.", file=sys.stderr)
    print(
        "xcresult summary counts: "
        f"passed={passed_count} failed={failed_count} skipped={skipped_count} "
        f"total={total_count} executed={executed_count} "
        f"failureDetails={has_failure_details}",
        file=sys.stderr,
    )
    print(f"xcresult summary keys: {', '.join(sorted(tests.keys()))}", file=sys.stderr)
if not no_build_errors:
    print("xcresult build summary reported build errors.", file=sys.stderr)
sys.exit(0 if tests_passed and no_build_errors else 1)
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
