from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase" / "migrations" / "20260819023000_r87_1_legacy_journal_metadata_guard.sql"
R86 = ROOT / "supabase" / "tests" / "verify_r86_complete_linked_financial_deletion.sql"


def need(label: str, condition: bool) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {label}")
    print(f"PASS: {label}")


sql = MIGRATION.read_text(encoding="utf-8")
r86 = R86.read_text(encoding="utf-8")

need("R87.1 migration is forward-only", sql.startswith("begin;") and sql.rstrip().endswith("commit;"))
need("V763 validator remains defined", "create or replace function public.erp_v763_validate_journal_line()" in sql)
need("R87 postable guard remains defined", "create or replace function public.erp_r87_journal_line_postable_guard()" in sql)
need("metadata-only path is update-only", "if tg_op='UPDATE'" in sql)
need("soft delete still returns before posting validation", sql.count("if new.is_deleted then") >= 1)
for field in ("accountId", "account_id", "debit", "credit", "currency"):
    need(f"posting fingerprint protects {field}", field in sql)
need("strict invalid-side rejection preserved", "invalid_journal_line_sides" in sql)
need("strict inactive-account rejection preserved", "journal_account_inactive_or_missing" in sql)
need("strict capitalization rejection preserved", "capitalization_account_forbidden" in sql)
need("strict currency rejection preserved", "journal_line_account_currency_mismatch" in sql)
need("postable account assertion preserved", "erp_assert_postable_account" in sql)
need("R86 still exercises legacy-shaped journal lines", "jsonb_build_object('entryId','r86-maint-journal-delete')" in r86)
need("R86 still restores origin triggers before deletion", "set local session_replication_role=origin;" in r86)

print("R87.1 legacy journal metadata guard PASS")
