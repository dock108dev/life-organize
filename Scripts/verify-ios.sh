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

run xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -enableCodeCoverage YES \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=

if [[ "$SKIP_COVERAGE_GATE" != "1" ]]; then
  run "$ROOT_DIR/Scripts/ios_coverage_gate.py" "$RESULT_BUNDLE" --threshold "$COVERAGE_THRESHOLD"
fi
