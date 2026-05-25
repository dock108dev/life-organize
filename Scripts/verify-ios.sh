#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-common.sh"

ROOT_DIR="$(script_root)"
PROJECT="${IOS_PROJECT:-LifeOrganize.xcodeproj}"
SCHEME="${IOS_SCHEME:-LifeOrganize}"
DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0}"
RESULT_BUNDLE="${IOS_RESULT_BUNDLE:-BuildArtifacts/LifeOrganizeTests.xcresult}"
DERIVED_DATA="${IOS_DERIVED_DATA:-BuildArtifacts/DerivedData}"
COVERAGE_THRESHOLD="${IOS_COVERAGE_THRESHOLD:-0.80}"
SKIP_COVERAGE_GATE="${IOS_SKIP_COVERAGE_GATE:-0}"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$RESULT_BUNDLE")"
rm -rf "$RESULT_BUNDLE"

printf 'iOS verification configuration:\n'
printf '  IOS_DESTINATION=%s\n' "$DESTINATION"
printf '  IOS_RESULT_BUNDLE=%s\n' "$RESULT_BUNDLE"
printf '  IOS_DERIVED_DATA=%s\n' "$DERIVED_DATA"
printf '  IOS_COVERAGE_THRESHOLD=%s\n' "$COVERAGE_THRESHOLD"
printf '  IOS_SKIP_COVERAGE_GATE=%s\n' "$SKIP_COVERAGE_GATE"
printf '  Failure artifact: %s\n' "$RESULT_BUNDLE"

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
