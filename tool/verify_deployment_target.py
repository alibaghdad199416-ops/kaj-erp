#!/usr/bin/env python3
"""Verify separated Local Supabase development and hosted production targets."""
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


active_runtime_path = ROOT / "dart_defines.json"
production_path = ROOT / "dart_defines.production.json"

active_text, active_runtime = read_json(active_runtime_path, "local test runtime")
if active_runtime.get("SUPABASE_URL") != EXPECTED_LOCAL_URL:
    errors.append("dart_defines.json must remain the Local Supabase test baseline")
active_key = public_key(active_runtime)
reject_secret(active_key, "local test runtime")
if re.search(r"https://[^\s\"']+\.supabase\.co", active_text, re.I):
    errors.append("dart_defines.json must not become the hosted production runtime")

production_text, production_runtime = read_json(production_path, "production runtime")
if production_runtime.get("SUPABASE_URL") != EXPECTED_SUPABASE_URL:
    errors.append("production SUPABASE_URL must match the intended project base URL")
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
    "expectedProductionUrl",
    "SUPABASE_ALLOW_LOCAL_DEV",
    "isHostedProductionTarget",
    "_isLoopback(host)",
    "sb_secret_",
    "/rest/v1",
):
    if required not in config_source:
        errors.append(f"SupabaseConfig is missing runtime contract: {required}")

firebaserc = json.loads((ROOT / ".firebaserc").read_text(encoding="utf-8"))
projects = firebaserc.get("projects", {})
if projects.get("default") != EXPECTED_FIREBASE_PROJECT:
    errors.append("Firebase default project is not kaj-erp")
if projects.get("production") != EXPECTED_FIREBASE_PROJECT:
    errors.append("Firebase production alias is not kaj-erp")

firebase = json.loads((ROOT / "firebase.json").read_text(encoding="utf-8"))
hosting = firebase.get("hosting", {})
if hosting.get("public") != "build/web":
    errors.append("Firebase Hosting must publish build/web")
firebase_text = (ROOT / "firebase.json").read_text(encoding="utf-8")
if "https://*.supabase.co" not in firebase_text or "wss://*.supabase.co" not in firebase_text:
    errors.append("Firebase CSP must allow Supabase HTTPS and Realtime connections")

config = (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
for marker in (
    f'project_id = "{EXPECTED_LOCAL_PROJECT_ID}"',
    'site_url = "https://kaj-erp.web.app"',
    "enable_signup = false",
    "[auth.email]",
    "https://kaj-erp.web.app/**",
    "https://kaj-erp.firebaseapp.com/**",
):
    if marker not in config:
        errors.append(f"missing Supabase deployment/local-development setting: {marker}")

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
            errors.append(
                f"admin-manage-user is missing atomic update compensation: {marker}"
            )
    auth_update = manage_source.find("auth.admin.updateUserById")
    erp_update = manage_source.rfind("from('erp_records').upsert", 0, auth_update)
    if erp_update < 0 or auth_update < erp_update:
        errors.append("admin-manage-user must update reversible ERP rows before Auth")
    if ".limit(1)" in manage_source:
        errors.append("admin-manage-user must not select an arbitrary caller tenant")
    if manage_source.count(".eq('company_id', requestedCompanyId)") < 5:
        errors.append(
            "admin-manage-user must scope caller, target, mutations, and rollback to the requested tenant"
        )

for function_name in ("admin-create-user", "admin-manage-user"):
    marker = f"[functions.{function_name}]\nverify_jwt = true"
    if marker not in config.replace("\r\n", "\n"):
        errors.append(f"{function_name} must require a verified user JWT")

if user_admin_service.is_file():
    user_admin_source = user_admin_service.read_text(encoding="utf-8")
    if "admin-create-user" not in user_admin_source:
        errors.append("Flutter user administration is not connected to admin-create-user")
    for marker in (
        "CloudTenantContext.instance",
        "'company_id': companyId",
        "isBootstrapReady",
    ):
        if marker not in user_admin_source:
            errors.append(f"Flutter user administration is missing tenant contract: {marker}")

# R87 regression contracts prove the effective forward migrations keep delegated
# authority and record scopes wired to live read models in either environment.
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
        "erp_r56_vehicle_service_card",
        "erp_r56_business_partner_360",
        "erp_r49_business_partner_card_summary",
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
    for forbidden in ("voucherNumberExists(", "_repository.searchTransactions("):
        if forbidden in cashbox:
            errors.append(f"cashbox duplicate full-read regression returned: {forbidden}")

if errors:
    print("FAILED separated deployment target verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS separated deployment target verification")
print(f"  - Local test API: {EXPECTED_LOCAL_URL}")
print(f"  - production Supabase: {EXPECTED_SUPABASE_URL}")
print(f"  - Firebase project: {EXPECTED_FIREBASE_PROJECT}")
print("  - browser runtimes contain public keys only")
print("  - Local Supabase remains a separate development/test path")
print("  - production Auth and Realtime are permitted by Firebase CSP")
print("  - ERP administrator functions remain tenant- and JWT-scoped")
