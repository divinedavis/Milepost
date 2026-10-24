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
# The Mac-wide build lock (one build at a time, every app). Re-entrant: under
# ship.sh it is already ours.
source scripts/build_lock.sh
build_lock_take "Milepost tests"

WHAT="${1:-all}"
FILTER="${2:-}"
WATCH_DEVICE="${MILEPOST_WATCH_SIM:-Apple Watch Series 11 (46mm)}"
# MILEPOST_SIM may be a name or a UDID. Three runtimes share the name
# "iPhone 17 Pro", so a UDID is the only way to pin one for screenshots.
DEVICE="$(./scripts/sim_udid.sh)"
if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  DEST="platform=iOS Simulator,id=$DEVICE"
else
  DEST="platform=iOS Simulator,name=$DEVICE"
fi

# One build for every pass (2026-10-23): build-for-testing once into a fixed
# DerivedData, then each class runs test-without-building against it. Before,
# every pass was its own `xcodebuild test`, re-checking and re-linking
# everything ~15 times a ship. Coverage is off (nothing reads it) and so is
# the index store (only Xcode's editor uses it).
DERIVED="${MILEPOST_TEST_DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/Milepost-tests}"
RESULTS="${MILEPOST_RESULTS:-build.nosync/test-results}"
FLAKY_LOG="$HOME/Library/Logs/milepost-flaky-tests.log"
# Package versions come only from the committed Package.resolved; asset
# catalogs compile for speed, not size, in these Debug builds.
BUILD_FLAGS=(CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO ENABLE_DEBUG_DYLIB=NO
             ASSETCATALOG_COMPILER_OPTIMIZATION=time)
PKG_FLAGS=(-onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation -skipMacroValidation)
DURATIONS="$HOME/Library/Logs/milepost-test-durations.csv"
BUILT=0

build_once() {
  [ "$BUILT" = 1 ] && return 0
  echo "== build for testing =="
  local log
  log=$(mktemp)
  if ! xcodebuild build-for-testing -project Milepost.xcodeproj -scheme Milepost -destination "$DEST" \
      -derivedDataPath "$DERIVED" -enableCodeCoverage NO "${PKG_FLAGS[@]}" "${BUILD_FLAGS[@]}" > "$log" 2>&1; then
    grep -E "error:" "$log" | head -20
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
  BUILT=1
}

boot() {
  # No Mac keyboard attached to the simulator: typed text goes through the
  # on-screen keyboard the tests expect.
  defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false 2>/dev/null || true
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
  # Location granted up front: no prompt to tap through, no 9 s wait for one.
  xcrun simctl privacy "$DEVICE" grant location-always com.divinedavis.milepost >/dev/null 2>&1 || true
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
  build_once
  local only="${FILTER:-$target}"
  local bundle="$RESULTS/$(echo "$only" | tr '/' '_').xcresult"
  mkdir -p "$RESULTS"
  rm -rf "$bundle"
  # A failing test is run once more on its own; a pass on the retry is a
  # flake, logged, not a ship failure. A real regression fails both times.
  local args=(-project Milepost.xcodeproj -scheme Milepost -destination "$DEST" -derivedDataPath "$DERIVED"
              -enableCodeCoverage NO -only-testing:"$only" -resultBundlePath "$bundle"
              -retry-tests-on-failure -test-iterations 2 "${BUILD_FLAGS[@]}")
  local log
  log=$(mktemp)
  set +e
  xcodebuild test-without-building "${args[@]}" > "$log" 2>&1
  local status=$?
  set -e
  grep -E "Test Case|error:|failed|\*\* TEST" "$log" | tail -80
  # Every test's time, for the slowest-tests report.
  sed -nE "s/.*Test Case '-\[([A-Za-z]+)\.([A-Za-z]+) ([A-Za-z0-9_]+)\]' passed \(([0-9.]+) seconds\).*/$(date +%F),\2,\3,\4/p" "$log" >> "$DURATIONS"
  if [ "$status" = 0 ] && grep -qE "Test Case .* failed" "$log"; then
    grep -E "Test Case .* failed" "$log" | sed "s/^/$(date '+%F %T') FLAKY (passed on retry): /" >> "$FLAKY_LOG"
    echo "flaky: a test failed once and passed on retry (logged to $FLAKY_LOG)"
  fi
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
  # Same DerivedData as the iOS build, which already compiled the watch app.
  xcodebuild test -project Milepost.xcodeproj -scheme MilepostWatch \
    -destination "platform=watchOS Simulator,name=$WATCH_DEVICE" \
    -derivedDataPath "$DERIVED" "${PKG_FLAGS[@]}" \
    -enableCodeCoverage NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO > "$log" 2>&1
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
