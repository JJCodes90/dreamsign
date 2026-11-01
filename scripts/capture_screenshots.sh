#!/usr/bin/env bash
# Captures every showcase screen on the iPhone Duo simulator (cover and inner displays) and on a
# standard iPhone, using only Apple's simctl.
#
#   scripts/capture_screenshots.sh <path/to/Dreamsign.app> <output-dir>
#
# Fold poses (book / laptop) can't be scripted with Apple's tools yet. Capture those by hand in
# Xcode's Device Hub or on a device.
set -uo pipefail

APP="$1"
OUT="$2"
BUNDLE_ID="com.jjcodes.dreamsign"
mkdir -p "$OUT"

SCREENS="alarms journal insights learn lesson reality ssild nightstand onboarding alarm-editor wbtb entry settings wake-shake wake-journal wake-math wake-complete mild sleep"

runtime_for() { # device name → newest runtime identifier that offers it
  xcrun simctl list devicetypes -j >/dev/null
  xcrun simctl list runtimes -j | python3 -c '
import json, sys
name = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["platform"] == "iOS"]
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
for r in reversed(runtimes):
    if any(d["name"] == name for d in r.get("supportedDeviceTypes", [])):
        print(r["identifier"]); break
' "$1"
}

capture_device() { # device-name prefix displays...
  local device="$1" prefix="$2"; shift 2
  local runtime udid
  runtime=$(runtime_for "$device")
  if [ -z "$runtime" ]; then echo "no runtime for $device"; return; fi
  udid=$(xcrun simctl create "Shots $prefix" "$device" "$runtime")
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance dark || true
  xcrun simctl status_bar "$udid" override --time "6:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"

  for screen in $SCREENS; do
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -showcase "$screen" >/dev/null
    sleep 4
    if [ "$#" -eq 0 ]; then
      xcrun simctl io "$udid" screenshot "$OUT/$prefix--$screen.png" >/dev/null 2>&1 \
        && echo "captured $prefix / $screen" || echo "FAILED $prefix / $screen"
    else
      for display in "$@"; do
        local label="${display%%=*}" id="${display#*=}"
        xcrun simctl io "$udid" screenshot --display="$id" "$OUT/$prefix-$label--$screen.png" >/dev/null 2>&1 \
          && echo "captured $prefix-$label / $screen" || echo "FAILED $prefix-$label / $screen"
      done
    fi
  done

  xcrun simctl shutdown "$udid" >/dev/null 2>&1
  xcrun simctl delete "$udid" >/dev/null 2>&1
}

# iPhone Duo: LCD is the cover display, LCD-1 the inner one. The app shows on whichever is active.
capture_device "iPhone Duo" "duo" "cover=LCD" "inner=LCD-1"
# A standard iPhone, for comparison.
capture_device "iPhone 17" "iphone17"

ls -1 "$OUT"/*.png 2>/dev/null | wc -l | xargs echo "screenshots:"
