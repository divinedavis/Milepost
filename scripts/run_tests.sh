#!/usr/bin/env bash
# Unit + UI tests.
#
#   ./scripts/run_tests.sh              # everything
#   ./scripts/run_tests.sh unit         # unit only
#   ./scripts/run_tests.sh ui           # UI only (static + moving)
#   ./scripts/run_tests.sh ui MilepostUITests/testEveryTabOpens
set -euo pipefail
cd "$(dirname "$0")/.."

WHAT="${1:-all}"
FILTER="${2:-}"
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

run() {
  local target="$1"
  local args=(-project Milepost.xcodeproj -scheme Milepost -destination "$DEST" CODE_SIGNING_ALLOWED=NO)
  if [ -n "$FILTER" ]; then
    args+=(-only-testing:"$FILTER")
  else
    args+=(-only-testing:"$target")
  fi
  set +e
  xcodebuild test "${args[@]}" 2>&1 | grep -E "Test Case|error:|failed|\*\* TEST" | tail -80
  local status=${PIPESTATUS[0]}
  set -e
  return $status
}

ui_all() {
  boot
  echo "== ui (static) =="
  still
  run MilepostUITests/MilepostUITests
  echo "== ui (live activity) =="
  run MilepostUITests/MilepostLiveActivityUITests
  echo "== ui (moving) =="
  moving
  run MilepostUITests/MilepostRouteUITests
  still
}

case "$WHAT" in
  unit) echo "== unit =="; run MilepostTests ;;
  ui)
    if [ -n "$FILTER" ]; then
      boot
      case "$FILTER" in *Route*) moving ;; *) still ;; esac
      run "$FILTER"; still
    else
      ui_all
    fi ;;
  all)  echo "== unit =="; run MilepostTests; ui_all ;;
  *)    echo "usage: run_tests.sh [unit|ui|all] [Class[/test]]"; exit 2 ;;
esac
