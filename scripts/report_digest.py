#!/usr/bin/env python3
"""Daily email of new Milepost abuse reports (security audit 2026-10-07, L4).

Runs on the divinedavis.com droplet (104.236.120.144) as
/usr/local/bin/milepost-report-digest from /etc/cron.d/milepost-report-digest.
Reads ops.report_digest through the Supabase session pooler as the
read-only role milepost_report_digest (migration 0010; credentials in
/etc/milepost-report-digest.env, 0600) and mails through uptime-watch's
SMTP helper, so it adds no service and nothing that bills.

Sends nothing when there is nothing new. A failed query DOES send, so a
broken digest never looks like a quiet day.

    milepost-report-digest               # the cron run
    milepost-report-digest --dry-run     # print, send nothing, keep state
    milepost-report-digest --test-email  # prove delivery
"""
from __future__ import annotations

import csv
import importlib.machinery
import io
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ENV = Path("/etc/milepost-report-digest.env")
STATE = Path("/var/lib/milepost-report-digest/state.json")
UPTIME_WATCH = "/usr/local/bin/uptime-watch"
COLUMNS = ["id", "created_at", "reason", "activity_id", "reporter", "target", "target_id", "target_total"]


def read_env(path: Path) -> dict:
    out = {}
    for line in path.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def query(since: datetime) -> list[dict]:
    sql = (f"select {', '.join(COLUMNS)} from ops.report_digest "
           f"where created_at > '{since.isoformat()}'::timestamptz order by created_at limit 500")
    env = dict(os.environ, **read_env(ENV))
    r = subprocess.run(["psql", "-X", "--csv", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       capture_output=True, text=True, env=env, timeout=60)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout).strip()[:500])
    return list(csv.DictReader(io.StringIO(r.stdout)))


def parse_ts(s: str) -> datetime:
    """psql prints `2026-10-07 16:58:12.123456+00`; older Pythons want +00:00."""
    s = s.strip().replace(" ", "T")
    if re.search(r"[+-]\d\d$", s):
        s += ":00"
    return datetime.fromisoformat(s)


def format_digest(rows: list[dict]) -> tuple[str, str]:
    n = len(rows)
    subject = f"Milepost: {n} new report{'s' if n != 1 else ''}"
    lines = [f"{n} new report{'s' if n != 1 else ''} in public.reports since the last digest.", ""]
    for r in rows:
        target = "@" + r["target"] if r.get("target") else f"(deleted user {r['target_id']})"
        reporter = "@" + r["reporter"] if r.get("reporter") else "(deleted user)"
        lines.append(f"- {r['created_at'][:16]}Z  {target} reported by {reporter}: {r['reason']}")
        extra = []
        if r.get("activity_id"):
            extra.append(f"activity {r['activity_id']}")
        if r.get("target_total") and int(r["target_total"]) > 1:
            extra.append(f"{r['target_total']} reports against them in total")
        if extra:
            lines.append("    " + "; ".join(extra))
    lines += ["", "Act with scripts in ~/projects/Milepost (block / delete via the service role).",
              "This digest only reads; nothing was changed."]
    return subject, "\n".join(lines)


def send(subject: str, body: str) -> None:
    uw = importlib.machinery.SourceFileLoader("uw", UPTIME_WATCH).load_module()
    uw.send(uw.env(), subject, body)


def main(argv: list[str]) -> int:
    if "--test-email" in argv:
        send("Milepost report digest: test", "Delivery test for the daily Milepost report digest.")
        print("sent test")
        return 0
    dry = "--dry-run" in argv
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    since = (datetime.fromisoformat(state["since"]) if "since" in state
             else datetime.now(timezone.utc) - timedelta(days=1))
    started = datetime.now(timezone.utc)
    try:
        rows = query(since)
    except Exception as e:  # noqa: BLE001 — any failure must reach the owner
        msg = f"The Milepost report digest could not read reports: {e}"
        print(msg, file=sys.stderr)
        if not dry:
            send("Milepost report digest FAILED", msg)
        return 1
    if rows:
        subject, body = format_digest(rows)
        if dry:
            print(subject + "\n\n" + body)
        else:
            send(subject, body)
        # Never skip a report: advance to the newest one actually mailed.
        newest = max(parse_ts(r["created_at"]) for r in rows)
        state["since"] = newest.isoformat()
    else:
        state["since"] = max(since, started - timedelta(minutes=5)).isoformat()
    print(f"{started.isoformat()} {len(rows)} new report(s)")
    if not dry:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(state))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
