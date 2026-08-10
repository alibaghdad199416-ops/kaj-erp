#!/usr/bin/env python3
"""Verify that production deployment points only to the intended cloud projects."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SUPABASE_REF = "havlqebmnjdcwmpaaqew"
EXPECTED_SUPABASE_URL = f"https://{EXPECTED_SUPABASE_REF}.supabase.co"
EXPECTED_FIREBASE_PROJECT = "kaj-erp"

errors: list[str] = []

production_candidate = ROOT / "dart_defines.production.json"
active_runtime_path = ROOT / "dart_defines.json"
production_path = production_candidate if production_candidate.is_file() else active_runtime_path
try:
    production_text = production_path.read_text(encoding="utf-8")
    production = json.loads(production_text)
except Exception as error:  # noqa: BLE001
    errors.append(f"invalid production Dart defines ({production_path.name}): {error}")
    production_text = ""
    production = {}

if production.get("SUPABASE_URL") != EXPECTED_SUPABASE_URL:
    errors.append("production SUPABASE_URL does not match the intended project base URL")
key = str(production.get("SUPABASE_PUBLISHABLE_KEY", ""))
if not key.startswith("sb_publishable_"):
    errors.append("production client key must be an sb_publishable_ key")
if any(marker in key for marker in ("sb_secret_", "service_role")):
    errors.append("a secret/service-role key must never be packaged for the web client")

firebaserc = json.loads((ROOT / ".firebaserc").read_text(encoding="utf-8"))
projects = firebaserc.get("projects", {})
if projects.get("default") != EXPECTED_FIREBASE_PROJECT:
    errors.append("Firebase default project is not kaj-erp")
if projects.get("production") != EXPECTED_FIREBASE_PROJECT:
    errors.append("Firebase production alias is not kaj-erp")

firebase = json.loads((ROOT / "firebase.json").read_text(encoding="utf-8"))
if firebase.get("hosting", {}).get("public") != "build/web":
    errors.append("Firebase Hosting must publish build/web")

config = (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
required_config = (
    'site_url = "https://kaj-erp.web.app"',
    'enable_signup = false',
    '[auth.email]',
    'https://kaj-erp.web.app/**',
    'https://kaj-erp.firebaseapp.com/**',
)
for marker in required_config:
    if marker not in config:
        errors.append(f"missing Supabase Auth deployment setting: {marker}")


edge_create = ROOT / "supabase" / "functions" / "admin-create-user" / "index.ts"
edge_manage = ROOT / "supabase" / "functions" / "admin-manage-user" / "index.ts"
user_admin_service = ROOT / "lib" / "core" / "cloud" / "supabase_user_administration_service.dart"
for required_file in (edge_create, edge_manage, user_admin_service):
    if not required_file.is_file():
        errors.append(f"missing internal user-administration component: {required_file.relative_to(ROOT)}")

if edge_create.is_file():
    edge_source = edge_create.read_text(encoding="utf-8")
    for marker in ("auth.admin.createUser", "is_system_admin", "company_memberships"):
        if marker not in edge_source:
            errors.append(f"admin-create-user is missing required security behavior: {marker}")

if edge_manage.is_file():
    manage_source = edge_manage.read_text(encoding="utf-8")
    for marker in (
        "auth.admin.updateUserById",
        "previousMembership",
        "previousProfile",
        "previousRecord",
        "Membership update rollback failed",
        "ERP user update rollback failed",
    ):
        if marker not in manage_source:
            errors.append(
                f"admin-manage-user is missing atomic update compensation: {marker}"
            )
    auth_update = manage_source.find("auth.admin.updateUserById")
    erp_update = manage_source.rfind("from('erp_records').upsert", 0, auth_update)
    if erp_update < 0 or auth_update < erp_update:
        errors.append("admin-manage-user must update reversible ERP rows before Auth")

for function_name in ("admin-create-user", "admin-manage-user"):
    marker = f"[functions.{function_name}]\nverify_jwt = true"
    if marker not in config.replace("\r\n", "\n"):
        errors.append(f"{function_name} must require a verified user JWT")

if user_admin_service.is_file() and "admin-create-user" not in user_admin_service.read_text(encoding="utf-8"):
    errors.append("Flutter user administration is not connected to admin-create-user")

if re.search(r"https://[^\s\"']+\.supabase\.co/rest/v1", production_text):
    errors.append("SUPABASE_URL must be the project base URL without /rest/v1")

if errors:
    print("FAILED production deployment target verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS production deployment target verification")
print(f"  - runtime config: {production_path.name}")
print(f"  - Supabase project: {EXPECTED_SUPABASE_REF}")
print(f"  - Firebase project: {EXPECTED_FIREBASE_PROJECT}")
print("  - public self-signup is disabled; ERP administrators create users inside the app")
print("  - only a publishable browser key is packaged")
