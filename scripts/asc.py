#!/usr/bin/env python3
"""Shared App Store Connect client for the Milepost scripts.

JWT auth from the gitignored asc-config.env (key id, issuer, .p8 path, app id,
review contact). Every other asc_*.py imports ASC + load_config from here.

    python3 scripts/asc.py status     # app record, versions, builds
"""
from __future__ import annotations

import os
import pathlib
import sys
import time

import jwt
import requests

CONFIG_PATH = pathlib.Path(__file__).resolve().parent / "asc-config.env"
API = "https://api.appstoreconnect.apple.com/v1"
# /v2 endpoints (appAvailabilities) share the host, not the version prefix.
HOST = "https://api.appstoreconnect.apple.com"

EDITABLE_STATES = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                   "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise SystemExit(f"missing {CONFIG_PATH} — copy asc-config.env.example")
    cfg: dict = {}
    for line in CONFIG_PATH.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        k, _, v = s.partition("=")
        cfg[k.strip()] = os.path.expandvars(v.strip().strip('"').strip("'"))
    return cfg


def token(cfg: dict) -> str:
    key = pathlib.Path(cfg["ASC_KEY_PATH"]).expanduser().read_text()
    now = int(time.time())
    return jwt.encode(
        {"iss": cfg["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": cfg["ASC_KEY_ID"], "typ": "JWT"})


class ASC:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token(cfg)}"

    def _url(self, path: str) -> str:
        return f"{HOST}{path}" if path.startswith("/v2/") else f"{API}{path}"

    def get(self, path: str, **params):
        r = self.s.get(self._url(path), params=params, timeout=30)
        r.raise_for_status()
        return r.json()

    def _send(self, method: str, path: str, payload: dict | None):
        r = self.s.request(method, self._url(path), json=payload, timeout=60)
        if r.status_code >= 400:
            raise RuntimeError(f"{method} {path} → {r.status_code} {r.text[:1500]}")
        return r.json() if r.text else {}

    def post(self, path: str, payload: dict):
        return self._send("POST", path, payload)

    def patch(self, path: str, payload: dict):
        return self._send("PATCH", path, payload)

    def delete(self, path: str):
        return self._send("DELETE", path, None)

    def editable_version(self, app_id: str) -> dict:
        versions = self.get(f"/apps/{app_id}/appStoreVersions", limit=10)["data"]
        editable = [v for v in versions if v["attributes"]["appStoreState"] in EDITABLE_STATES]
        if not editable:
            raise SystemExit("no editable App Store version — every version is submitted or live")
        return editable[0]

    def builds(self, app_id: str) -> list[dict]:
        """Every build, newest first — via preReleaseVersions so a build still
        PROCESSING is visible (/builds?filter[app] hides those)."""
        out: list[dict] = []
        for prv in self.get("/preReleaseVersions", **{"filter[app]": app_id, "limit": 50})["data"]:
            out += self.get(f"/preReleaseVersions/{prv['id']}/builds", limit=50)["data"]
        out.sort(key=lambda b: b["attributes"].get("uploadedDate") or "", reverse=True)
        return out


def main() -> None:
    cfg = load_config()
    asc = ASC(cfg)
    app_id = cfg["ASC_APP_ID"]
    app = asc.get(f"/apps/{app_id}")["data"]["attributes"]
    print(f"app {app_id}  {app['name']}  ({app['bundleId']})")
    for v in asc.get(f"/apps/{app_id}/appStoreVersions", limit=10)["data"]:
        a = v["attributes"]
        b = asc.get(f"/appStoreVersions/{v['id']}/build").get("data")
        print(f"  version {a['versionString']}  {a['appStoreState']}  build {b['attributes']['version'] if b else '-'}")
    for b in asc.builds(app_id)[:5]:
        a = b["attributes"]
        print(f"  build {a['version']}  {a['processingState']}  {a.get('uploadedDate')}")


if __name__ == "__main__":
    sys.exit(main())
