#!/usr/bin/env bash
# Captures every showcase screen on the iPhone Duo simulator's cover display, using only
# Apple's simctl.
#
#   scripts/capture_screenshots.sh <path/to/Dreamsign.app> <output-dir>
#
# The simulator boots closed, so the inner display is off. Open and folded poses can't be
# scripted with Apple's tools yet; capture those in Xcode's Device Hub or on a device.
set -uo pipefail

APP="$1"
OUT="$2"
BUNDLE_ID="com.jjcodes.dreamsign"
DEVICE="iPhone Duo"
mkdir -p "$OUT"

# macOS has no `timeout`; perl's alarm does the job. Kills a simctl call that hangs.
limit() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }
log() { echo "[$(date +%H:%M:%S)] $*"; }

SCREENS="alarms journal insights learn lesson reality ssild nightstand onboarding alarm-editor wbtb entry settings wake-shake wake-journal wake-math wake-complete mild sleep"

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["platform"] == "iOS"]
runtimes.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
for r in reversed(runtimes):
    if any(d["name"] == sys.argv[1] for d in r.get("supportedDeviceTypes", [])):
        print(r["identifier"]); break
' "$DEVICE")

UDID=$(xcrun simctl create "Dreamsign Shots" "$DEVICE" "$RUNTIME")
log "booting $DEVICE ($RUNTIME)"
xcrun simctl boot "$UDID"
limit 600 xcrun simctl bootstatus "$UDID" -b >/dev/null || log "bootstatus timed out"
log "booted"
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override --time "6:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
limit 120 xcrun simctl install "$UDID" "$APP" || log "install failed"

size_of() { stat -f%z "$1" 2>/dev/null || echo 0; }

diagnose() { # screen
  if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    log "  app process is running (looks like a hang or slow first frame)"
  else
    log "  app process is NOT running (looks like a crash)"
  fi
  limit 60 xcrun simctl spawn "$UDID" log show --last 20s --style compact \
    --predicate 'process == "Dreamsign"' 2>/dev/null \
    | grep -iE "fault|error|fatal|crash|exception|assert|precondition|hang|swiftdata" | tail -25 | sed 's/^/    /'
}

shoot() { # screen
  local screen="$1" file="$OUT/duo--$1.png"
  limit 60 xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -showcase "$screen" >/dev/null \
    || log "launch failed: $screen"
  sleep 5
  limit 30 xcrun simctl io "$UDID" screenshot --display=LCD "$file" >/dev/null 2>&1 || log "screenshot failed: $screen"
  # A frame with only the launch color is ~150 KB; real screens are 500 KB+. Nightstand is
  # intentionally near-black, so it's exempt.
  if [ "$screen" != "nightstand" ] && [ "$(size_of "$file")" -lt 300000 ]; then
    log "$screen looks blank ($(size_of "$file") bytes); retrying in 10 s"
    diagnose "$screen"
    sleep 10
    limit 30 xcrun simctl io "$UDID" screenshot --display=LCD "$file" >/dev/null 2>&1 || true
    [ "$(size_of "$file")" -lt 300000 ] && { log "$screen still blank"; diagnose "$screen"; mv "$file" "$OUT/blank--$screen.png"; return; }
  fi
  log "captured $screen ($(size_of "$file") bytes)"
}

for screen in $SCREENS; do shoot "$screen"; done

log "crash reports:"
for report in $(ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i dreamsign | head -3); do
  echo "---- $report"
  python3 - "$HOME/Library/Logs/DiagnosticReports/$report" <<'PY' || head -c 4000 "$HOME/Library/Logs/DiagnosticReports/$report"
import json, sys
text = open(sys.argv[1]).read()
header, _, body = text.partition("\n")
report = json.loads(body)
print("exception:", report.get("exception"))
print("termination:", report.get("termination", {}).get("indicator"), report.get("asi"))
images = report.get("usedImages", [])
for thread in report.get("threads", []):
    if thread.get("triggered"):
        for frame in thread.get("frames", [])[:25]:
            image = images[frame.get("imageIndex", 0)].get("name", "?") if images else "?"
            print("  ", image, frame.get("symbol", "?"))
PY
done

limit 120 xcrun simctl shutdown "$UDID" >/dev/null 2>&1
limit 120 xcrun simctl delete "$UDID" >/dev/null 2>&1
ls -1 "$OUT"/duo--*.png 2>/dev/null | wc -l | xargs echo "screenshots:"
