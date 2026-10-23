#!/usr/bin/env bash
# Install (or refresh) Milepost's daily holiday App Store job:
# mp_holidays_auto.py --apply every day at 06:20 on this Mac (Marracat's runs
# at 06:10; launchd runs a missed one at the next wake). The scripts,
# holidays.json and logo files are copied out of the repo, in the repo's
# layout, so a checkout mid-edit never runs; re-run this after changing any
# of them. Log: ~/Library/Logs/milepost-holidays.log
set -euo pipefail
cd "$(dirname "$0")/../.."
DEST="$HOME/Library/Application Support/milepost-holidays"
PLIST="$HOME/Library/LaunchAgents/com.divinedavis.milepost-holidays.plist"
PY="${PY:-$HOME/.venvs/dhcr-map/bin/python}"
ASC="${ASC:-$HOME/projects/dhcr-map/ios/scripts}"
mkdir -p "$DEST/scripts/asc_growth" "$DEST/Milepost/Resources" "$DEST/marketing/logo" "$DEST/asc"
cp scripts/asc_growth/mp_holidays_auto.py scripts/asc_growth/asc_app_events.py "$DEST/scripts/asc_growth/"
cp scripts/holiday_event_art.py "$DEST/scripts/"
cp Milepost/Resources/holidays.json "$DEST/Milepost/Resources/"
cp marketing/logo/runner-wordmark-dark-transparent.svg "$DEST/marketing/logo/"
cp "$ASC/asc_creative_assets.py" "$DEST/asc/"
cp "$ASC/asc-config.env" "$DEST/asc/" && chmod 600 "$DEST/asc/asc-config.env"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.divinedavis.milepost-holidays</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>$DEST/scripts/asc_growth/mp_holidays_auto.py</string>
    <string>--apply</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONPATH</key><string>$DEST/scripts/asc_growth:$DEST/asc</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>WorkingDirectory</key><string>$DEST</string>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>6</integer><key>Minute</key><integer>20</integer></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/milepost-holidays.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/milepost-holidays.log</string>
</dict>
</plist>
PL
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed: $PLIST (daily 06:20); log ~/Library/Logs/milepost-holidays.log"
