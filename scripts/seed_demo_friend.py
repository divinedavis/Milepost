#!/usr/bin/env python3
"""Create or refresh @milepost_demo, the friend App Review can add.

Requests to it are accepted by a trigger (0002_demo_friend.sql) and it carries
sample activities dated relative to today, so re-run this before a submission.
Its auth user has a random password and email sign-in is disabled on the
project, so nobody can sign in as it.

    ~/.venvs/spendcap/bin/python scripts/seed_demo_friend.py
"""
from __future__ import annotations

import datetime as dt
import secrets
import subprocess
import uuid

import requests

REF = "pmdcwgsxxyagmkkypvma"
URL = f"https://{REF}.supabase.co"
USERNAME = "milepost_demo"
DISPLAY = "Milepost Demo"

# (title, sport, meters, moving seconds, days ago, hour)
SAMPLES = [
    ("Morning Loop", "run", 5230, 1620, 1, 7),
    ("Prospect Park Walk", "walk", 3400, 2580, 2, 18),
    ("Bridge Ride", "bike", 24100, 3720, 4, 9),
    ("Tempo Miles", "run", 8050, 2310, 6, 6),
    ("Easy Shakeout", "run", 4020, 1500, 9, 17),
]


def keychain(service: str) -> str:
    user = subprocess.check_output(["id", "-un"]).decode().strip()
    return subprocess.check_output(["security", "find-generic-password", "-a", user, "-s", service, "-w"]).decode().strip()


SERVICE = keychain("milepost-supabase-service")
H = {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}", "Content-Type": "application/json"}


def rest(method: str, path: str, **kw) -> requests.Response:
    headers = dict(H)
    headers.update(kw.pop("headers", {}))
    r = requests.request(method, f"{URL}/rest/v1/{path}", headers=headers, timeout=30, **kw)
    if r.status_code >= 300:
        raise SystemExit(f"{method} {path}: {r.status_code} {r.text[:200]}")
    return r


def main() -> int:
    rows = rest("GET", f"profiles?select=id&username=eq.{USERNAME}").json()
    if rows:
        uid = rows[0]["id"]
        print(f"@{USERNAME} exists ({uid})")
    else:
        r = requests.post(f"{URL}/auth/v1/admin/users", headers=H, timeout=30, json={
            "email": f"milepost-demo-{uuid.uuid4().hex[:8]}@example.com",
            "password": secrets.token_urlsafe(32), "email_confirm": True})
        r.raise_for_status()
        uid = r.json()["id"]
        rest("POST", "profiles", json={"id": uid, "username": USERNAME, "display_name": DISPLAY})
        print(f"created @{USERNAME} ({uid})")
    rest("POST", "demo_accounts", headers={"Prefer": "resolution=ignore-duplicates"}, json={"id": uid})

    rest("DELETE", f"shared_activities?user_id=eq.{uid}")
    today = dt.datetime.now(dt.timezone.utc).replace(minute=0, second=0, microsecond=0)
    payload = [{
        "user_id": uid, "id": str(uuid.uuid4()), "sport": sport, "title": title,
        "start_date": (today - dt.timedelta(days=days)).replace(hour=hour).isoformat(),
        "distance_m": meters, "moving_s": seconds,
    } for title, sport, meters, seconds, days, hour in SAMPLES]
    rest("POST", "shared_activities", json=payload)
    print(f"seeded {len(payload)} activities, newest {payload[0]['start_date']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
