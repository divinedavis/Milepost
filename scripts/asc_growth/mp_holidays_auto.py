"""Keep Milepost's holiday App Store presence running every year without
anyone remembering to (owner, 2026-10-22: "we should also have holiday
themes like we do with marracat ... do the app store changes too", then
"lets do it and keep the running days"). A port of Marracat's
mc_holidays_auto.py; the rules and Apple limits are the same.

Daily (launchd, scripts/asc_growth/install_holidays_auto.sh), from
Milepost/Resources/holidays.json:
  1. lays out every holiday whose event starts in the next HORIZON days;
  2. makes its art (card 3840x2160, details 2160x3840 and, for a themed
     day, the product page header 3840x1646; scripts/holiday_event_art.py)
     and uploads what the Asset Library doesn't have yet;
  3. creates each event as a draft (an event with the same reference name is
     left alone), but only once a live version routes its link: milepost://
     needs LINKS_FROM (the version that registered the scheme);
  4. sends the drafts and new headers to App Review in one submission,
     unless one is already open (Apple allows one), in which case it tries
     again tomorrow;
  5. swaps the live product page's header to the day's approved header
     while its theme is on, and back to the everyday header after.

Apple's rules (checked 2026-10-17 for Find A Crib's events): an event runs at
most 31 days, shows at most 14 days before it starts, 10 published and 15
approved at a time; its text can't change once approved. Placements can't be
edited (create and delete only), and only approved assets go on an approved
version.

    PYTHONPATH=scripts/asc_growth:~/projects/dhcr-map/ios/scripts \\
      ~/.venvs/dhcr-map/bin/python scripts/asc_growth/mp_holidays_auto.py            # plan only
    ... mp_holidays_auto.py --apply                                                  # do it
"""
import json
import subprocess
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests
from asc_creative_assets import API, call

APP = "6808740421"
ROOT = Path(__file__).resolve().parents[2]
DOC = json.loads((ROOT / "Milepost/Resources/holidays.json").read_text())
CACHE = Path.home() / "Library/Caches/milepost-holidays"
HORIZON = 24          # days ahead an event's start may be when it's created (14 shown + 10 for review)
SHOW = 14             # Apple's longest lead before an event starts
NY = timedelta(hours=-5)   # midnight in New York, near enough across DST
LINKS_FROM = (1, 6)        # the first version with the milepost:// scheme
EVERYDAY_HEADER = "milepost-2026-10/default/header-3840x1646.png"
LIMITS = {"name": 30, "shortDescription": 50, "longDescription": 120}
ART_PY = Path.home() / ".venvs/spendcap/bin/python"   # PIL + rsvg for the art


def log(*a):
    print(datetime.now().isoformat(timespec="seconds"), *a, flush=True)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def midnight(d):
    return datetime(d.year, d.month, d.day, tzinfo=timezone.utc) - NY


def holiday_day(h, year):
    """Same rule as the app's Holiday.day(in:): ISO weekdays, nth -1 = last."""
    r = h["date"]
    if "day" in r:
        d = date(year, r["month"], r["day"])
    else:
        first = date(year, r["month"], 1)
        if r["nth"] > 0:
            d = first + timedelta(days=(r["weekday"] - first.isoweekday()) % 7 + 7 * (r["nth"] - 1))
        else:
            nxt = date(year + (r["month"] == 12), r["month"] % 12 + 1, 1)
            last = nxt - timedelta(days=1)
            d = last - timedelta(days=(last.isoweekday() - r["weekday"]) % 7)
    return d + timedelta(days=r.get("offset", 0))


def planned(today):
    """Every event starting within HORIZON days (or running now)."""
    out = []
    for h in DOC["holidays"]:
        for y in (today.year, today.year + 1):
            day = holiday_day(h, y)
            e = h["event"]
            start, end = day + timedelta(days=e["from"]), day + timedelta(days=e["to"])
            theme = None
            if h.get("theme"):
                theme = (day + timedelta(days=h["theme"]["from"]), day + timedelta(days=h["theme"]["to"]))
            out.append(dict(id=h["id"], ref=f"Holiday {h['id']} {y}", year=y, start=start, end=end, theme=theme,
                            event=e, link=e["link"]))
    return [p for p in out if p["end"] >= today and (p["start"] - today).days <= HORIZON]


def live_version():
    v = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[appStoreState]=READY_FOR_SALE&filter[platform]=IOS&limit=1")["data"]
    return v[0] if v else None


def opens(version):
    have = tuple(int(x) for x in version["attributes"]["versionString"].split(".")[:2]) if version else (0, 0)
    return have >= LINKS_FROM


def library(kind):
    out, path = [], f"/v1/appAssetLibraries/{APP}/{kind}?limit=200&filter[category]=CREATIVE_ASSETS"
    while path:
        d = call("GET", path)
        out += d["data"]
        n = d.get("links", {}).get("next")
        path = n[len(API):] if n else None
    return out


def upload(f, ref):
    data = f.read_bytes()
    d = call("POST", "/v1/appAssetLibraryImages", {"data": {"type": "appAssetLibraryImages", "attributes": {
        "category": "CREATIVE_ASSETS", "fileName": f.name, "fileSize": len(data), "referenceName": ref},
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": APP}}}}})["data"]
    for op in d["attributes"].get("uploadOperations") or []:
        hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders") or []}
        r = requests.request(op["method"], op["url"], headers=hdrs,
                             data=data[op["offset"]:op["offset"] + op["length"]], timeout=600)
        if r.status_code >= 400:
            sys.exit(f"chunk failed {r.status_code} {r.text[:300]}")
    call("PATCH", f"/v1/appAssetLibraryImages/{d['id']}", {"data": {"type": "appAssetLibraryImages", "id": d["id"],
         "attributes": {"uploaded": True}}})
    a = {}
    for _ in range(100):
        a = call("GET", f"/v1/appAssetLibraryImages/{d['id']}")["data"]["attributes"]
        if a.get("state") not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE"):
            break
        time.sleep(4)
    return d["id"], a


NAMES = {"card": "card-3840x2160.png", "details": "details-2160x3840.png", "header": "header-3840x1646.png"}


def art_files(p):
    """Card, details and (for a themed day) header PNGs, made once and cached."""
    d = CACHE / str(p["year"]) / p["id"]
    files = {k: d / v for k, v in NAMES.items() if k != "header" or p["theme"]}
    if not all(f.exists() for f in files.values()):
        subprocess.run([str(ART_PY), str(ROOT / "scripts/holiday_event_art.py"), str(CACHE),
                        "--id", p["id"], "--year", str(p["year"])], check=True)
    return files


def ref_for(p, kind):
    return f"milepost-holidays/{p['year']}/{p['id']}/{NAMES[kind]}"


def spec(p):
    e = p["event"]
    s, end = midnight(p["start"]), midnight(p["end"] + timedelta(days=1)) - timedelta(minutes=1)
    out = {"referenceName": p["ref"], "badge": e["badge"].upper().replace(" ", "_"),
           "purpose": "APPROPRIATE_FOR_ALL_USERS", "priority": "NORMAL", "territories": ["USA"],
           "publishStart": iso(s - timedelta(days=SHOW)), "eventStart": iso(s), "eventEnd": iso(end),
           "deepLink": p["link"], "purchaseRequirement": "NO_COST_ASSOCIATED",
           "name": e["name"], "shortDescription": e["short"], "longDescription": e["long"],
           "card": ref_for(p, "card"), "details": ref_for(p, "details")}
    for k, n in LIMITS.items():
        assert len(out[k]) <= n, (p["ref"], k, len(out[k]))
    return out


def open_submission():
    for r in call("GET", f"/v1/reviewSubmissions?filter[app]={APP}&filter[platform]=IOS&limit=20")["data"]:
        if r["attributes"].get("state") in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"):
            return r["id"], r["attributes"]["state"]
    return None, None


def submit(apply):
    """Draft events and unreviewed holiday headers, in one submission."""
    items = [("appEvent", "appEvents", e["id"], e["attributes"]["referenceName"])
             for e in call("GET", f"/v1/apps/{APP}/appEvents?limit=200")["data"]
             if e["attributes"].get("eventState") == "DRAFT"]
    items += [("appAssetLibraryImage", "appAssetLibraryImages", i["id"], i["attributes"]["referenceName"])
              for i in library("images")
              if i["attributes"].get("state") == "PREPARE_FOR_SUBMISSION"
              and i["attributes"].get("referenceName", "").startswith("milepost-holidays/")
              and "/header-" in i["attributes"]["referenceName"]]
    if not items:
        return
    names = ", ".join(x[3] for x in items)
    sid, st = open_submission()
    if sid:
        log(f"wait     {names}: submission {sid[:8]} is {st}")
        return
    if not apply:
        log(f"would submit {names}")
        return
    sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
               "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})["data"]
    for rel, typ, iid, _ in items:
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
            rel: {"data": {"type": typ, "id": iid}}}}})
    d = call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"],
             "attributes": {"submitted": True}}})["data"]
    log(f"submitted {names} as {sub['id'][:8]} ({d['attributes'].get('state')})")


def assets():
    out = {}
    for i in library("images"):
        a = i["attributes"]
        if a.get("state") != "ARCHIVED":
            out[a.get("referenceName")] = (i["id"], a.get("state"))
    return out


def place(asset_id, loc_id):
    return call("POST", "/v1/appAssetLibraryPlacements", {"data": {"type": "appAssetLibraryPlacements",
        "attributes": {"placementType": "PRODUCT_PAGE_HEADER_ASSET", "placementGroup": "DEFAULT_PROFILE"},
        "relationships": {"image": {"data": {"type": "appAssetLibraryImages", "id": asset_id}},
                          "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})["data"]


def swap_header(today, version, have, apply):
    """The live version's header: the themed day's approved header, or the
    everyday one. Apple can't edit a placement, so swap = delete + create,
    putting the old one back if the create fails."""
    if not version:
        return
    want, span = EVERYDAY_HEADER, None
    for h in DOC["holidays"]:
        if not h.get("theme"):
            continue
        for y in (today.year - 1, today.year, today.year + 1):
            day = holiday_day(h, y)
            a, b = day + timedelta(days=h["theme"]["from"]), day + timedelta(days=h["theme"]["to"])
            ref = f"milepost-holidays/{y}/{h['id']}/{NAMES['header']}"
            if a <= today <= b and have.get(ref, (0, ""))[1] == "APPROVED":
                if span is None or (b - a) < span:   # the shortest theme wins, as in the app
                    want, span = ref, b - a
    if want not in have:
        log(f"header   {want} isn't in the library; left as is")
        return
    # Apple refuses to delete a placement while a product page A/B test runs
    # (409 STATE_ERROR.EXPERIMENT_IN_PROGRESS, daily since 2026-10-25), so
    # wait it out, as mc_holidays_auto.py does.
    now = datetime.now(timezone.utc)
    for x in call("GET", f"/v1/apps/{APP}/appStoreVersionExperimentsV2?limit=50")["data"]:
        a = x["attributes"]
        if a.get("startDate") and a.get("endDate") and \
                datetime.fromisoformat(a["startDate"]) <= now < datetime.fromisoformat(a["endDate"]):
            log(f"header   kept: A/B test '{a.get('name')}' runs until {a['endDate'][:10]} (wanted {want})")
            return
    by_id = {v[0]: r for r, v in have.items()}
    for loc in call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]:
        for p in call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/placements?limit=200&include=image,video")["data"]:
            if p["attributes"]["placementType"] != "PRODUCT_PAGE_HEADER_ASSET":
                continue
            r = p["relationships"]
            cur = (r.get("image", {}).get("data") or r.get("video", {}).get("data") or {}).get("id")
            if by_id.get(cur) == want:
                continue
            log(("swap" if apply else "would swap"), loc["attributes"]["locale"], by_id.get(cur), "->", want)
            if not apply:
                continue
            call("DELETE", f"/v1/appAssetLibraryPlacements/{p['id']}")
            try:
                place(have[want][0], loc["id"])
            except BaseException:
                place(cur, loc["id"])
                raise


def main():
    import asc_app_events
    apply = "--apply" in sys.argv
    today = datetime.now(timezone.utc).astimezone(timezone(NY)).date()
    log(f"==> {today} ({'apply' if apply else 'plan only'})")
    version = live_version()
    log("live version", version["attributes"]["versionString"] if version else None)
    events = {e["attributes"]["referenceName"] for e in call("GET", f"/v1/apps/{APP}/appEvents?limit=200")["data"]}
    have = assets()
    for p in sorted(planned(today), key=lambda x: x["start"]):
        if p["ref"] in events:
            continue
        if not opens(version):
            log(f"later    {p['ref']}: {p['link']} needs version {'.'.join(map(str, LINKS_FROM))} live")
            continue
        if not apply:
            log(f"would create {p['ref']}: {p['start']} to {p['end']} ({p['link']})")
            continue
        for kind, f in art_files(p).items():
            ref = ref_for(p, kind)
            if ref not in have:
                iid, a = upload(f, ref)
                have[ref] = (iid, a.get("state"))
                log(f"uploaded {ref} ({a.get('state')})")
        s = spec(p)
        now = datetime.now(timezone.utc)
        if datetime.fromisoformat(s["eventStart"].replace("Z", "+00:00")) < now:
            s["eventStart"] = iso(now + timedelta(hours=1))
        if datetime.fromisoformat(s["publishStart"].replace("Z", "+00:00")) < now:
            s["publishStart"] = iso(now + timedelta(hours=1))
        asc_app_events.create(APP, s)
    submit(apply)
    swap_header(today, version, assets() if apply else have, apply)


if __name__ == "__main__":
    main()
