from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

MIGRATIONS = {
    "20260826030000_r50_integrity_repair.sql": (
        "erp_document_processing_jobs",
        "erp_r49_cloud_global_search",
        "erp_validate",
    ),
    "20260826050000_r51_runtime_schema_and_accounting_closure.sql": (
        "erp_r9_list_cloud_master_records",
        "erp_r15_reconcile_company_state",
        "erp_r16_current_state_health",
        "erp_phase2_post_scrap",
        "notify pgrst,'reload schema'",
    ),
    "20260826003000_r52_full_integrity_closure.sql": (
        "R52 consolidated integrity closure",
        "erp_document_processing_jobs",
        "alter function",
    ),
    "20260826033000_r53_security_permission_closure.sql": (
        "R53 security closure",
        "tenant_access",
        "erp_user_belongs_to_company",
    ),
    "20260826060000_r54_document_storage_security_closure.sql": (
        "R54: document storage closure",
        "enterprise-documents",
        "storage.objects",
    ),
    "20260826061000_r55_document_storage_permission_alignment.sql": (
        "R55 corrects the R54 storage boundary",
        "erp_r54_document_storage_company_id",
        "storage.objects",
    ),
}

errors: list[str] = []
for name, markers in MIGRATIONS.items():
    path = ROOT / "supabase" / "migrations" / name
    if not path.is_file():
        errors.append(f"missing migration: {name}")
        continue
    text = path.read_text(encoding="utf-8", errors="strict")
    for marker in markers:
        if marker not in text:
            errors.append(f"{name}: missing marker {marker!r}")

if errors:
    print("FAIL R50-R55 full integrity closure")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("PASS R50-R55 full integrity closure")
print("- R50 integrity repair present")
print("- R51 runtime/schema/accounting closure present")
print("- R52 consolidated integrity closure present")
print("- R53 security/permission closure present")
print("- R54 private document storage boundary present")
print("- R55 document storage permission alignment present")
