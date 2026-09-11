#!/usr/bin/env python3
"""Write the App Store listing for Milepost through the API.

Everything App Store Connect accepts over its API lives here so the listing is
a file in the repo, not a memory of which boxes were ticked: categories,
subtitle, description, keywords, URLs, copyright, the age rating
questionnaire, the review contact + notes, the price, and availability.

Idempotent — every call is a PATCH or an upsert.

    python3 scripts/asc_metadata.py            # apply
    python3 scripts/asc_metadata.py --show     # print what is there now

Not reachable over the public API:
  * App Privacy (the data-collection labels) — scripts/asc_push_privacy_iris.py
    drives Apple's private iris API with a fastlane spaceauth cookie.
  * Submitting — scripts/asc_submit_for_review.py (reviewSubmissions works).

The review contact's phone number is a real person's, so it comes from the
gitignored asc-config.env: ASC_CONTACT_FIRST_NAME / _LAST_NAME / _PHONE / _EMAIL.
There is no demo account: the app has no sign-in.
"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc import ASC, load_config  # noqa: E402

NAME = "Milepost: Run, Walk & Ride"                   # <= 30 characters
SUBTITLE = "GPS run, walk & ride tracker"                 # <= 30 characters
# Words already in the name or subtitle are indexed from there, so they are
# not repeated here.
KEYWORDS = ("running,walking,cycling,bike,biking,pace,splits,"
            "miles,jog,jogging,route,distance,fitness,cues")   # <= 100 characters
PROMO = ("Press Start, run, press Finish. Time, pace and distance live, splits as "
         "they happen, your route on a map. Add friends to see their runs; routes stay on your phone.")
SUPPORT = "https://divinedavis.com/milepost/support/"
PRIVACY = "https://divinedavis.com/milepost/privacy/"
COPYRIGHT = "2026 Divine Davis"
PRIMARY_CATEGORY = "HEALTH_AND_FITNESS"
SECONDARY_CATEGORY = "SPORTS"

DESCRIPTION = """Milepost records your runs, walks and bike rides and keeps them on your phone. Press Start, go, press Finish. That is the whole app.

WHILE YOU RUN
A full-screen recorder shows the clock, your current split pace and distance in big type you can read at a glance. Pause stops the clock, Resume picks it up, Finish saves. Lock the phone or switch apps and the recording keeps going. Collapse the recorder and the same run sits on the map with your route drawing in as you move.

SPLITS AS THEY HAPPEN
Every mile (or kilometre) rolls onto a splits bar so you can see whether this one is faster or slower than the last. Runs that cover less than a few metres are caught before they are saved, so a false start never clutters your log.

VOICE CUES
Optional spoken cues every mile or every half mile with your time and last split pace, read over your music with the screen locked.

YOUR LOG
Every activity with its route on a map, distance, time, average pace, and each split. Weekly and all-time totals on the You tab. Miles or kilometres, your choice, and each run keeps the unit it was recorded in.

FRIENDS ON THE BLOCK
The Block tab has two sides: Mine, your own log, and Friends. Sign in with Apple, pick a username, and add friends by searching for theirs. Once they accept, you see each other's activities: sport, title, distance, pace and time. Friends are optional; without an account the app works exactly the same.

YOUR ROUTES STAY ON YOUR PHONE
Recording needs no account. Runs and their routes live in a database on your phone. If you sign in for friends, only each activity's stats are shared, and only with people you accept. Maps, GPS points and splits are never uploaded. Turn sharing off or delete your account from the You tab at any time. There are no ads and no analytics. Location is asked for when you press Start and used only while a run is recording.

Milepost uses GPS, so it needs open sky; runs that start indoors show distance once you are outside and moving.
"""

REVIEW_NOTES = """WHAT THE APP DOES
Milepost records a run, walk or bike ride with GPS: elapsed time, distance, split pace, mile/km splits, and the route drawn on an Apple map. Runs are saved to a local database on the device. Recording needs no account and there is no in-app purchase.

FRIENDS (OPTIONAL, SIGN IN WITH APPLE)
Block tab > Friends > Continue with Apple, then pick any username. Tap the person-plus button, search "milepost_demo" and tap Add: that demo account accepts requests automatically and has sample activities, so its runs appear in Block > Friends right away. Friends see only an activity's sport, title, distance, pace and time - never the route. Swipe a friend's activity (or long-press) to Report or Block. You tab > Friends: sharing toggle, Sign out, and Delete account (deletes the account and everything shared, immediately).

HOW TO TEST
1. Record tab: press Start. iOS asks for location access ("While Using the App"). The full-screen recorder opens with a running clock.
2. Move, or in the Simulator use Features > Location > Freeway Drive / City Run. Distance and split pace update live and the route draws on the map.
3. Press Pause, then Finish. Name the run and tap Save. (Finishing with under 10 metres of movement shows a "No Movement Detected" alert instead of a save sheet - that is intentional.)
4. Block tab: the saved run with its route map, tiles and splits. You tab: weekly/all-time totals, the miles/km switch, and Voice cues (spoken split announcements, off by default).

BACKGROUND LOCATION
The app declares the location background mode so a run keeps recording with the screen locked. It requests only "When In Use" authorization and reads location solely between Start and Finish. The audio background mode is used only for the optional spoken voice cues during a run.

CONTACT
Any question at all: the email and phone number above.
"""

# A run tracker. "Health or wellness topics" in Apple's questionnaire means
# self-care/lifestyle recommendations (calorie tracking, dieting advice,
# exercise recommendations); Milepost records what you did and recommends
# nothing, so it stays 4+. The newer questionnaire fields are BOOLEANs, the
# older content fields three-value enums, and all of them must go in one PATCH.
AGE_RATING = {
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "contests": "NONE",
    "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE",
    "horrorOrFearThemes": "NONE",
    "matureOrSuggestiveThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE",
    "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE",
    "sexualContentOrNudity": "NONE",
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "advertising": False,
    "ageAssurance": False,
    "gambling": False,
    "healthOrWellnessTopics": False,
    "lootBox": False,
    "messagingAndChat": False,
    "parentalControls": False,
    "unrestrictedWebAccess": False,
    "userGeneratedContent": False,
    "ageRatingOverride": "NONE",
}


def resolve(asc: ASC, app_id: str) -> dict:
    info = asc.get(f"/apps/{app_id}/appInfos")["data"][0]
    version = asc.editable_version(app_id)
    return {
        "info": info["id"],
        "info_loc": asc.get(f"/appInfos/{info['id']}/appInfoLocalizations")["data"][0]["id"],
        "version": version["id"],
        "version_string": version["attributes"]["versionString"],
        "version_loc": asc.get(
            f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"][0]["id"],
    }


def ensure_price_free(asc: ASC, app_id: str) -> None:
    # A schedule object can exist with a base territory and NO prices, and
    # submission then fails with APP_PRICING_REQUIRED — check the prices.
    existing = asc.s.get(f"{asc._url('/appPriceSchedules/' + app_id + '/manualPrices')}", timeout=30)
    if existing.status_code == 200 and existing.json().get("data"):
        print("    price schedule already set — left alone")
        return
    points = asc.get(f"/apps/{app_id}/appPricePoints",
                     **{"filter[territory]": "USA", "limit": 200})["data"]
    free = next(p for p in points if float(p["attributes"]["customerPrice"]) == 0.0)
    asc.post("/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
        "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": {
                          "data": {"type": "appPricePoints", "id": free["id"]}}}}]})
    print("    price: free")


def ensure_availability(asc: ASC, app_id: str) -> None:
    """An app with no availability record is approved and then never listed
    ("removed from sale" banner, lookup returns nothing). Create it once,
    every territory, and opt into new ones."""
    r = asc.s.get(f"{asc._url('/apps/' + app_id + '/appAvailabilityV2')}", timeout=30)
    if r.status_code == 200:
        print("    availability record exists — left alone")
        return
    territories = [t["id"] for t in asc.get("/territories", limit=200)["data"]]
    asc.post("/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities",
                 "attributes": {"availableInNewTerritories": True},
                 "relationships": {
                     "app": {"data": {"type": "apps", "id": app_id}},
                     "territoryAvailabilities": {"data": [
                         {"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
        "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}",
                      "attributes": {"available": True},
                      "relationships": {"territory": {"data": {"type": "territories", "id": t}}}}
                     for t in territories]})
    print(f"    availability: {len(territories)} territories")


def apply(asc: ASC, cfg: dict) -> None:
    assert len(NAME) <= 30, "name over 30 chars"
    assert len(SUBTITLE) <= 30, "subtitle over 30 chars"
    assert len(KEYWORDS) <= 100, f"keywords over 100 chars ({len(KEYWORDS)})"
    assert len(PROMO) <= 170, f"promotional text over 170 chars ({len(PROMO)})"
    assert len(DESCRIPTION) <= 4000, "description over 4000 chars"
    assert len(REVIEW_NOTES) <= 4000, "review notes over 4000 chars"

    app_id = cfg["ASC_APP_ID"]
    ids = resolve(asc, app_id)
    print(f"==> version {ids['version_string']}")

    asc.patch(f"/apps/{app_id}", {"data": {
        "type": "apps", "id": app_id,
        "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    print("    content rights")

    asc.patch(f"/appInfos/{ids['info']}", {"data": {
        "type": "appInfos", "id": ids["info"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": PRIMARY_CATEGORY}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": SECONDARY_CATEGORY}}}}})
    print(f"    categories {PRIMARY_CATEGORY} / {SECONDARY_CATEGORY}")

    asc.patch(f"/appInfoLocalizations/{ids['info_loc']}", {"data": {
        "type": "appInfoLocalizations", "id": ids["info_loc"],
        "attributes": {"name": NAME, "subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY}}})
    print("    name, subtitle + privacy policy URL")

    asc.patch(f"/appStoreVersionLocalizations/{ids['version_loc']}", {"data": {
        "type": "appStoreVersionLocalizations", "id": ids["version_loc"],
        "attributes": {"description": DESCRIPTION, "keywords": KEYWORDS,
                       "promotionalText": PROMO, "supportUrl": SUPPORT}}})
    print("    description, keywords, promo, support URL")

    asc.patch(f"/appStoreVersions/{ids['version']}", {"data": {
        "type": "appStoreVersions", "id": ids["version"],
        "attributes": {"copyright": COPYRIGHT, "usesIdfa": False, "releaseType": "AFTER_APPROVAL"}}})
    print("    copyright, IDFA, release after approval")

    asc.patch(f"/ageRatingDeclarations/{ids['info']}", {"data": {
        "type": "ageRatingDeclarations", "id": ids["info"], "attributes": AGE_RATING}})
    print("    age rating (4+)")

    missing = [k for k in ("ASC_CONTACT_FIRST_NAME", "ASC_CONTACT_LAST_NAME",
                           "ASC_CONTACT_PHONE", "ASC_CONTACT_EMAIL") if not cfg.get(k)]
    if missing:
        raise SystemExit("asc-config.env is missing: " + ", ".join(missing))
    attributes = {
        "contactFirstName": cfg["ASC_CONTACT_FIRST_NAME"],
        "contactLastName": cfg["ASC_CONTACT_LAST_NAME"],
        "contactPhone": cfg["ASC_CONTACT_PHONE"],
        "contactEmail": cfg["ASC_CONTACT_EMAIL"],
        "demoAccountRequired": False, "notes": REVIEW_NOTES,
    }
    detail = asc.get(f"/appStoreVersions/{ids['version']}/appStoreReviewDetail").get("data")
    if detail:
        asc.patch(f"/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"], "attributes": attributes}})
    else:
        asc.post("/appStoreReviewDetails", {"data": {
            "type": "appStoreReviewDetails", "attributes": attributes,
            "relationships": {"appStoreVersion": {
                "data": {"type": "appStoreVersions", "id": ids["version"]}}}}})
    print("    review contact + notes (no demo account needed)")

    ensure_price_free(asc, app_id)
    ensure_availability(asc, app_id)


def show(asc: ASC, cfg: dict) -> None:
    app_id = cfg["ASC_APP_ID"]
    ids = resolve(asc, app_id)
    loc = asc.get(f"/appStoreVersionLocalizations/{ids['version_loc']}")["data"]["attributes"]
    info_loc = asc.get(f"/appInfoLocalizations/{ids['info_loc']}")["data"]["attributes"]
    version = asc.get(f"/appStoreVersions/{ids['version']}")["data"]["attributes"]
    detail = asc.get(f"/appStoreVersions/{ids['version']}/appStoreReviewDetail").get("data")
    build = asc.get(f"/appStoreVersions/{ids['version']}/build").get("data")
    info = asc.get(f"/appInfos/{ids['info']}", include="primaryCategory,secondaryCategory")["data"]
    cats = [c["data"]["id"] if c.get("data") else None
            for c in (info["relationships"].get("primaryCategory", {}), info["relationships"].get("secondaryCategory", {}))]
    prices = asc.s.get(asc._url(f"/appPriceSchedules/{app_id}/manualPrices"), timeout=30)
    avail = asc.s.get(asc._url(f"/apps/{app_id}/appAvailabilityV2"), timeout=30)
    print(f"version {version['versionString']}  {version['appStoreState']}")
    print(f"  categories   {cats}")
    print(f"  name         {info_loc['name']}")
    print(f"  subtitle     {info_loc['subtitle']}")
    print(f"  description  {len(loc['description'] or '')} chars")
    print(f"  keywords     {loc['keywords']}")
    print(f"  support      {loc['supportUrl']}")
    print(f"  privacy      {info_loc['privacyPolicyUrl']}")
    print(f"  copyright    {version['copyright']}")
    print(f"  build        {build['attributes']['version'] if build else '(none attached)'}")
    print(f"  review info  {'set' if detail else 'MISSING'}")
    print(f"  price        {'set' if prices.status_code == 200 and prices.json().get('data') else 'MISSING'}")
    print(f"  availability {'record exists' if avail.status_code == 200 else 'MISSING'}")


def main() -> None:
    cfg = load_config()
    asc = ASC(cfg)
    (show if "--show" in sys.argv else apply)(asc, cfg)


if __name__ == "__main__":
    main()
