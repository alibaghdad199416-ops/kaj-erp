from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260819023800_r87_2_legacy_journal_integrity_metadata_guard.sql"
R871 = ROOT / "supabase/migrations/20260819023000_r87_1_legacy_journal_metadata_guard.sql"
R86 = ROOT / "tool/verify_r86_complete_linked_financial_deletion.py"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


text = MIGRATION.read_text(encoding="utf-8")
r871 = R871.read_text(encoding="utf-8")
r86 = R86.read_text(encoding="utf-8")

require(text.lstrip().lower().startswith("begin;"), "R87.2 migration is forward-only")
require("create or replace function public.erp_validate_journal_line_integrity()" in text,
        "legacy integrity validator remains defined")
require("tg_op='UPDATE'" in text, "metadata-only bypass is update-only")
require("coalesce(old.is_deleted,false)=coalesce(new.is_deleted,false)" in text,
        "restore cannot use metadata-only bypass")
for token in ("entryId", "entry_id", "accountId", "account_id", "debit", "credit"):
    require(token in text, f"posting fingerprint protects {token}")
require("بيانات سطر القيد غير مكتملة" in text, "strict required-field rejection preserved")
require("يجب أن يحتوي سطر القيد على مدين أو دائن موجب واحد فقط" in text,
        "strict one-sided amount validation preserved")
require("حساب سطر القيد غير موجود أو غير فعال" in text,
        "strict active-account rejection preserved")
require("erp_v763_validate_journal_line" in r871 and "erp_r87_journal_line_postable_guard" in r871,
        "R87.1 modern guards remain layered")
sql_test = (ROOT / 'supabase/tests/verify_r86_complete_linked_financial_deletion.sql').read_text(encoding='utf-8')
require("erp_delete_cloud_cash_transaction" in sql_test,
        "R86 continues to exercise linked financial deletion and its R68 metadata stamping path")
require("session_replication_role" in r86,
        "R86 continues to exercise legacy-shaped journal evidence")
print("R87.2 legacy journal integrity metadata guard PASS")
