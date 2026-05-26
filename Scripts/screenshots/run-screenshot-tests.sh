#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-compare}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/Scripts/simulator-common.sh"

PROJECT="${SCREENSHOT_PROJECT:-LifeOrganize.xcodeproj}"
SCHEME="${SCREENSHOT_SCHEME:-LifeOrganize}"
DEVICE_NAME="${SCREENSHOT_DEVICE_NAME:-iPhone 17 Pro}"
DEVICE_OS="${SCREENSHOT_DEVICE_OS:-26.2}"
APPEARANCE="${SCREENSHOT_APPEARANCE:-light}"
DEVICE_SLUG="${SCREENSHOT_DEVICE_SLUG:-${DEVICE_NAME// /_}}"
TARGET_KEY="${SCREENSHOT_TARGET_KEY:-$DEVICE_SLUG}"
ORIENTATION="${SCREENSHOT_ORIENTATION:-portrait}"
RESULT_BUNDLE="${SCREENSHOT_RESULT_BUNDLE:-BuildArtifacts/ScreenshotTests-$TARGET_KEY-$ORIENTATION-$APPEARANCE.xcresult}"
ACTUAL_DIR="${SCREENSHOT_ACTUAL_DIR:-BuildArtifacts/screenshots/actual/$TARGET_KEY/$ORIENTATION/$APPEARANCE}"
DIFF_DIR="${SCREENSHOT_DIFF_DIR:-BuildArtifacts/screenshots/diff/$TARGET_KEY/$ORIENTATION/$APPEARANCE}"
BASELINE_DIR="${SCREENSHOT_BASELINE_DIR:-Tests/ScreenshotBaselines/$TARGET_KEY/$ORIENTATION/$APPEARANCE}"
LEGACY_BASELINE_DIR="Tests/ScreenshotBaselines/$TARGET_KEY/$APPEARANCE"
ORIENTATION_CONFIG="$ROOT_DIR/BuildArtifacts/screenshots/orientation.txt"
SCREENSHOT_TESTS=(
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testFirstLaunchAndEmptyTimelineScreenshots"
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testTimelineScreenshot"
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testThingsAndThingDetailScreenshots"
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testCarryForwardScreenshot"
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testSearchScreenshot"
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testReviewQueueScreenshot"
  "LifeOrganizeUITests/LifeOrganizeScenarioUITests/testHeavyTimelineScreenshot"
)

case "$MODE" in
  compare|update) ;;
  *)
    echo "Usage: $0 [compare|update]" >&2
    exit 2
    ;;
esac

case "$ORIENTATION" in
  portrait|landscape) ;;
  *)
    echo "Unsupported SCREENSHOT_ORIENTATION: $ORIENTATION" >&2
    echo "Expected one of: portrait, landscape" >&2
    exit 2
    ;;
esac

print_failure_help() {
  if [[ "$MODE" == "compare" ]]; then
    cat >&2 <<EOF
Screenshot comparison failed.
Failure artifacts:
  result bundle: $RESULT_BUNDLE
  actual PNGs:   $ACTUAL_DIR
  diff PNGs:     $DIFF_DIR
  baselines:     $BASELINE_DIR
Baseline updates are manual. To accept an intentional visual change, run:
  Scripts/screenshots/run-screenshot-tests.sh update
EOF
  fi
}

trap print_failure_help ERR
cleanup_orientation_config() {
  rm -f "$ORIENTATION_CONFIG"
}
trap cleanup_orientation_config EXIT

cd "$ROOT_DIR"

if [[ "$MODE" == "compare" && ! -d "$BASELINE_DIR" && -z "${SCREENSHOT_TARGET_KEY:-}" && -z "${SCREENSHOT_ORIENTATION:-}" && -d "$LEGACY_BASELINE_DIR" ]]; then
  BASELINE_DIR="$LEGACY_BASELINE_DIR"
fi

if [[ "$MODE" == "compare" && ! -d "$BASELINE_DIR" ]]; then
  cat >&2 <<EOF
Screenshot baseline directory is missing: $BASELINE_DIR
Run Scripts/screenshots/run-screenshot-tests.sh update and commit the generated baselines.
EOF
  exit 2
fi

configure_simulator() {
  local udid
  if ! udid="$(simulator_udid_for "$DEVICE_NAME" "$DEVICE_OS")"; then
    echo "No available simulator found for $DEVICE_NAME iOS $DEVICE_OS" >&2
    return 1
  fi
  configure_simulator_for_ui_capture "$udid" "$APPEARANCE" large
}

configure_simulator

rm -rf "$RESULT_BUNDLE"
ONLY_TESTING_ARGS=()
for test_identifier in "${SCREENSHOT_TESTS[@]}"; do
  ONLY_TESTING_ARGS+=("-only-testing:$test_identifier")
done

export SCREENSHOT_ORIENTATION="$ORIENTATION"
mkdir -p "$(dirname "$ORIENTATION_CONFIG")"
printf '%s\n' "$ORIENTATION" > "$ORIENTATION_CONFIG"

xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$DEVICE_OS" \
  "${ONLY_TESTING_ARGS[@]}" \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO

Scripts/screenshots/extract-xcresult-screenshots.sh "$RESULT_BUNDLE" "$ACTUAL_DIR"

if [[ "$MODE" == "update" ]]; then
  rm -rf "$BASELINE_DIR"
  mkdir -p "$BASELINE_DIR"
  cp "$ACTUAL_DIR"/*.png "$BASELINE_DIR"/
  printf 'Updated baselines in %s\n' "$BASELINE_DIR"
  exit 0
fi

Scripts/screenshots/compare-screenshots.swift \
  --baseline "$BASELINE_DIR" \
  --actual "$ACTUAL_DIR" \
  --diff "$DIFF_DIR"
