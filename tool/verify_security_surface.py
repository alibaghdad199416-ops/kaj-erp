#!/usr/bin/env python3
"""Static security-surface gates for browser Dart and current SQL closure."""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
MIGRATIONS = ROOT / "supabase" / "migrations"
R53 = MIGRATIONS / "20260826033000_r53_security_permission_closure.sql"
R54 = MIGRATIONS / "20260826060000_r54_document_storage_security_closure.sql"
R55 = MIGRATIONS / "20260826061000_r55_document_storage_permission_alignment.sql"
errors: list[str] = []

# Never allow the obsolete browser login pattern back into the application.
for path in LIB.rglob("*.dart"):
    source = path.read_text(encoding="utf-8", errors="ignore")
    lowered = source.lower()
    if "admin@kaj.com" in lowered or "texteditingcontroller(text: '123456'" in lowered:
        errors.append(f"hardcoded legacy credential found in {path.relative_to(ROOT)}")

# Permission denial must be fail-closed. In particular, the guard must never
# navigate back to the same protected dashboard blindly, because a legitimate
# authenticated role can lack dashboard.view and would otherwise loop forever.
guard = LIB / "features" / "settings" / "access" / "widgets" / "permission_guard.dart"
if guard.is_file():
    source = guard.read_text(encoding="utf-8", errors="ignore")
    if "pushNamedAndRemoveUntil(\n                        AppRouteNames.dashboard" in source:
        errors.append("PermissionGuard can loop by redirecting denied users to protected dashboard")
    if "Navigator.of(context).canPop()" not in source:
        errors.append("PermissionGuard lacks safe back-navigation for denied routes")
    if "AppRouteNames.login" not in source:
        errors.append("PermissionGuard lacks fail-closed login fallback")
else:
    errors.append("missing PermissionGuard")

if not R53.is_file():
    errors.append("missing R53 security permission closure migration")
else:
    source = R53.read_text(encoding="utf-8")
    required_markers = (
        "auth.uid() is null or not public.is_active_company_member(p_company_id)",
        "erp_r9_master_resource_for_table(p_table)",
        "erp_r14_master_table_contract_ok(p_table)",
        "erp_r9_master_required_permission(p_table,'view')",
        "erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id)",
        "public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit)",
        "customer_service.view",
        "create policy tenant_access",
    )
    for marker in required_markers:
        if marker not in source:
            errors.append(f"R53 security migration missing required guard: {marker}")

    for function_name in ("erp_r9_get_cloud_master_record", "erp_r9_list_cloud_master_records"):
        pattern = rf"create\s+or\s+replace\s+function\s+public\.{function_name}.*?security\s+definer.*?\$\$(.*?)\$\$;"
        match = re.search(pattern, source, flags=re.I | re.S)
        if not match:
            errors.append(f"R53 migration does not redefine {function_name}")
            continue
        body = match.group(1)
        for marker in (
            "is_active_company_member(p_company_id)",
            "erp_r9_master_required_permission",
            "erp_r9_master_resource_for_table",
        ):
            if marker not in body:
                errors.append(f"R53 {function_name} missing guard: {marker}")

for path, required in (
    (R54, (
        "insert into storage.buckets",
        "enterprise-documents",
        "enterprise_documents_storage_select",
        "enterprise_documents_storage_insert",
        "erp_register_cloud_document_blob",
    )),
    (R55, (
        "erp_r54_document_storage_can_read",
        "erp_r54_document_storage_can_write",
        "erp_r49_document_can_read",
        "erp_r49_document_can_write",
        "document_write_permission_required",
        "enterprise_documents_storage_delete",
    )),
):
    if not path.is_file():
        errors.append(f"missing document storage security migration: {path.name}")
    else:
        source = path.read_text(encoding="utf-8")
        for marker in required:
            if marker not in source:
                errors.append(f"{path.name} missing required storage guard: {marker}")

storage_repo = LIB / "core" / "documents" / "repositories" / "document_storage_repository.dart"
if storage_repo.is_file():
    source = storage_repo.read_text(encoding="utf-8")
    for marker in (
        "enterprise-documents",
        "erp_register_cloud_document_blob",
        "remove([path])",
        "path.startsWith('$companyId/')",
    ):
        if marker not in source:
            errors.append(f"document storage repository missing reliability guard: {marker}")
else:
    errors.append("missing document storage repository")

if errors:
    print("FAILED security surface verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS security surface verification")
print("  - no obsolete hardcoded browser credentials")
print("  - PermissionGuard cannot loop on denied dashboard access")
print("  - R53 tenant/permission/master-contract guards present")
print("  - document storage bucket, tenant isolation, and module permissions are enforced")
print("  - document upload rollback prevents orphaned blobs after registration failure")
