#!/usr/bin/env bash
# Runs one command under the Mac-wide build lock, for ad-hoc builds and test
# runs outside ship.sh/run_tests.sh:  scripts/with_build_lock.sh "<label>" cmd ...
set -euo pipefail
source "$(dirname "$0")/build_lock.sh"
label="$1"; shift
build_lock_take "Milepost $label"
"$@"
