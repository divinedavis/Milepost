#!/usr/bin/env bash
# Waits until no other build is running on this Mac: another app's ship or
# daily ship, a test run, or any xcodebuild. Owner rule (2026-10-23): never two
# builds at once — overlapping ships failed Milepost's tests and starved the
# 16 GB Mac. Gives up after MAX_WAIT seconds (default three hours).
set -euo pipefail
MAX_WAIT="${MAX_WAIT:-10800}"

# Our own process and its parents are not "another build".
mine=" $$ "
p=$PPID
while [[ "$p" -gt 1 ]]; do
    mine+="$p "
    p=$(ps -o ppid= -p "$p" | tr -d ' ')
    [[ -z "$p" ]] && break
done

busy() {
    ps -axo pid=,command= | while read -r pid cmd; do
        [[ "$mine" == *" $pid "* ]] && continue
        case "$cmd" in
            *xcodebuild\ *|*/xcodebuild|*daily_ship.sh*|*scripts/ship.sh*|*run_tests.sh*) echo "$pid $cmd" ;;
        esac
    done | grep -v -E "wait_for_quiet_mac|grep" | head -1
}

waited=0
while other=$(busy) && [[ -n "$other" ]]; do
    if (( waited == 0 )); then echo "==> waiting for another build to finish: ${other:0:120}"; fi
    if (( waited >= MAX_WAIT )); then echo "error: still busy after ${MAX_WAIT}s" >&2; exit 1; fi
    sleep 30; waited=$((waited + 30))
done
(( waited > 0 )) && echo "==> Mac is quiet after ${waited}s" || true
