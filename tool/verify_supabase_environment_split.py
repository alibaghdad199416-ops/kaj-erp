#!/usr/bin/env python3
"""Fail closed if KAJ ERP Local/Production Supabase wiring can cross environments."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FINAL_REF = "havlqebmnjdcwmpaaqew"
FINAL_URL = f"https://{FINAL_REF}.supabase.co"
LOCAL_URL = "http://127.0.0.1:54321"
LOCAL_ID = "quality_line_erp_local_dev"
OLD_REFS = {"fjiaxdorunedmltgqtty", "txeuuacukonedgxwcrip"}
errors: list[str] = []


def text(path: str) -> str:
    p = ROOT / path
    if not p.is_file():
        errors.append(f"missing required file: {path}")
        return ""
    return p.read_text(encoding="utf-8")


def json_file(path: str) -> dict:
    raw = text(path)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        errors.append(f"invalid JSON {path}: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"JSON root must be object: {path}")
        return {}
    return value


local = json_file("dart_defines.json")
production = json_file("dart_defines.production.json")

if local.get("KAJ_BACKEND_TARGET") != "local":
    errors.append("local defines must declare KAJ_BACKEND_TARGET=local")
if local.get("SUPABASE_URL") != LOCAL_URL:
    errors.append("local defines must use loopback Supabase only")
if local.get("SUPABASE_ALLOW_LOCAL_DEV") is not True:
    errors.append("local defines must explicitly enable local development")
if local.get("SUPABASE_LOCAL_PROJECT_ID") != LOCAL_ID:
    errors.append("local defines project id is incorrect")

if production.get("KAJ_BACKEND_TARGET") != "production":
    errors.append("production defines must declare KAJ_BACKEND_TARGET=production")
if production.get("SUPABASE_URL") != FINAL_URL:
    errors.append("production defines must target the final Supabase project only")
if production.get("SUPABASE_ALLOW_LOCAL_DEV") is not False:
    errors.append("production defines must explicitly disable local development")
if not str(production.get("SUPABASE_PUBLISHABLE_KEY", "")).startswith("sb_publishable_"):
    errors.append("production browser key must be a publishable key")

local_config = text("supabase/config.toml")
if f'project_id = "{LOCAL_ID}"' not in local_config:
    errors.append("supabase/config.toml is not the local project")
if re.search(r"https://[^\s\"']+\.supabase\.co", local_config, re.I):
    errors.append("local Supabase config contains a Hosted Supabase URL")
if "kaj-erp.web.app" in local_config or "kaj-erp.firebaseapp.com" in local_config:
    errors.append("local Auth config contains production Firebase redirects")
if 'site_url = "http://127.0.0.1:5000"' not in local_config:
    errors.append("local Auth site_url must remain loopback")

prod_config = text("deployment/production/supabase/config.toml")
for marker in (
    f'project_id = "{FINAL_REF}"',
    'site_url = "https://kaj-erp.web.app"',
    "https://kaj-erp.firebaseapp.com/**",
    "[auth.third_party.firebase]\nenabled = false",
):
    if marker not in prod_config.replace("\r\n", "\n"):
        errors.append(f"production Supabase config missing: {marker}")
if re.search(r"localhost|127\.0\.0\.1|\[::1\]", prod_config, re.I):
    errors.append("production Supabase config contains a local redirect/host")

runtime = text("lib/core/cloud/supabase_config.dart")
for marker in (
    "KAJ_BACKEND_TARGET",
    "defaultValue: ''",
    "validateRuntimeContract",
    FINAL_REF,
):
    if marker not in runtime:
        errors.append(f"runtime fail-closed contract missing: {marker}")

bootstrap = text("tool/bootstrap_local_supabase.ps1")
for marker in (LOCAL_URL, LOCAL_ID, "Assert-LocalOnlyUrl", "supabase start"):
    if marker not in bootstrap:
        errors.append(f"local bootstrap safeguard missing: {marker}")
if re.search(r"https://[^\s\"']+\.supabase\.co", bootstrap, re.I):
    errors.append("local bootstrap contains a Hosted Supabase URL")

guard = text("tool/guarded_supabase_db_push.py")
for marker in (FINAL_REF, "assert_expected_linked_project", "Refusing linked database operation"):
    if marker not in guard:
        errors.append(f"linked DB push guard missing: {marker}")

deploy = text("tool/deploy_production.ps1")
for marker in (
    FINAL_REF,
    "dart_defines.production.json",
    "deployment\\production",
    "build_production_web.ps1",
    "guarded_supabase_db_push.py --linked",
):
    if marker not in deploy:
        errors.append(f"production deploy contract missing: {marker}")
if "npm run check:release" in deploy:
    errors.append("production deploy must not use local build:web through check:release")

r49_validate = text("tool/validate_r49_workspace.ps1")
if "build_production_web.ps1" not in r49_validate:
    errors.append("R49 production validation must produce a production-defined web build")
if "npm run build:web" in r49_validate:
    errors.append("R49 production validation still builds the local runtime artifact")

r49_deploy = text("tool/deploy_r49_production.ps1")
if f"$SupabaseProject = '{FINAL_REF}'" not in r49_deploy:
    errors.append("R49 deploy final project ref is incorrect")
if "supabase link --project-ref $SupabaseProject --yes" not in r49_deploy:
    errors.append("R49 deploy must explicitly link the final Supabase project")

# Old refs may remain in historical migrations/verifiers/reports, but never in
# active runtime/deployment configuration files.
active_paths = (
    "dart_defines.json",
    "dart_defines.production.json",
    ".env.example",
    "supabase/config.toml",
    "deployment/production/supabase/config.toml",
    "lib/core/cloud/supabase_config.dart",
    "tool/bootstrap_local_supabase.ps1",
    "tool/build_production_web.ps1",
    "tool/deploy_production.ps1",
    "tool/deploy_r49_production.ps1",
)
for path in active_paths:
    source = text(path)
    for old_ref in OLD_REFS:
        if old_ref in source:
            errors.append(f"old Supabase ref {old_ref} remains in active file {path}")

firebase = json_file("firebase.json")
if set(firebase) != {"hosting"}:
    errors.append("Firebase must remain Hosting-only")
pubspec = text("pubspec.yaml")
for dependency in (
    "firebase_core:",
    "firebase_auth:",
    "cloud_firestore:",
    "firebase_database:",
    "firebase_storage:",
):
    if dependency in pubspec:
        errors.append(f"forbidden Firebase runtime dependency: {dependency}")

if errors:
    print("FAILED strict Local/Production Supabase environment split")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS strict Local/Production Supabase environment split")
print(f"  LOCAL      -> {LOCAL_URL}")
print(f"  PRODUCTION -> {FINAL_URL}")
print("  Firebase   -> Hosting only (kaj-erp)")
print("  Linked DB pushes -> final production ref only")
