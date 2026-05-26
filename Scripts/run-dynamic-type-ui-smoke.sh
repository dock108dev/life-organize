#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/Scripts/simulator-common.sh"

usage() {
  cat <<'EOF'
Usage: Scripts/run-dynamic-type-ui-smoke.sh

Runs Dynamic Type UI smoke tests for normal, large, Accessibility Large,
and Accessibility XXXL text sizes. Result bundles are written under
BuildArtifacts/DynamicTypeSmoke by default.
EOF
}

case "${1:-}" in
  "")
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

PROJECT="${DYNAMIC_TYPE_PROJECT:-LifeOrganize.xcodeproj}"
SCHEME="${DYNAMIC_TYPE_SCHEME:-LifeOrganize}"
DEVICE_NAME="${DYNAMIC_TYPE_DEVICE_NAME:-iPhone 17 Pro}"
DEVICE_OS="${DYNAMIC_TYPE_DEVICE_OS:-26.2}"
APPEARANCE="${DYNAMIC_TYPE_APPEARANCE:-light}"
RESULT_ROOT="${DYNAMIC_TYPE_RESULT_ROOT:-BuildArtifacts/DynamicTypeSmoke}"
TEST_EXECUTION_ALLOWANCE="${DYNAMIC_TYPE_TEST_EXECUTION_ALLOWANCE:-300}"

DYNAMIC_TYPE_TESTS=(
  "normal|medium|LifeOrganizeUITests/DynamicTypeSmokeUITests/testNormalTextSizeCoreControlsStayReachable"
  "large|large|LifeOrganizeUITests/DynamicTypeSmokeUITests/testLargeTextSizeCoreControlsStayReachable"
  "accessibility-large|accessibility-large|LifeOrganizeUITests/DynamicTypeSmokeUITests/testAccessibilityLargeTextSizeCoreControlsStayReachable"
  "accessibility-extra-extra-extra-large|accessibility-extra-extra-extra-large|LifeOrganizeUITests/DynamicTypeSmokeUITests/testAccessibilityXXXLTextSizeCoreControlsStayReachable"
)

cd "$ROOT_DIR"

configure_simulator() {
  local udid="$1"
  local content_size="$2"

  configure_simulator_for_ui_capture "$udid" "$APPEARANCE" "$content_size"
}

if ! UDID="$(simulator_udid_for "$DEVICE_NAME" "$DEVICE_OS")"; then
  echo "No available simulator found for $DEVICE_NAME iOS $DEVICE_OS" >&2
  exit 1
fi

mkdir -p "$RESULT_ROOT"

for entry in "${DYNAMIC_TYPE_TESTS[@]}"; do
  IFS='|' read -r label content_size test_identifier <<< "$entry"
  result_bundle="$RESULT_ROOT/$label.xcresult"
  rm -rf "$result_bundle"

  printf 'Running Dynamic Type smoke: %s (%s)\n' "$label" "$content_size"
  configure_simulator "$UDID" "$content_size"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    "-only-testing:$test_identifier" \
    -resultBundlePath "$result_bundle" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$TEST_EXECUTION_ALLOWANCE" \
    -maximum-test-execution-time-allowance "$TEST_EXECUTION_ALLOWANCE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=
done
