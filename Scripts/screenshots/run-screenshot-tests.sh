#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-compare}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="${SCREENSHOT_PROJECT:-LifeOrganize.xcodeproj}"
SCHEME="${SCREENSHOT_SCHEME:-LifeOrganize}"
DEVICE_NAME="${SCREENSHOT_DEVICE_NAME:-iPhone 16}"
DEVICE_OS="${SCREENSHOT_DEVICE_OS:-18.6}"
APPEARANCE="${SCREENSHOT_APPEARANCE:-light}"
DEVICE_DIR="${DEVICE_NAME// /_}"
RESULT_BUNDLE="${SCREENSHOT_RESULT_BUNDLE:-BuildArtifacts/ScreenshotTests.xcresult}"
ACTUAL_DIR="${SCREENSHOT_ACTUAL_DIR:-BuildArtifacts/screenshots/actual/$DEVICE_DIR/$APPEARANCE}"
DIFF_DIR="${SCREENSHOT_DIFF_DIR:-BuildArtifacts/screenshots/diff/$DEVICE_DIR/$APPEARANCE}"
BASELINE_DIR="${SCREENSHOT_BASELINE_DIR:-Tests/ScreenshotBaselines/$DEVICE_DIR/$APPEARANCE}"

case "$MODE" in
  compare|update) ;;
  *)
    echo "Usage: $0 [compare|update]" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

simulator_udid() {
  python3 - "$DEVICE_NAME" "$DEVICE_OS" <<'PY'
import json
import subprocess
import sys

name = sys.argv[1]
os_version = sys.argv[2].replace(".", "-")
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
for runtime, devices in payload.get("devices", {}).items():
    if os_version and not runtime.endswith(f"iOS-{os_version}"):
        continue
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
PY
}

configure_simulator() {
  local udid
  if ! udid="$(simulator_udid)"; then
    echo "No available simulator found for $DEVICE_NAME iOS $DEVICE_OS" >&2
    return 1
  fi
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  xcrun simctl status_bar "$udid" override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiMode active \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --operatorName "" \
    --batteryState charged \
    --batteryLevel 100 >/dev/null 2>&1 || true
  xcrun simctl ui "$udid" appearance "$APPEARANCE" >/dev/null 2>&1 || true
  xcrun simctl ui "$udid" content_size large >/dev/null 2>&1 || true
}

configure_simulator

rm -rf "$RESULT_BUNDLE"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$DEVICE_OS" \
  -only-testing:LifeOrganizeUITests/LifeOrganizeScreenshotTests \
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
