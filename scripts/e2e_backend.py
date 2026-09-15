#!/usr/bin/env python3
"""End-to-end check of the friends backend with real JWTs.

Creates three throwaway users through the admin API, then as those users:
profiles -> search -> share an activity -> friend request -> accept -> the
friend sees it and a stranger does not -> report -> block ends everything ->
delete_account cascades. Also proves anon can do nothing and that no function
is executable without a session. Email/password is enabled only for the
duration of the run (the app itself is Apple-only).

    ~/.venvs/spendcap/bin/python scripts/e2e_backend.py
"""
from __future__ import annotations

import subprocess
import sys
import time
import uuid

import requests

REF = "pmdcwgsxxyagmkkypvma"
URL = f"https://{REF}.supabase.co"
MGMT = f"https://api.supabase.com/v1/projects/{REF}"


def keychain(service: str) -> str:
    return subprocess.check_output(
        ["security", "find-generic-password", "-a", subprocess.check_output(["id", "-un"]).decode().strip(), "-s", service, "-w"]
    ).decode().strip()


PAT = keychain("supabase-pat-clockin")
ANON = keychain("milepost-supabase-anon")
SERVICE = keychain("milepost-supabase-service")
MH = {"Authorization": f"Bearer {PAT}", "User-Agent": "curl/8.7.1", "Content-Type": "application/json"}
ANON_H = {"apikey": ANON, "Authorization": f"Bearer {ANON}", "Content-Type": "application/json"}
FUNCTIONS = ["search_profiles", "send_friend_request", "respond_friend_request", "remove_friend",
             "block_user", "list_blocked", "list_connections", "friend_feed", "delete_account"]


def check(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        raise SystemExit(1)


def sql(query: str):
    r = requests.post(f"{MGMT}/database/query", headers=MH, json={"query": query}, timeout=60)
    r.raise_for_status()
    return r.json()


def set_email_auth(enabled: bool):
    requests.patch(f"{MGMT}/config/auth", headers=MH, json={"external_email_enabled": enabled}, timeout=30).raise_for_status()


class User:
    def __init__(self, tag: str):
        self.email = f"e2e-{tag}-{uuid.uuid4().hex[:8]}@example.com"
        self.password = uuid.uuid4().hex
        self.username = f"e2e_{tag}_{uuid.uuid4().hex[:6]}"
        r = requests.post(f"{URL}/auth/v1/admin/users", headers={"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"},
                          json={"email": self.email, "password": self.password, "email_confirm": True}, timeout=30)
        r.raise_for_status()
        self.id = r.json()["id"]
        # The auth-config toggle takes a few seconds to reach GoTrue.
        for _ in range(12):
            r = requests.post(f"{URL}/auth/v1/token?grant_type=password", headers={"apikey": ANON},
                              json={"email": self.email, "password": self.password}, timeout=30)
            if r.status_code == 200:
                break
            time.sleep(5)
        if r.status_code != 200:
            self.admin_delete()  # never strand a throwaway user
            raise SystemExit(f"password grant failed: {r.status_code} {r.text}")
        self.jwt = r.json()["access_token"]

    @property
    def h(self):
        return {"apikey": ANON, "Authorization": f"Bearer {self.jwt}", "Content-Type": "application/json"}

    def rest(self, method, path, **kw):
        headers = dict(self.h)
        headers.update(kw.pop("headers", {}))
        return requests.request(method, f"{URL}/rest/v1/{path}", headers=headers, timeout=30, **kw)

    def rpc(self, fn, **params):
        return self.rest("POST", f"rpc/{fn}", json=params)

    def admin_delete(self):
        requests.delete(f"{URL}/auth/v1/admin/users/{self.id}",
                        headers={"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"}, timeout=30)


def main():
    print("== function ACLs")
    rows = sql("select p.proname, has_function_privilege('anon', p.oid, 'EXECUTE') as anon "
               "from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'")
    anon_exec = sorted(r["proname"] for r in rows if r["anon"])
    check(anon_exec == [], f"no public function executable by anon ({anon_exec})")
    r = requests.post(f"{URL}/rest/v1/rpc/search_profiles", headers=ANON_H, json={"q": "e2e"}, timeout=30)
    check(r.status_code in (401, 403, 404), f"anon cannot search ({r.status_code})")

    set_email_auth(True)
    a = b = c = None
    try:
        a, b, c = User("a"), User("b"), User("c")
        print("== profiles")
        r = a.rest("POST", "profiles", json={"id": a.id, "username": a.username, "display_name": "Runner A"})
        check(r.status_code == 201, f"A creates own profile ({r.status_code} {r.text[:100]})")
        r = a.rest("POST", "profiles", json={"id": b.id, "username": "squatter"})
        check(r.status_code in (401, 403), f"A cannot create a profile for B ({r.status_code})")
        for u in (b, c):
            r = u.rest("POST", "profiles", json={"id": u.id, "username": u.username})
            check(r.status_code == 201, f"{u.username} creates own profile ({r.status_code})")
        r = c.rest("POST", "profiles", json={"id": c.id, "username": a.username})
        check(r.status_code in (401, 403, 409), f"duplicate username refused ({r.status_code})")
        r = a.rest("GET", f"profiles?select=id&id=eq.{b.id}")
        check(r.json() == [], "a stranger's profile is not readable from the table")

        print("== search")
        r = a.rpc("search_profiles", q=b.username[:6])
        found = {row["id"]: row["status"] for row in r.json()} if r.status_code == 200 else {}
        check(found.get(b.id) == "none" and a.id not in found, f"A finds B by prefix, not self ({r.status_code} {r.text[:120]})")
        r = a.rpc("search_profiles", q="e")
        check(r.status_code == 200 and r.json() == [], "one-character search returns nothing")
        r = a.rpc("search_profiles", q="e2e%")
        check(r.status_code == 200 and r.json() == [], "LIKE wildcards are escaped")

        print("== sharing before friendship")
        act = str(uuid.uuid4())
        r = a.rest("POST", "shared_activities", json={"user_id": a.id, "id": act, "sport": "run", "title": "Morning Run",
                                                      "start_date": "2026-09-10T11:00:00Z", "distance_m": 5012.3, "moving_s": 1500})
        check(r.status_code == 201, f"A shares an activity ({r.status_code} {r.text[:100]})")
        r = a.rest("POST", "shared_activities", headers={"Prefer": "resolution=merge-duplicates"},
                   json={"user_id": a.id, "id": act, "sport": "run", "title": "Renamed Run",
                         "start_date": "2026-09-10T11:00:00Z", "distance_m": 5012.3, "moving_s": 1500})
        check(r.status_code in (200, 201), f"re-upload is an upsert ({r.status_code} {r.text[:100]})")
        r = b.rest("POST", "shared_activities", json={"user_id": a.id, "id": str(uuid.uuid4()), "sport": "run", "title": "spoof",
                                                      "start_date": "2026-09-10T11:00:00Z", "distance_m": 1, "moving_s": 1})
        check(r.status_code in (401, 403), f"B cannot share as A ({r.status_code})")
        r = b.rest("POST", "shared_activities", json={"user_id": b.id, "id": str(uuid.uuid4()), "sport": "swim", "title": "x",
                                                      "start_date": "2026-09-10T11:00:00Z", "distance_m": 1, "moving_s": 1})
        check(r.status_code == 400, f"unknown sport refused ({r.status_code})")
        r = b.rest("GET", f"shared_activities?select=id&user_id=eq.{a.id}")
        check(r.json() == [], "B (not a friend) cannot read A's activity")
        r = requests.get(f"{URL}/rest/v1/shared_activities?select=id", headers=ANON_H, timeout=30)
        check(r.status_code == 200 and r.json() == [], "anon reads zero activities")

        print("== friend request")
        r = b.rest("POST", "friendships", json={"requester_id": b.id, "addressee_id": a.id, "status": "accepted"})
        check(r.status_code in (401, 403), f"friendships cannot be written directly ({r.status_code})")
        r = a.rpc("send_friend_request", target=a.id)
        check(r.status_code >= 400, f"cannot friend yourself ({r.status_code})")
        r = a.rpc("send_friend_request", target=b.id)
        check(r.status_code == 200 and r.json() == "outgoing", f"A asks B ({r.status_code} {r.text[:100]})")
        r = b.rpc("list_connections")
        check(any(x["id"] == a.id and x["status"] == "incoming" for x in r.json()), f"B sees A's incoming request ({r.text[:120]})")
        r = b.rest("GET", f"profiles?select=username&id=eq.{a.id}")
        check(r.json() == [{"username": a.username}], "B can read A's profile once a request exists")
        r = b.rest("GET", f"shared_activities?select=id&user_id=eq.{a.id}")
        check(r.json() == [], "a pending request shows no activities")
        r = b.rpc("respond_friend_request", requester=a.id, accept=True)
        check(r.status_code in (200, 204), f"B accepts ({r.status_code} {r.text[:100]})")

        print("== feed")
        r = b.rpc("friend_feed")
        feed = r.json() if r.status_code == 200 else []
        check(len(feed) == 1 and feed[0]["id"] == act and feed[0]["title"] == "Renamed Run" and feed[0]["username"] == a.username,
              f"B sees A's activity in friend_feed ({r.status_code} {r.text[:160]})")
        check(not any(k in feed[0] for k in ("route", "latitude", "longitude", "polyline")), "the feed row carries no location")
        r = a.rest("PATCH", f"shared_activities?user_id=eq.{a.id}&id=eq.{act}",
                   json={"sport": "strollerRun", "title": "Stroller Run"})
        check(r.status_code in (200, 204), f"A saves the stroller run type ({r.status_code})")
        r = b.rpc("friend_feed")
        check(r.status_code == 200 and len(r.json()) == 1 and r.json()[0]["sport"] == "strollerRun",
              "the friend feed preserves the stroller run type")
        r = c.rpc("friend_feed")
        check(r.status_code == 200 and r.json() == [], "C (a stranger) sees nothing")
        r = a.rpc("friend_feed")
        check(r.status_code == 200 and r.json() == [], "your own activities are not in your friend feed")
        r = b.rest("PATCH", f"shared_activities?user_id=eq.{a.id}&id=eq.{act}", headers={"Prefer": "return=representation"},
                   json={"title": "defaced"})
        check(r.status_code == 200 and r.json() == [], "B cannot edit A's activity")
        r = b.rest("DELETE", f"shared_activities?user_id=eq.{a.id}&id=eq.{act}", headers={"Prefer": "return=representation"})
        check(r.status_code == 200 and r.json() == [], "B cannot delete A's activity")

        print("== demo friend (App Review)")
        r = c.rpc("search_profiles", q="milepost_demo")
        demo = next((x for x in r.json() if x["username"] == "milepost_demo"), None) if r.status_code == 200 else None
        check(demo is not None, "@milepost_demo is findable (run seed_demo_friend.py if not)")
        r = c.rpc("send_friend_request", target=demo["id"])
        check(r.status_code == 200 and r.json() == "friend", f"a request to the demo account is accepted at once ({r.text[:80]})")
        r = c.rpc("friend_feed")
        check(r.status_code == 200 and len(r.json()) > 0, "its sample activities show up")
        r = c.rpc("remove_friend", other=demo["id"])
        check(r.status_code in (200, 204), "and it can be unfriended")
        r = c.rest("GET", "demo_accounts?select=id")
        check(r.status_code in (401, 403) or r.json() == [], f"demo_accounts is invisible to clients ({r.status_code})")

        print("== report + block")
        r = b.rest("POST", "reports", json={"target_id": a.id, "activity_id": act, "reason": "e2e test"})
        check(r.status_code == 201, f"B reports A ({r.status_code} {r.text[:100]})")
        r = b.rest("GET", "reports?select=id")
        check(r.status_code in (200, 401, 403) and (r.status_code != 200 or r.json() == []), "reports are write-only")
        r = a.rpc("block_user", target=b.id)
        check(r.status_code in (200, 204), f"A blocks B ({r.status_code} {r.text[:100]})")
        r = b.rpc("friend_feed")
        check(r.json() == [], "the block ended B's view of A's activities")
        r = b.rpc("search_profiles", q=a.username)
        check(r.json() == [], "the blocker is invisible to the blocked in search")
        r = b.rpc("send_friend_request", target=a.id)
        check(r.status_code >= 400 and "not found" in r.text, f"the blocked cannot re-request ({r.status_code})")
        r = a.rpc("list_blocked")
        check([x["id"] for x in r.json()] == [b.id], "A's blocked list has B")
        r = a.rest("DELETE", f"blocks?blocked_id=eq.{b.id}", headers={"Prefer": "return=representation"})
        check(r.status_code == 200 and len(r.json()) == 1, "A can unblock B")

        print("== delete account")
        r = a.rpc("delete_account")
        check(r.status_code in (200, 204), f"A deletes account ({r.status_code} {r.text[:100]})")
        rows = sql(f"select (select count(*) from public.profiles where id = '{a.id}') as p, "
                   f"(select count(*) from public.shared_activities where user_id = '{a.id}') as s, "
                   f"(select count(*) from public.reports where target_id = '{a.id}') as r, "
                   f"(select count(*) from auth.users where id = '{a.id}') as u")
        check(rows[0] == {"p": 0, "s": 0, "r": 0, "u": 0}, f"everything of A's cascaded away ({rows[0]})")
        a = None
        print("ALL OK")
    finally:
        for u in (a, b, c):
            if u is not None:
                u.admin_delete()
        set_email_auth(False)
        r = requests.get(f"{MGMT}/config/auth", headers=MH, timeout=30).json()
        print("external_email_enabled restored to", r["external_email_enabled"])


if __name__ == "__main__":
    main()
