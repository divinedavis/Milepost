#!/usr/bin/env bash
# Build -> install -> cold-launch in a simulator. Proves the app actually
# starts, which a green `xcodebuild build` does not.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${MILEPOST_SIM:-iPhone 17 Pro}"
BUNDLE_ID="com.divinedavis.milepost"
DERIVED="build/smoke"

echo "== build =="
xcodebuild -project Milepost.xcodeproj -scheme Milepost \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build > /dev/null

APP="$DERIVED/Build/Products/Debug-iphonesimulator/Milepost.app"
[ -d "$APP" ] || { echo "no app at $APP"; exit 1; }

# XcodeGen quietly drops resources that are declared in the wrong place.
[ -f "$APP/Assets.car" ] || { echo "Assets.car missing from bundle — icon/accent not shipped"; exit 1; }
for key in NSLocationWhenInUseUsageDescription UIBackgroundModes; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist" >/dev/null 2>&1 || { echo "Info.plist missing $key"; exit 1; }
done

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
