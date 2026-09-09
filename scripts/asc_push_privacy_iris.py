#!/usr/bin/env python3
"""Publish Milepost's App Privacy labels: "Data Not Collected".

The public App Store Connect API has no App Privacy resource, so this drives
the private iris API the dashboard itself uses, with the cookie jar fastlane's
Spaceship writes after `fastlane spaceauth -u <apple id>` (2FA, so a person
runs that; the cookie lasts a few days).

Milepost stores runs in an on-device database and makes no network requests,
so the whole questionnaire is one record with dataProtection
DATA_NOT_COLLECTED and no category/purpose, followed by the publish PATCH.
The publish state can only be UPDATEd, never read, so a 200 there is the proof.

    python3 scripts/asc_push_privacy_iris.py [--probe-only]
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

import requests

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc import load_config  # noqa: E402

IRIS = "https://appstoreconnect.apple.com/iris/v1"
COOKIE_FILE = pathlib.Path.home() / ".fastlane" / "spaceship" / "divinejdavis@gmail.com" / "cookie"


def cookies() -> list[dict]:
    """Spaceship's jar is Ruby YAML (!ruby/object:HTTP::Cookie); line-scan it."""
    if not COOKIE_FILE.exists():
        raise SystemExit(f"no cookie at {COOKIE_FILE} — run: fastlane spaceauth -u divinejdavis@gmail.com")
    out: list[dict] = []
    cur: dict | None = None
    for line in COOKIE_FILE.read_text().splitlines():
        if line.lstrip().startswith("- !ruby/object:"):
            if cur and cur.get("name") and cur.get("value"):
                out.append(cur)
            cur = {}
            continue
        if cur is None or ":" not in line:
            continue
        k, _, v = line.strip().partition(":")
        if k.strip() in ("name", "value", "domain") and v.strip():
            cur[k.strip()] = v.strip().strip('"').strip("'")
    if cur and cur.get("name") and cur.get("value"):
        out.append(cur)
    if not out:
        raise SystemExit("parsed 0 cookies from the Spaceship jar")
    return out


def session() -> requests.Session:
    s = requests.Session()
    for c in cookies():
        s.cookies.set(c["name"], c["value"], domain=c.get("domain", "appstoreconnect.apple.com"))
    s.headers.update({
        "Accept": "application/vnd.api+json", "Content-Type": "application/vnd.api+json",
        "X-Requested-With": "XMLHttpRequest",
        "User-Agent": ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                       "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"),
        "Origin": "https://appstoreconnect.apple.com", "Referer": "https://appstoreconnect.apple.com/",
    })
    return s


def show(label: str, r: requests.Response) -> None:
    print(f"── {label}  HTTP {r.status_code}")
    try:
        print(json.dumps(r.json(), indent=1)[:1200])
    except Exception:
        print(r.text[:600])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe-only", action="store_true")
    args = ap.parse_args()
    app_id = load_config()["ASC_APP_ID"]
    s = session()

    r = s.get(f"{IRIS}/appDataUsages", params={"filter[app]": app_id, "limit": 50}, timeout=30)
    if r.status_code == 401:
        raise SystemExit("iris says 401: the Spaceship cookie has expired — "
                         "run `fastlane spaceauth -u divinejdavis@gmail.com` and retry")
    show("existing appDataUsages", r)
    existing = r.json().get("data", []) if r.ok else []
    if args.probe_only:
        show("dataProtections", s.get(f"{IRIS}/appDataUsageDataProtections", timeout=30))
        # The "regulated medical device" declaration (required for any app in
        # Health & Fitness) has no public API either. Dump the appInfo the
        # dashboard sees so the field name can be found and PATCHed.
        r = s.get(f"{IRIS}/apps/{app_id}/appInfos", timeout=30)
        show("appInfos (look for medical/regulated fields)", r)
        for key in ("regulatedMedicalDeviceDeclarations", "medicalDeviceDeclarations", "appMedicalDeviceDeclarations"):
            rr = s.get(f"{IRIS}/{key}", params={"filter[app]": app_id}, timeout=30)
            print(f"   {key}: HTTP {rr.status_code}")
        return 0

    if any((e.get("relationships", {}).get("dataProtection", {}).get("data") or {}).get("id")
           == "DATA_NOT_COLLECTED" for e in existing):
        print("DATA_NOT_COLLECTED record already present")
    else:
        for e in existing:   # a stale category record would contradict "not collected"
            s.delete(f"{IRIS}/appDataUsages/{e['id']}", timeout=30)
        body = {"data": {"type": "appDataUsages", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "dataProtection": {"data": {"type": "appDataUsageDataProtections", "id": "DATA_NOT_COLLECTED"}}}}}
        r = s.post(f"{IRIS}/appDataUsages", data=json.dumps(body), timeout=30)
        if r.status_code >= 400:
            show("POST DATA_NOT_COLLECTED failed", r)
            return 1
        print("posted DATA_NOT_COLLECTED")

    r = s.patch(f"{IRIS}/appDataUsagesPublishState/{app_id}", data=json.dumps({"data": {
        "type": "appDataUsagesPublishState", "id": app_id, "attributes": {"published": True}}}), timeout=30)
    if r.status_code >= 400:
        show("publish failed", r)
        return 1
    print("App Privacy published: Data Not Collected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
