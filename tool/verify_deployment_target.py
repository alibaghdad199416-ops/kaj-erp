#!/usr/bin/env python3
"""Verify strict Local Supabase / production Supabase separation for KAJ ERP."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_SUPABASE_REF = "havlqebmnjdcwmpaaqew"
EXPECTED_SUPABASE_URL = f"https://{EXPECTED_SUPABASE_REF}.supabase.co"
EXPECTED_LOCAL_URL = "http://127.0.0.1:54321"
EXPECTED_LOCAL_PROJECT_ID = "quality_line_erp_local_dev"
EXPECTED_FIREBASE_PROJECT = "kaj-erp"
errors: list[str] = []


def read_json(path: Path, label: str) -> tuple[str, dict]:
    try:
        text = path.read_text(encoding="utf-8")
        value = json.loads(text)
        if not isinstance(value, dict):
            raise TypeError("root must be a JSON object")
        return text, value
    except Exception as error:  # noqa: BLE001
        errors.append(f"invalid {label} ({path.name}): {error}")
        return "", {}


def public_key(runtime: dict) -> str:
    return str(
        runtime.get("SUPABASE_PUBLISHABLE_KEY")
        or runtime.get("SUPABASE_ANON_KEY")
        or ""
    )


def reject_secret(key: str, label: str) -> None:
    if not key:
        errors.append(f"{label} public Supabase key is missing")
        return
    if any(marker in key.lower() for marker in ("sb_secret_", "service_role")):
        errors.append(f"{label} must never package a secret/service-role Supabase key")


local_path = ROOT / "dart_defines.json"
production_path = ROOT / "dart_defines.production.json"
local_text, local_runtime = read_json(local_path, "local runtime")
production_text, production_runtime = read_json(production_path, "production runtime")

local_allowed = {"SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEY"}
local_extra = set(local_runtime) - local_allowed
if local_extra:
    errors.append(f"local browser config has unexpected keys: {sorted(local_extra)}")
if local_runtime.get("SUPABASE_URL") != EXPECTED_LOCAL_URL:
    errors.append("dart_defines.json must target Local Supabase loopback only")
reject_secret(public_key(local_runtime), "local runtime")
if re.search(r"https://[^\s\"']+\.supabase\.co", local_text, re.I):
    errors.append("local runtime must not contain any Hosted Supabase URL")

if production_runtime.get("KAJ_BACKEND_TARGET") != "production":
    errors.append("production runtime must explicitly declare KAJ_BACKEND_TARGET=production")
if production_runtime.get("SUPABASE_URL") != EXPECTED_SUPABASE_URL:
    errors.append("production SUPABASE_URL must match the intended project base URL")
if production_runtime.get("SUPABASE_ALLOW_LOCAL_DEV") is not False:
    errors.append("production runtime must explicitly disable Local Supabase")
production_key = public_key(production_runtime)
reject_secret(production_key, "production runtime")
if not production_key.startswith("sb_publishable_"):
    errors.append("production client key must be an sb_publishable_ key")
if re.search(r"https://[^\s\"']+\.supabase\.co/rest/v1", production_text, re.I):
    errors.append("production SUPABASE_URL must be the project base URL without /rest/v1")

config_source = (ROOT / "lib" / "core" / "cloud" / "supabase_config.dart").read_text(
    encoding="utf-8"
)
for required in (
    EXPECTED_SUPABASE_REF,
    "KAJ_BACKEND_TARGET",
    "resolveBackendTarget",
    "return _isLoopback(host) ? 'local' : '';",
    "validateRuntimeContract",
    "defaultValue: ''",
    "SUPABASE_ALLOW_LOCAL_DEV",
    "isHostedProductionTarget",
    "_isLoopback(host)",
    "sb_secret_",
    "/rest/v1",
):
    if required not in config_source:
        errors.append(f"SupabaseConfig is missing runtime contract: {required}")
if "_defaultProjectUrl = expectedProductionUrl" in config_source:
    errors.append("SupabaseConfig must not silently default to production")
if "return _isLoopback(host) ? 'local' : 'production';" in config_source:
    errors.append("SupabaseConfig must never infer production from a hosted URL")

config = (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
for marker in (
    f'project_id = "{EXPECTED_LOCAL_PROJECT_ID}"',
    'site_url = "http://127.0.0.1:5000"',
    'additional_redirect_urls = ["http://127.0.0.1:**", "http://localhost:**"]',
    "enable_signup = false",
    "[auth.email]",
    "[realtime]",
    "[storage]",
    "[auth.third_party.firebase]\nenabled = false",
):
    if marker not in config.replace("\r\n", "\n"):
        errors.append(f"missing Local Supabase setting: {marker}")
if re.search(r"https://[^\s\"']+\.supabase\.co", config, re.I):
    errors.append("supabase/config.toml must not contain any Hosted Supabase project URL")
if "kaj-erp.web.app" in config or "kaj-erp.firebaseapp.com" in config:
    errors.append("local Supabase Auth redirects must not point at production Firebase Hosting")

for function_name in (
    "admin-create-user",
    "admin-manage-user",
    "admin-update-user-media",
):
    marker = f"[functions.{function_name}]\nverify_jwt = true"
    if marker not in config.replace("\r\n", "\n"):
        errors.append(f"{function_name} must require a verified user JWT")

bootstrap = ROOT / "tool" / "bootstrap_local_supabase.ps1"
if not bootstrap.is_file():
    errors.append("missing Local Supabase/Auth bootstrap script")
else:
    bootstrap_source = bootstrap.read_text(encoding="utf-8")
    for marker in (
        EXPECTED_LOCAL_URL,
        EXPECTED_LOCAL_PROJECT_ID,
        "/auth/v1/admin/users",
        "company_memberships",
        "Assert-LocalOnlyUrl",
        "Refusing to bootstrap Auth against non-local Supabase URL",
    ):
        if marker not in bootstrap_source:
            errors.append(f"local bootstrap is missing safety behavior: {marker}")
    if (
        "supabase start" not in bootstrap_source
        and 'Invoke-LocalSupabase -Arguments @("start")' not in bootstrap_source
    ):
        errors.append("local bootstrap is missing safety behavior: local Supabase start")
    if (
        "supabase status -o env" not in bootstrap_source
        and 'Invoke-LocalSupabase -Arguments @("status", "-o", "env")' not in bootstrap_source
    ):
        errors.append("local bootstrap is missing safety behavior: local Supabase status env")
    if re.search(r"https://[^\s\"']+\.supabase\.co", bootstrap_source, re.I):
        errors.append("local bootstrap must never contain a Hosted Supabase URL")

firebaserc = json.loads((ROOT / ".firebaserc").read_text(encoding="utf-8"))
projects = firebaserc.get("projects", {})
if projects.get("default") != EXPECTED_FIREBASE_PROJECT:
    errors.append("Firebase default project is not kaj-erp")
if projects.get("production") != EXPECTED_FIREBASE_PROJECT:
    errors.append("Firebase production alias is not kaj-erp")

firebase_text = (ROOT / "firebase.json").read_text(encoding="utf-8")
firebase = json.loads(firebase_text)
if set(firebase) != {"hosting"}:
    errors.append("firebase.json must configure Hosting only")
hosting = firebase.get("hosting", {})
if hosting.get("public") != "build/web":
    errors.append("Firebase Hosting must publish build/web")
if "https://*.supabase.co" not in firebase_text or "wss://*.supabase.co" not in firebase_text:
    errors.append("Firebase CSP must allow Supabase HTTPS and Realtime connections")

pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
for forbidden in (
    "firebase_auth:",
    "cloud_firestore:",
    "firebase_database:",
    "firebase_storage:",
    "firebase_core:",
):
    if forbidden in pubspec:
        errors.append(f"Firebase runtime dependency is forbidden: {forbidden}")

edge_create = ROOT / "supabase" / "functions" / "admin-create-user" / "index.ts"
edge_manage = ROOT / "supabase" / "functions" / "admin-manage-user" / "index.ts"
user_admin_service = ROOT / "lib" / "core" / "cloud" / "supabase_user_administration_service.dart"
for required_file in (edge_create, edge_manage, user_admin_service):
    if not required_file.is_file():
        errors.append(
            f"missing internal user-administration component: {required_file.relative_to(ROOT)}"
        )

if edge_create.is_file():
    edge_source = edge_create.read_text(encoding="utf-8")
    for marker in (
        "auth.admin.createUser",
        "is_system_admin",
        "company_memberships",
        "company_context_required",
        ".eq('company_id', requestedCompanyId)",
    ):
        if marker not in edge_source:
            errors.append(f"admin-create-user is missing required security behavior: {marker}")
    if ".limit(1)" in edge_source:
        errors.append("admin-create-user must not select an arbitrary caller tenant")

if edge_manage.is_file():
    manage_source = edge_manage.read_text(encoding="utf-8")
    for marker in (
        "auth.admin.updateUserById",
        "previousMembership",
        "previousProfile",
        "previousRecord",
        "Membership update rollback failed",
        "ERP user update rollback failed",
        "company_context_required",
        ".eq('company_id', requestedCompanyId)",
    ):
        if marker not in manage_source:
            errors.append(f"admin-manage-user is missing atomic update behavior: {marker}")
    if ".limit(1)" in manage_source:
        errors.append("admin-manage-user must not select an arbitrary caller tenant")

if user_admin_service.is_file():
    user_admin_source = user_admin_service.read_text(encoding="utf-8")
    for marker in (
        "admin-create-user",
        "CloudTenantContext.instance",
        "'company_id': companyId",
        "isBootstrapReady",
    ):
        if marker not in user_admin_source:
            errors.append(f"Flutter user administration is missing tenant contract: {marker}")

# Preserve the latest R87 regression closures while changing deployment wiring.
authority_path = ROOT / "supabase" / "migrations" / "20260816235500_r87_final_authority_local_runtime_closure.sql"
inventory_path = ROOT / "supabase" / "migrations" / "20260816235600_r87_inventory_car_scope_closure.sql"
cashbox_path = ROOT / "lib" / "features" / "accounting" / "cashbox" / "controllers" / "cashbox_controller.dart"
for required_file in (authority_path, inventory_path, cashbox_path):
    if not required_file.is_file():
        errors.append(f"missing R87 closure component: {required_file.relative_to(ROOT)}")

if authority_path.is_file():
    authority = authority_path.read_text(encoding="utf-8")
    for marker in (
        "permission_grant_exceeds_authority",
        "permission_unknown:",
        "erp_r84_record_visible(p_company_id,'customer_service'",
        "erp_r84_record_visible(p_company_id,'maintenance'",
        "erp_r84_record_visible(p_company_id,'sales'",
        "erp_r84_record_visible(p_company_id,'purchases'",
        "erp_r84_record_visible(p_company_id,'cashbox'",
        "erp_r84_record_visible(p_company_id,'warehouses'",
    ):
        if marker not in authority:
            errors.append(f"R87 authority closure is missing: {marker}")

if inventory_path.is_file():
    inventory = inventory_path.read_text(encoding="utf-8")
    for marker in (
        "erp_r49_list_inventory_warehouse_transfers",
        "erp_r84_record_visible(p_company_id,'inventory',t.created_by,null)",
        "erp_r49_list_cloud_cars_with_warehouse",
        "erp_r84_record_visible(p_company_id,'cars',c.created_by,null)",
    ):
        if marker not in inventory:
            errors.append(f"R87 inventory closure is missing: {marker}")

if cashbox_path.is_file():
    cashbox = cashbox_path.read_text(encoding="utf-8")
    for marker in ("_refreshRequested", "_runRefreshLoop", "_allTransactions"):
        if marker not in cashbox:
            errors.append(f"cashbox refresh regression is missing: {marker}")

if errors:
    print("FAILED separated deployment target verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS strict Supabase runtime separation")
print(f"  - Local development: {EXPECTED_LOCAL_URL} only (loopback-only inference)")
print(f"  - Production: {EXPECTED_SUPABASE_URL} only (explicit target required)")
print(f"  - Firebase Hosting only: {EXPECTED_FIREBASE_PROJECT}")
print("  - Hosted targets never receive an implicit runtime target")
print("  - Local Auth bootstrap is loopback guarded")
