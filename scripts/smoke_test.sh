#!/usr/bin/env bash
# Build -> install -> cold-launch in a simulator. Proves the app actually
# starts, which a green `xcodebuild build` does not.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${MILEPOST_SIM:-iPhone 17 Pro}"
if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  DEST="platform=iOS Simulator,id=$DEVICE"
else
  DEST="platform=iOS Simulator,name=$DEVICE"
fi
BUNDLE_ID="com.divinedavis.milepost"
DERIVED="build/smoke"

echo "== build =="
xcodebuild -project Milepost.xcodeproj -scheme Milepost \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build > /dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Milepost.app"
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
/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$WATCH_APP/Info.plist" 2>/dev/null | grep -q workout-processing || {
  echo "watch app missing the workout-processing background mode — a run would stop with the wrist down"; exit 1; }

echo "== boot $DEVICE =="
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b > /dev/null 2>&1 || true

echo "== install =="
xcrun simctl install "$DEVICE" "$APP"

echo "== launch =="
PID=$(xcrun simctl launch "$DEVICE" "$BUNDLE_ID" | awk '{print $2}')
sleep 5

RUNNING=$(xcrun simctl spawn "$DEVICE" launchctl list 2>/dev/null || true)
if printf '%s' "$RUNNING" | grep -q "$BUNDLE_ID"; then
  echo "SMOKE OK — $BUNDLE_ID running (pid $PID)"
else
  echo "SMOKE FAILED — $BUNDLE_ID is not running after launch"
  ls -t ~/Library/Logs/DiagnosticReports/Milepost-*.ips 2>/dev/null | head -1 | xargs -I{} sh -c 'echo "--- {}"; head -c 4000 {}'
  exit 1
fi
