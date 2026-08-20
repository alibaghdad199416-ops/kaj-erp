from pathlib import Path
root=Path(__file__).resolve().parents[1]
m=(root/"supabase/migrations/20260806183000_v754_fx_cashbox_409_conflict_repair.sql").read_text(encoding="utf-8")
r=(root/"lib/features/accounting/cashbox/repositories/cashbox_repository.dart").read_text(encoding="utf-8")
p=(root/"pubspec.yaml").read_text(encoding="utf-8")
r9=(root/"supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql").read_text(encoding="utf-8")
r22=(root/"supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql").read_text(encoding="utf-8")
r90=(root/"supabase/migrations/20260820113000_r90_phase11_final_acceptance_closure.sql").read_text(encoding="utf-8")
assert "erp_transfer_cloud_cash_v4" in m and "erp_ensure_fx_clearing_account" in m
assert "lower(code)=lower(v_code)" in m
assert "when unique_violation" in m
assert ("erp_r90_transfer_cloud_cash" in r and "create or replace function public.erp_r90_transfer_cloud_cash" in r90 and "erp_r22_transfer_cloud_cash" in r90 and "erp_v762_assert_posted_journal_balanced" in r22 and "cashTransactionId" in r22)
assert any(v in p for v in ["version: 18.9.24+189240","version: 18.9.25+189250","version: 22.9.8+229008"])
print("PASS V7.5.4 FX cashbox HTTP 409 conflict repair")
