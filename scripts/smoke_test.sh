#!/usr/bin/env bash
# Build -> install -> cold-launch in a simulator. Proves the app actually
# starts, which a green `xcodebuild build` does not.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/build_lock.sh
build_lock_take "Milepost smoke test"

DEVICE="$(./scripts/sim_udid.sh)"
if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  DEST="platform=iOS Simulator,id=$DEVICE"
else
  DEST="platform=iOS Simulator,name=$DEVICE"
fi
BUNDLE_ID="com.divinedavis.milepost"
DERIVED="build/smoke"

# ship.sh passes the app its tests just built (MILEPOST_SMOKE_APP) instead of
# building a third copy; on its own this script still builds.
if [[ -n "${MILEPOST_SMOKE_APP:-}" && -d "${MILEPOST_SMOKE_APP}" ]]; then
  APP="$MILEPOST_SMOKE_APP"
else
  echo "== build =="
  xcodebuild -project Milepost.xcodeproj -scheme Milepost \
    -destination "$DEST" \
    -derivedDataPath "$DERIVED" \
    -configuration Debug CODE_SIGNING_ALLOWED=NO \
    ENABLE_DEBUG_DYLIB=NO \
    build > /dev/null
  APP="$DERIVED/Build/Products/Debug-iphonesimulator/Milepost.app"
fi
[ -d "$APP" ] || { echo "no app at $APP"; exit 1; }

# XcodeGen quietly drops resources that are declared in the wrong place.
[ -f "$APP/Assets.car" ] || { echo "Assets.car missing from bundle — icon/accent not shipped"; exit 1; }
for key in NSLocationWhenInUseUsageDescription UIBackgroundModes NSHealthUpdateUsageDescription NSHealthShareUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1 || { echo "Info.plist missing $key"; exit 1; }
done

# The watch app rides inside the iPhone app. If the embed phase is missing the
# iOS build still succeeds and TestFlight simply has no watch app, silently.
WATCH_APP="$APP/Watch/MilepostWatch.app"
[ -d "$WATCH_APP" ] || { echo "watch app not embedded at $WATCH_APP"; exit 1; }
for key in WKCompanionAppBundleIdentifier NSHealthUpdateUsageDescription NSLocationWhenInUseUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$WATCH_APP/Info.plist" >/dev/null 2>&1 || { echo "watch Info.plist missing $key"; exit 1; }
done
# WKBackgroundModes, not UIBackgroundModes: watchOS has its own key and the
# wrong one only fails at App Store upload (90362), long after a green build.
/usr/libexec/PlistBuddy -c "Print :WKBackgroundModes" "$WATCH_APP/Info.plist" 2>/dev/null | grep -q workout-processing || {
  echo "watch app missing the workout-processing WKBackgroundModes entry — a run would stop with the wrist down"; exit 1; }
/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$WATCH_APP/Info.plist" >/dev/null 2>&1 && {
  echo "watch app has UIBackgroundModes — watchOS wants WKBackgroundModes; the App Store will reject this"; exit 1; }

echo "== boot $DEVICE =="
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1 || true

echo "== install =="
xcrun simctl install "$DEVICE" "$APP"

echo "== launch =="
# Straight after the performance tests the simulator can still be tearing the
# test app down, and a single check 5 s after launch failed the ship twice
# (2026-10-22, 2026-10-23) for an app that started fine. So: stop any running
# copy, retry the launch, and pass once the app has stayed up for three checks
# in a row (6 s alive — a crash on launch still fails).
xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
PID=""
for attempt in 1 2 3; do
  PID=$(xcrun simctl launch "$DEVICE" "$BUNDLE_ID" 2>/dev/null | awk '{print $2}') || true
  [ -n "$PID" ] && break
  sleep 3
done

alive=0
for i in $(seq 1 10); do
  sleep 2
  # Captured first: grep -q under pipefail reports launchctl's SIGPIPE as a miss.
  RUNNING=$(xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null || true)
  if printf '%s' "$RUNNING" | grep -q "$BUNDLE_ID"; then
    alive=$((alive + 1)); [ "$alive" -ge 3 ] && break
  else
    alive=0
  fi
done

if [ "$alive" -ge 3 ]; then
  echo "SMOKE OK — $BUNDLE_ID running (pid $PID)"
else
  echo "SMOKE FAILED — $BUNDLE_ID is not running after launch"
  ls -t ~/Library/Logs/DiagnosticReports/Milepost-*.ips 2>/dev/null | head -1 | xargs -I{} sh -c 'echo "--- {}"; head -c 4000 {}'
  exit 1
fi
