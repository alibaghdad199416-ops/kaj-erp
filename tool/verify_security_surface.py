#!/usr/bin/env python3
"""Static security-surface gates for browser Dart and current SQL closure."""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
R53 = ROOT / "supabase" / "migrations" / "20260826033000_r53_security_permission_closure.sql"
errors: list[str] = []

# Never allow the obsolete browser login pattern back into the application.
for path in LIB.rglob("*.dart"):
    source = path.read_text(encoding="utf-8", errors="ignore")
    lowered = source.lower()
    if "admin@kaj.com" in lowered or "texteditingcontroller(text: '123456'" in lowered:
        errors.append(f"hardcoded legacy credential found in {path.relative_to(ROOT)}")

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

    # The two generic master readers are the high-risk dynamic SQL surfaces.
    # Verify the guards in the current effective replacement migration rather
    # than rejecting historical migrations that are intentionally superseded.
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

if errors:
    print("FAILED security surface verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS security surface verification")
print("  - no obsolete hardcoded browser credentials")
print("  - R53 tenant/permission/master-contract guards present")
print("  - generic SECURITY DEFINER master readers are fail-closed")
