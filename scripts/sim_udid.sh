#!/usr/bin/env bash
# Prints the simulator UDID to test on: $MILEPOST_SIM if set, otherwise the
# "iPhone 17 Pro" on the newest installed iOS runtime. Two simulators share
# that name (iOS 26.4 and 26.5) and a bare name failed a ship with "Unable to
# find a device" (2026-10-23), so scripts always pass a UDID.
set -euo pipefail
if [[ -n "${MILEPOST_SIM:-}" ]]; then echo "$MILEPOST_SIM"; exit 0; fi
NAME="${MILEPOST_SIM_NAME:-iPhone 17 Pro}"
xcrun simctl list devices available -j | python3 -c '
import json, sys, re
name = sys.argv[1]
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m: continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d["name"] == name and (best is None or version > best[0]):
            best = (version, d["udid"])
if not best: sys.exit(f"no simulator named {name}")
print(best[1])' "$NAME"
