#!/usr/bin/env python3
"""Submit the editable version to App Review through reviewSubmissions.

Pre-flight checks everything the public API can see (listing fields, build,
review contact, screenshots, categories, privacy URL, price, availability) and
submits only when all of it is green. App Privacy labels are invisible to the
API — a 409 with APP_PRIVACY... in meta.associatedErrors means they are missing
(scripts/asc_push_privacy_iris.py).

    python3 scripts/asc_submit_for_review.py --check    # pre-flight only
    python3 scripts/asc_submit_for_review.py            # submit
    python3 scripts/asc_submit_for_review.py --force    # submit despite gaps
"""
from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc import ASC, load_config  # noqa: E402


def preflight(asc: ASC, app_id: str, ver_id: str) -> list[str]:
    issues: list[str] = []
    locs = asc.get(f"/appStoreVersions/{ver_id}/appStoreVersionLocalizations")["data"]
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    if not en:
        issues.append("missing en-US localization")
    else:
        for f in ("description", "keywords", "supportUrl"):
            if not en["attributes"].get(f):
                issues.append(f"localization.{f} empty")
        sets = asc.get(f"/appStoreVersionLocalizations/{en['id']}/appScreenshotSets")["data"]
        iphone = next((s for s in sets if s["attributes"]["screenshotDisplayType"].startswith("APP_IPHONE")), None)
        if not iphone:
            issues.append("no iPhone screenshot set")
        else:
            shots = asc.get(f"/appScreenshotSets/{iphone['id']}/appScreenshots")["data"]
            ready = [s for s in shots if (s["attributes"].get("assetDeliveryState") or {}).get("state") == "COMPLETE"]
            if len(ready) < 3:
                issues.append(f"only {len(ready)} screenshot(s) COMPLETE (need >= 3)")
    if not asc.get(f"/appStoreVersions/{ver_id}/build").get("data"):
        issues.append("no build attached")
    rd = asc.get(f"/appStoreVersions/{ver_id}/appStoreReviewDetail").get("data")
    if not rd:
        issues.append("no appStoreReviewDetail")
    else:
        for f in ("contactFirstName", "contactPhone", "contactEmail"):
            if not rd["attributes"].get(f):
                issues.append(f"reviewDetail.{f} empty")
    info = asc.get(f"/apps/{app_id}/appInfos")["data"][0]
    full = asc.get(f"/appInfos/{info['id']}", include="primaryCategory,appInfoLocalizations")
    if not full["data"]["relationships"].get("primaryCategory", {}).get("data"):
        issues.append("primaryCategory unset")
    for inc in full.get("included", []):
        if inc["type"] == "appInfoLocalizations" and inc["attributes"].get("locale") == "en-US" \
                and not inc["attributes"].get("privacyPolicyUrl"):
            issues.append("privacyPolicyUrl empty")
    prices = asc.s.get(asc._url(f"/appPriceSchedules/{app_id}/manualPrices"), timeout=30)
    if not (prices.status_code == 200 and prices.json().get("data")):
        issues.append("no price set (APP_PRICING_REQUIRED at submit)")
    if asc.s.get(asc._url(f"/apps/{app_id}/appAvailabilityV2"), timeout=30).status_code != 200:
        issues.append("no availability record (approved app would never list)")
    return issues


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    cfg = load_config()
    asc = ASC(cfg)
    app_id = cfg["ASC_APP_ID"]
    version = asc.editable_version(app_id)
    ver_id = version["id"]
    print(f"version {version['attributes']['versionString']} ({version['attributes']['appStoreState']})")

    issues = preflight(asc, app_id, ver_id)
    if issues:
        print("pre-flight gaps:")
        for x in issues:
            print(f"  - {x}")
        if not args.force:
            return 1
        print("--force: submitting anyway")
    else:
        print("pre-flight clean (App Privacy labels are not visible to the API)")
    if args.check:
        return 0 if not issues else 1

    subs = asc.get("/reviewSubmissions", **{"filter[app]": app_id, "filter[platform]": "IOS", "limit": 5})["data"]
    draft = next((s for s in subs if s["attributes"].get("state") in
                  ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES", "COMPLETING")), None)
    if draft:
        sub_id = draft["id"]
        print(f"reusing reviewSubmission {sub_id} ({draft['attributes']['state']})")
    else:
        sub_id = asc.post("/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]["id"]
        print(f"created reviewSubmission {sub_id}")

    items = asc.get(f"/reviewSubmissions/{sub_id}/items").get("data", [])
    if not any(it.get("relationships", {}).get("appStoreVersion", {}).get("data", {}).get("id") == ver_id
               for it in items):
        asc.post("/reviewSubmissionItems", {"data": {
            "type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}}}})
        print("added the version as a submission item")

    try:
        asc.patch(f"/reviewSubmissions/{sub_id}", {"data": {
            "type": "reviewSubmissions", "id": sub_id, "attributes": {"submitted": True}}})
    except RuntimeError as e:
        print(f"SUBMISSION REFUSED: {e}")
        return 2
    print("submitted to App Review")
    return 0


if __name__ == "__main__":
    sys.exit(main())
