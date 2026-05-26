#!/usr/bin/env bash

simulator_udid_for() {
  local device_name="$1"
  local device_os="$2"

  python3 - "$device_name" "$device_os" <<'PY'
import json
import subprocess
import sys

name = sys.argv[1]
os_version = sys.argv[2].replace(".", "-")
payload = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
matches = []
for runtime, devices in payload.get("devices", {}).items():
    if os_version and not runtime.endswith(f"iOS-{os_version}"):
        continue
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            matches.append(device)
for device in sorted(matches, key=lambda item: item.get("state") != "Booted"):
    print(device["udid"])
    sys.exit(0)
sys.exit(1)
PY
}

user_app_bundle_ids_for() {
  local udid="$1"

  python3 - "$udid" <<'PY'
import json
import subprocess
import sys

udid = sys.argv[1]
plist = subprocess.check_output(["xcrun", "simctl", "listapps", udid])
payload = subprocess.check_output(["plutil", "-convert", "json", "-o", "-", "-"], input=plist)
for bundle_id, metadata in json.loads(payload).items():
    if metadata.get("ApplicationType") == "User":
        print(bundle_id)
PY
}

configure_simulator_for_ui_capture() {
  local udid="$1"
  local appearance="$2"
  local content_size="$3"
  local bundle_id

  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  while IFS= read -r bundle_id; do
    xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  done < <(user_app_bundle_ids_for "$udid")
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
  xcrun simctl ui "$udid" appearance "$appearance" >/dev/null 2>&1 || true
  xcrun simctl ui "$udid" content_size "$content_size" >/dev/null 2>&1 || true
}
