#!/usr/bin/env python3
"""Upload build/asc-screenshots/*.png to the editable version's en-US iPhone slot.

Per file: reserve (POST appScreenshots) → PUT each chunk → commit (PATCH with
the MD5). --replace clears the slot first; without it existing files stay.
The 6.7" slot (APP_IPHONE_67, 1290x2796) is the largest one the API takes and
Apple scales it to every other iPhone size.

    python3 scripts/asc_upload_screenshots.py --replace
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys

import requests

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc import ASC, load_config  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCREENSHOTS_DIR = ROOT / "build" / "asc-screenshots"
DISPLAY_TYPE = "APP_IPHONE_67"


def screenshot_set(asc: ASC, loc_id: str, display: str) -> str:
    for s in asc.get(f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]:
        if s["attributes"]["screenshotDisplayType"] == display:
            return s["id"]
    return asc.post("/appScreenshotSets", {"data": {
        "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})["data"]["id"]


def upload(asc: ASC, set_id: str, png: pathlib.Path) -> None:
    data = png.read_bytes()
    res = asc.post("/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": png.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in res["attributes"]["uploadOperations"]:
        chunk = data[int(op["offset"]):int(op["offset"]) + int(op["length"])]
        r = requests.request(op["method"], op["url"],
                             headers={h["name"]: h["value"] for h in op["requestHeaders"]},
                             data=chunk, timeout=120)
        if r.status_code >= 400:
            raise SystemExit(f"chunk upload failed: {r.status_code} {r.text[:300]}")
    asc.patch(f"/appScreenshots/{res['id']}", {"data": {
        "type": "appScreenshots", "id": res["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--display", default=DISPLAY_TYPE)
    args = ap.parse_args()

    cfg = load_config()
    asc = ASC(cfg)
    version = asc.editable_version(cfg["ASC_APP_ID"])
    loc = next(l for l in asc.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
               if l["attributes"]["locale"] == "en-US")
    set_id = screenshot_set(asc, loc["id"], args.display)
    if args.replace:
        for s in asc.get(f"/appScreenshotSets/{set_id}/appScreenshots")["data"]:
            asc.delete(f"/appScreenshots/{s['id']}")
        print("cleared existing screenshots")
    pngs = sorted(p for p in SCREENSHOTS_DIR.glob("*.png") if not p.name.startswith("_"))
    if not pngs:
        raise SystemExit(f"no PNGs in {SCREENSHOTS_DIR} — run asc_make_screenshots.py first")
    for png in pngs:
        upload(asc, set_id, png)
        print(f"  ✓ {png.name}")
    print(f"{len(pngs)} screenshot(s) in {args.display} en-US")
    return 0


if __name__ == "__main__":
    sys.exit(main())
