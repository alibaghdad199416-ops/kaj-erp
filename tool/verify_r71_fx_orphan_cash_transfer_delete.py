from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = root / "supabase/migrations/20260815124700_r71_fx_orphan_cash_transfer_delete_repair.sql"
text = migration.read_text(encoding="utf-8")

required = [
    "erp_r71_delete_cash_transfer_core",
    "erp_delete_cloud_cash_transfer",
    "erp_delete_cloud_cash_transaction",
    "cash_transfer_source",
    "cash_transfer_target",
    "r71RecoveredMissingOrDeletedTransferHeader",
    "r71OrphanTransferLegDelete",
    "tr.is_deleted",
    "category",
    "v_journal_reference_id",
    "grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text)",
    "grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)",
    "notify pgrst,'reload schema'",
]
for token in required:
    assert token in text, token

core_start = text.index("create or replace function public.erp_r71_delete_cash_transfer_core")
wrapper_start = text.index(
    "create or replace function public.erp_delete_cloud_cash_transfer", core_start + 1
)
core = text[core_start:wrapper_start]
assert "if not found then return" not in core.lower(), (
    "core must not no-op when the transfer header is absent/deleted"
)
assert "where t.company_id=p_company_id\n    and t.id=p_transfer_id\n  for update" in core
assert "like 'cash_transfer%'" in core
assert "public.erp_v65_soft_delete_journal" in core

transaction_start = text.index(
    "create or replace function public.erp_delete_cloud_cash_transaction"
)
repair_start = text.index("-- One-time repair", transaction_start)
transaction = text[transaction_start:repair_start]
assert "v_category='cash_transfer'" in transaction
assert "v_transfer_id:=coalesce(v_reference_id,v_journal_reference_id)" in transaction
assert "perform public.erp_delete_cloud_cash_transfer" in transaction
assert "Last-resort orphan recovery" in transaction

print("PASS R71 FX/orphan cash-transfer deletion repair")
