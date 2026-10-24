#!/usr/bin/env bash
# Build -> install -> cold-launch the watch app in a watchOS simulator.
#
# The iPhone smoke test proves the phone app starts; it says nothing about the
# watch app riding inside it, which has its own @main, its own HealthKit and
# CoreLocation setup, and its own ways to die on launch.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/build_lock.sh
build_lock_take "Milepost watch smoke test"

DEVICE="${MILEPOST_WATCH_SIM:-Apple Watch Series 11 (46mm)}"
BUNDLE_ID="com.divinedavis.milepost.watchkitapp"
DERIVED="build/smoke-watch"

echo "== build =="
xcodebuild -project Milepost.xcodeproj -scheme MilepostWatch \
  -destination "platform=watchOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build > /dev/null

APP="$DERIVED/Build/Products/Debug-watchsimulator/MilepostWatch.app"
[ -d "$APP" ] || { echo "no watch app at $APP"; exit 1; }

# WKBackgroundModes, not UIBackgroundModes, and `location` is not a value it
# accepts. Both only fail at App Store upload (90362), so check here.
/usr/libexec/PlistBuddy -c "Print :WKBackgroundModes" "$APP/Info.plist" 2>/dev/null | grep -q workout-processing \
  || { echo "missing workout-processing in WKBackgroundModes"; exit 1; }
if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$APP/Info.plist" >/dev/null 2>&1; then
  echo "watch app has UIBackgroundModes — watchOS wants WKBackgroundModes"; exit 1
fi
if /usr/libexec/PlistBuddy -c "Print :WKBackgroundModes" "$APP/Info.plist" 2>/dev/null | grep -qx "    location"; then
  echo "'location' is not a valid WKBackgroundModes value — the App Store rejects it"; exit 1
fi

echo "== boot $DEVICE =="
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1 || true

echo "== install =="
xcrun simctl install "$DEVICE" "$APP"

echo "== launch =="
xcrun simctl launch "$DEVICE" "$BUNDLE_ID" > /dev/null
sleep 4
PID=$(xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null | awk -v b="$BUNDLE_ID" '$3 ~ b {print $1}' | head -1)
if [ -z "$PID" ] || [ "$PID" = "-" ]; then
  echo "WATCH SMOKE FAILED — $BUNDLE_ID is not running after launch"
  exit 1
fi
echo "WATCH SMOKE OK — $BUNDLE_ID running (pid $PID)"
