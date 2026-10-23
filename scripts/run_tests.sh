#!/usr/bin/env bash
# Unit + UI tests.
#
#   ./scripts/run_tests.sh              # everything
#   ./scripts/run_tests.sh unit         # iPhone unit + watch journeys
#   ./scripts/run_tests.sh watch        # watch journeys only
#   ./scripts/run_tests.sh ui           # UI only (static + moving)
#   ./scripts/run_tests.sh ui MilepostUITests/testEveryTabOpens
set -euo pipefail
cd "$(dirname "$0")/.."

WHAT="${1:-all}"
FILTER="${2:-}"
WATCH_DEVICE="${MILEPOST_WATCH_SIM:-Apple Watch Series 11 (46mm)}"
# MILEPOST_SIM may be a name or a UDID. Three runtimes share the name
# "iPhone 17 Pro", so a UDID is the only way to pin one for screenshots.
DEVICE="${MILEPOST_SIM:-iPhone 17 Pro}"
if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  DEST="platform=iOS Simulator,id=$DEVICE"
else
  DEST="platform=iOS Simulator,name=$DEVICE"
fi

boot() {
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
}

# A fixed fix in Brooklyn: the static suite expects "No Movement Detected".
still() {
  xcrun simctl location "$DEVICE" clear >/dev/null 2>&1 || true
  xcrun simctl location "$DEVICE" set 40.6835,-73.9680 >/dev/null 2>&1 || true
}

# A loop through Prospect Park at an easy jog; long enough to outlast the test.
moving() {
  xcrun simctl location "$DEVICE" start --speed=3.5 --interval=1 \
    40.6602,-73.9690 40.6560,-73.9620 40.6510,-73.9660 40.6530,-73.9750 \
    40.6600,-73.9740 40.6650,-73.9700 40.6602,-73.9690 >/dev/null 2>&1 || true
}

# The same loop at about 18 mph, for the ride suite.
riding() {
  xcrun simctl location "$DEVICE" start --speed=8 --interval=1 \
    40.6602,-73.9690 40.6560,-73.9620 40.6510,-73.9660 40.6530,-73.9750 \
    40.6600,-73.9740 40.6650,-73.9700 40.6602,-73.9690 >/dev/null 2>&1 || true
}

run() {
  local target="$1"
  local args=(-project Milepost.xcodeproj -scheme Milepost -destination "$DEST" CODE_SIGNING_ALLOWED=NO)
  if [ -n "$FILTER" ]; then
    args+=(-only-testing:"$FILTER")
  else
    args+=(-only-testing:"$target")
  fi
  local log
  log=$(mktemp)
  set +e
  xcodebuild test "${args[@]}" > "$log" 2>&1
  local status=$?
  set -e
  grep -E "Test Case|error:|failed|\*\* TEST" "$log" | tail -80
  # A filter that matches nothing — or a stale xcodeproj whose test bundle
  # was built without the new file — runs zero tests and still prints
  # "** TEST SUCCEEDED **". That is a broken gate, not a pass.
  if ! grep -qE "Executed [1-9][0-9]* test" "$log"; then
    echo "NO TESTS RAN for ${FILTER:-$target}"
    echo "  a filter that matches nothing, or a stale project: run scripts/generate.sh"
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  return $status
}

# watchOS has no XCUITest, so the watch journeys drive the controller the
# buttons call — which is where the freezes and the lost runs have lived.
watch_tests() {
  echo "== watch (journeys) =="
  local log
  log=$(mktemp)
  set +e
  xcodebuild test -project Milepost.xcodeproj -scheme MilepostWatch \
    -destination "platform=watchOS Simulator,name=$WATCH_DEVICE" \
    CODE_SIGNING_ALLOWED=NO > "$log" 2>&1
  local status=$?
  set -e
  grep -E "Test Case|error:|\*\* TEST" "$log" | grep -v "healthkit Code=4" | tail -40
  if ! grep -qE "Executed [1-9][0-9]* test" "$log"; then
    echo "NO TESTS RAN for MilepostWatchTests"
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  return $status
}

ui_all() {
  boot
  echo "== ui (static) =="
  still
  run MilepostUITests/MilepostUITests
  echo "== ui (splash) =="
  run MilepostUITests/MilepostSplashUITests
  echo "== ui (health) =="
  run MilepostUITests/MilepostHealthUITests
  echo "== ui (sport) =="
  run MilepostUITests/MilepostSportUITests
  echo "== ui (heatmap) =="
  run MilepostUITests/MilepostHeatmapUITests
  echo "== ui (friends) =="
  run MilepostUITests/MilepostFriendsUITests
  echo "== ui (accessibility audit) =="
  run MilepostUITests/AccessibilityAuditTests
  echo "== ui (profile, recovery, holidays, record options, tab bar) =="
  run MilepostUITests/MilepostProfileUITests
  run MilepostUITests/MilepostRecoveryUITests
  run MilepostUITests/MilepostHolidayUITests
  run MilepostUITests/MilepostRecordOptionsUITests
  run MilepostUITests/MilepostTabBarUITests
  echo "== ui (live activity) =="
  run MilepostUITests/MilepostLiveActivityUITests
  echo "== ui (moving) =="
  moving
  run MilepostUITests/MilepostRouteUITests
  echo "== ui (moving, ride) =="
  riding
  run MilepostUITests/MilepostRideUITests
  still
}

case "$WHAT" in
  unit) echo "== unit =="; run MilepostTests; watch_tests ;;
  watch) watch_tests ;;
  ui)
    if [ -n "$FILTER" ]; then
      boot
      case "$FILTER" in *Ride*) riding ;; *Route*) moving ;; *) still ;; esac
      run "$FILTER"; still
    else
      ui_all
    fi ;;
  all)  echo "== unit =="; run MilepostTests; watch_tests; ui_all ;;
  *)    echo "usage: run_tests.sh [unit|watch|ui|all] [Class[/test]]"; exit 2 ;;
esac
