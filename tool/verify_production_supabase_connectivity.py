#!/usr/bin/env python3
"""Verify the configured hosted Supabase Auth and PostgREST endpoints are reachable."""
from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "dart_defines.production.json"
EXPECTED_URL = "https://havlqebmnjdcwmpaaqew.supabase.co"

runtime = json.loads(CONFIG.read_text(encoding="utf-8"))
base_url = str(runtime.get("SUPABASE_URL") or "").rstrip("/")
key = str(runtime.get("SUPABASE_PUBLISHABLE_KEY") or "")

if base_url != EXPECTED_URL:
    raise SystemExit(f"FAIL production URL mismatch: {base_url!r}")
if not key.startswith("sb_publishable_"):
    raise SystemExit("FAIL production publishable key is missing")
if "service_role" in key.lower() or key.lower().startswith("sb_secret_"):
    raise SystemExit("FAIL secret/service-role key must not be used by the browser runtime")

headers = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "User-Agent": "kaj-erp-production-connectivity-check/1",
}
context = ssl.create_default_context()


def check(label: str, path: str) -> None:
    request = urllib.request.Request(
        f"{base_url}{path}",
        headers=headers,
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=20, context=context) as response:
            status = int(response.status)
            response.read(1024)
    except urllib.error.HTTPError as error:
        status = int(error.code)
        detail = error.read(512).decode("utf-8", errors="replace")
        raise SystemExit(f"FAIL {label}: HTTP {status}: {detail}") from error
    except Exception as error:  # noqa: BLE001
        raise SystemExit(f"FAIL {label}: {error}") from error
    if status < 200 or status >= 300:
        raise SystemExit(f"FAIL {label}: HTTP {status}")
    print(f"PASS {label}: HTTP {status}")


check("Supabase Auth settings", "/auth/v1/settings")
check("Supabase PostgREST", "/rest/v1/")
print("PASS production Supabase connectivity")
print(f"  - project: {EXPECTED_URL}")
print("  - publishable key accepted by Auth and PostgREST")
print("  - no user password was read or transmitted by this verifier")
