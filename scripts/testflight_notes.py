#!/usr/bin/env python3
"""TestFlight "What to Test" for a build, from the commits since the last ship.

ship.sh starts this in the background after an upload (2026-10-23). It waits
for Apple to finish processing the build (up to 30 minutes), then writes the
subjects of the commits between the previous `build-N` tag and this one into
the build's en-US "What to Test", so the owner sees on the phone what changed.

    scripts/testflight_notes.py --build 39 [--dry-run]
"""
from __future__ import annotations

import argparse
import subprocess
import time

import requests

from attach_build import API_BASE, load_config, token

APP_ID = "6808740421"
LIMIT = 4000  # Apple's cap on whatsNew


def notes_for(build: int) -> str:
    tags = subprocess.run(["git", "tag", "--list", "build-*"], capture_output=True, text=True).stdout.split()
    earlier = sorted((int(t.split("-")[1]) for t in tags if t.split("-")[1].isdigit() and int(t.split("-")[1]) < build))
    since = f"build-{earlier[-1]}" if earlier else "HEAD~10"
    log = subprocess.run(["git", "log", "--format=- %s", f"{since}..build-{build}"],
                         capture_output=True, text=True).stdout
    # Bookkeeping commits say nothing a tester needs.
    lines = [l for l in log.splitlines() if not l.startswith("- Ship ") and "Regenerate Info.plist" not in l]
    text = "What changed in this build:\n" + "\n".join(lines or ["- Maintenance build"])
    return text[:LIMIT]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", type=int, required=True)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    text = notes_for(args.build)
    print(text)
    if args.dry_run:
        return

    cfg = load_config()
    deadline = time.time() + 30 * 60
    build_id = None
    while time.time() < deadline:
        h = {"Authorization": f"Bearer {token(cfg)}"}
        r = requests.get(f"{API_BASE}/builds", headers=h, timeout=30,
                         params={"filter[app]": APP_ID, "filter[version]": str(args.build), "limit": 1})
        data = r.json().get("data", [])
        if data and data[0]["attributes"].get("processingState") == "VALID":
            build_id = data[0]["id"]
            break
        time.sleep(60)
    if not build_id:
        raise SystemExit(f"build {args.build} not processed after 30 minutes; notes not written")

    h = {"Authorization": f"Bearer {token(cfg)}", "Content-Type": "application/json"}
    locs = requests.get(f"{API_BASE}/builds/{build_id}/betaBuildLocalizations", headers=h, timeout=30).json().get("data", [])
    en = next((l for l in locs if l["attributes"].get("locale") == "en-US"), None)
    if en:
        r = requests.patch(f"{API_BASE}/betaBuildLocalizations/{en['id']}", headers=h, timeout=30,
                           json={"data": {"type": "betaBuildLocalizations", "id": en["id"],
                                          "attributes": {"whatsNew": text}}})
    else:
        r = requests.post(f"{API_BASE}/betaBuildLocalizations", headers=h, timeout=30,
                          json={"data": {"type": "betaBuildLocalizations",
                                         "attributes": {"locale": "en-US", "whatsNew": text},
                                         "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    print(f"build {args.build}: What to Test {'updated' if r.ok else 'FAILED ' + r.text[:300]}")


if __name__ == "__main__":
    main()
