#!/usr/bin/env python3
"""Static security-surface gates for browser Dart and SECURITY DEFINER SQL."""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
MIGRATIONS = ROOT / "supabase" / "migrations"
errors: list[str] = []

# Never allow the obsolete browser login pattern back into the application.
for path in LIB.rglob("*.dart"):
    source = path.read_text(encoding="utf-8", errors="ignore")
    lowered = source.lower()
    if "admin@kaj.com" in lowered or "texteditingcontroller(text: '123456'" in lowered:
        errors.append(f"hardcoded legacy credential found in {path.relative_to(ROOT)}")

r53 = MIGRATIONS / "20260826033000_r53_security_permission_closure.sql"
if not r53.is_file():
    errors.append("missing R53 security permission closure migration")
else:
    source = r53.read_text(encoding="utf-8")
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

# Catch newly introduced SECURITY DEFINER master readers that bypass the
# canonical permission boundary in the same migration file. This is deliberately
# narrow: it protects the known high-risk generic readers without rejecting
# legitimate internal SECURITY DEFINER routines elsewhere in the ERP.
for path in sorted(MIGRATIONS.glob("*.sql")):
    source = path.read_text(encoding="utf-8", errors="ignore")
    for function_name in ("erp_r9_get_cloud_master_record", "erp_r9_list_cloud_master_records"):
        pattern = rf"create\s+or\s+replace\s+function\s+public\.{function_name}.*?security\s+definer.*?\$\$(.*?)\$\$;"
        for match in re.finditer(pattern, source, flags=re.I | re.S):
            body = match.group(1)
            if "is_active_company_member(p_company_id)" not in body:
                errors.append(f"{path.relative_to(ROOT)}: {function_name} lacks company membership guard")
            if "erp_r9_master_required_permission" not in body:
                errors.append(f"{path.relative_to(ROOT)}: {function_name} lacks master permission guard")
            if "erp_r9_master_resource_for_table" not in body:
                errors.append(f"{path.relative_to(ROOT)}: {function_name} lacks master resource allow-list")

if errors:
    print("FAILED security surface verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS security surface verification")
print("  - no obsolete hardcoded browser credentials")
print("  - R53 tenant/permission/master-contract guards present")
print("  - generic SECURITY DEFINER master readers are fail-closed")
