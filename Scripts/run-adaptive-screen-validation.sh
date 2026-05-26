#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-compare}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/simulator-common.sh"

PROJECT="${ADAPTIVE_SCREEN_PROJECT:-LifeOrganize.xcodeproj}"
SCHEME="${ADAPTIVE_SCREEN_SCHEME:-LifeOrganize}"
DEVICE_OS="${ADAPTIVE_SCREEN_DEVICE_OS:-26.2}"
APPEARANCE="${ADAPTIVE_SCREEN_APPEARANCE:-light}"
ARTIFACT_ROOT="${ADAPTIVE_SCREEN_ARTIFACT_ROOT:-BuildArtifacts/AdaptiveScreenValidation}"
IPHONE_DEVICE="${ADAPTIVE_SCREEN_IPHONE_DEVICE:-iPhone 17 Pro}"
IPAD_PRO_DEVICE="${ADAPTIVE_SCREEN_IPAD_PRO_DEVICE:-iPad Pro 13-inch (M5)}"
SMALL_IPAD_CANDIDATES="${ADAPTIVE_SCREEN_SMALL_IPAD_CANDIDATES:-iPad mini (A17 Pro)|iPad (A16)|iPad Air 11-inch (M3)|iPad Pro 11-inch (M5)}"
SCREENSHOT_ATTEMPTS="${ADAPTIVE_SCREEN_SCREENSHOT_ATTEMPTS:-2}"

SCREENSHOT_CELLS=(
  "iPhone_17_Pro|$IPHONE_DEVICE|portrait"
  "iPhone_17_Pro|$IPHONE_DEVICE|landscape"
  "iPad_Pro_13-inch_M5|$IPAD_PRO_DEVICE|portrait"
  "iPad_Pro_13-inch_M5|$IPAD_PRO_DEVICE|landscape"
)

ADAPTIVE_SHELL_TESTS=(
  "compact-iphone|$IPHONE_DEVICE|portrait|LifeOrganizeUITests/AdaptiveShellUITests/testCompactLaunchKeepsTabsAndUtilityModals"
  "regular-ipad-pro-landscape|$IPAD_PRO_DEVICE|landscape|LifeOrganizeUITests/AdaptiveShellUITests/testRegularWidthSidebarShowsWorkspaceUtilitiesAndConditionalReview"
  "regular-ipad-pro-start-routes|$IPAD_PRO_DEVICE|landscape|LifeOrganizeUITests/AdaptiveShellUITests/testRegularWidthScreenshotStartsRouteToSidebarDestinations"
)

case "$MODE" in
  compare|update) ;;
  -h|--help)
    cat <<'EOF'
Usage: Scripts/run-adaptive-screen-validation.sh [compare|update]

Runs the local adaptive screen matrix:
  - iPhone 17 Pro portrait and landscape screenshot comparison
  - iPad Pro portrait and landscape screenshot comparison
  - smaller iPad portrait adaptive shell smoke when available locally
  - Large, Accessibility Large, and Accessibility XXXL Dynamic Type smoke
  - compact and regular adaptive shell UI checks

compare is read-only for committed screenshot baselines. update refreshes only
the screenshot baseline cells that this matrix owns.
EOF
    exit 0
    ;;
  *)
    echo "Usage: Scripts/run-adaptive-screen-validation.sh [compare|update]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"
mkdir -p "$ARTIFACT_ROOT"

if [[ ! "$SCREENSHOT_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ADAPTIVE_SCREEN_SCREENSHOT_ATTEMPTS must be a positive integer." >&2
  exit 2
fi

printf 'Adaptive screen validation configuration:\n'
printf '  mode=%s\n' "$MODE"
printf '  device_os=%s\n' "$DEVICE_OS"
printf '  appearance=%s\n' "$APPEARANCE"
printf '  artifact_root=%s\n' "$ARTIFACT_ROOT"
printf '  screenshot_attempts=%s\n' "$SCREENSHOT_ATTEMPTS"
printf '  stage_manager_narrow_window=not covered: CoreSimulator CLI cannot reliably create or size Stage Manager windows for XCTest\n'

require_simulator() {
  local device_name="$1"

  if ! simulator_udid_for "$device_name" "$DEVICE_OS" >/dev/null; then
    echo "Required simulator is unavailable: $device_name iOS $DEVICE_OS" >&2
    return 1
  fi
}

available_simulator_udid() {
  local device_name="$1"

  simulator_udid_for "$device_name" "$DEVICE_OS" 2>/dev/null || true
}

slug_for_device() {
  local device_name="$1"

  printf '%s' "$device_name" \
    | sed -e 's/ (M5)//g' \
      -e 's/ (A17 Pro)//g' \
      -e 's/ (A16)//g' \
      -e 's/[()]/-/g' \
      -e 's/[[:space:]]/_/g' \
      -e 's/__*/_/g' \
      -e 's/_$//'
}

run_screenshot_cell() {
  local target_key="$1"
  local device_name="$2"
  local orientation="$3"
  local attempt=1

  printf '\nRunning screenshot matrix cell: %s %s %s\n' "$target_key" "$orientation" "$APPEARANCE"
  while (( attempt <= SCREENSHOT_ATTEMPTS )); do
    if SCREENSHOT_TARGET_KEY="$target_key" \
      SCREENSHOT_DEVICE_NAME="$device_name" \
      SCREENSHOT_DEVICE_OS="$DEVICE_OS" \
      SCREENSHOT_ORIENTATION="$orientation" \
      SCREENSHOT_APPEARANCE="$APPEARANCE" \
      SCREENSHOT_RESULT_BUNDLE="$ARTIFACT_ROOT/ScreenshotTests-$target_key-$orientation-$APPEARANCE.xcresult" \
      SCREENSHOT_ACTUAL_DIR="BuildArtifacts/screenshots/actual/$target_key/$orientation/$APPEARANCE" \
      SCREENSHOT_DIFF_DIR="BuildArtifacts/screenshots/diff/$target_key/$orientation/$APPEARANCE" \
      SCREENSHOT_BASELINE_DIR="Tests/ScreenshotBaselines/$target_key/$orientation/$APPEARANCE" \
        "$SCRIPT_DIR/screenshots/run-screenshot-tests.sh" "$MODE"; then
      return 0
    fi

    if (( attempt >= SCREENSHOT_ATTEMPTS )); then
      return 1
    fi

    printf 'Retrying screenshot matrix cell after failed capture or comparison: %s %s, attempt %s of %s\n' \
      "$target_key" "$orientation" "$((attempt + 1))" "$SCREENSHOT_ATTEMPTS" >&2
    attempt=$((attempt + 1))
  done
}

run_adaptive_shell_test() {
  local label="$1"
  local device_name="$2"
  local orientation="$3"
  local test_identifier="$4"
  local udid
  local result_bundle="$ARTIFACT_ROOT/AdaptiveShell-$label.xcresult"

  udid="$(simulator_udid_for "$device_name" "$DEVICE_OS")"
  printf '\nRunning adaptive shell smoke: %s on %s %s\n' "$label" "$device_name" "$orientation"
  configure_simulator_for_ui_capture "$udid" "$APPEARANCE" large
  rm -rf "$result_bundle"
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" \
    "-only-testing:$test_identifier" \
    -resultBundlePath "$result_bundle" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=
}

run_dynamic_type_smoke() {
  printf '\nRunning Dynamic Type smoke matrix: Normal, Large, Accessibility Large, Accessibility XXXL\n'
  DYNAMIC_TYPE_PROJECT="$PROJECT" \
  DYNAMIC_TYPE_SCHEME="$SCHEME" \
  DYNAMIC_TYPE_DEVICE_NAME="$IPHONE_DEVICE" \
  DYNAMIC_TYPE_DEVICE_OS="$DEVICE_OS" \
  DYNAMIC_TYPE_APPEARANCE="$APPEARANCE" \
  DYNAMIC_TYPE_RESULT_ROOT="$ARTIFACT_ROOT/DynamicTypeSmoke" \
    "$SCRIPT_DIR/run-dynamic-type-ui-smoke.sh"
}

append_small_ipad_if_available() {
  local candidate
  local slug
  local udid

  IFS='|' read -r -a candidates <<< "$SMALL_IPAD_CANDIDATES"
  for candidate in "${candidates[@]}"; do
    udid="$(available_simulator_udid "$candidate")"
    if [[ -n "$udid" ]]; then
      slug="$(slug_for_device "$candidate")"
      ADAPTIVE_SHELL_TESTS+=(
        "small-ipad-portrait-$slug|$candidate|portrait|LifeOrganizeUITests/AdaptiveShellUITests/testPadPortraitShellKeepsCoreDestinationsReachable"
      )
      printf '  smaller_ipad_portrait=%s\n' "$candidate"
      return
    fi
  done

  printf '  smaller_ipad_portrait=not covered: no configured candidate exists for iOS %s\n' "$DEVICE_OS"
}

require_simulator "$IPHONE_DEVICE"
require_simulator "$IPAD_PRO_DEVICE"
append_small_ipad_if_available

for cell in "${SCREENSHOT_CELLS[@]}"; do
  IFS='|' read -r target_key device_name orientation <<< "$cell"
  run_screenshot_cell "$target_key" "$device_name" "$orientation"
done

run_dynamic_type_smoke

for entry in "${ADAPTIVE_SHELL_TESTS[@]}"; do
  IFS='|' read -r label device_name orientation test_identifier <<< "$entry"
  run_adaptive_shell_test "$label" "$device_name" "$orientation" "$test_identifier"
done
