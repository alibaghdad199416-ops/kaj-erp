from pathlib import Path
root=Path(__file__).resolve().parents[1]
m=(root/'supabase/migrations/20260806193000_v755_fx_transfer_unique_vouchers_auth_preferences.sql').read_text(encoding='utf-8')
r=(root/'lib/features/accounting/cashbox/repositories/cashbox_repository.dart').read_text(encoding='utf-8')
pref=(root/'lib/core/preferences/user_interface_preferences_repository.dart').read_text(encoding='utf-8')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
r9=(root/'supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql').read_text(encoding='utf-8')
r22=(root/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql').read_text(encoding='utf-8')
assert 'erp_transfer_cloud_cash_v5' in m and (('erp_transfer_cloud_cash_v5' in r) or ('erp_v2300_transfer_cloud_cash' in r) or ('erp_r9_transfer_cloud_cash' in r and 'erp_v2300_transfer_cloud_cash' in r9 and 'erp_transfer_cloud_cash_v5(' in (root/'supabase/migrations/20260807180000_v2300_atomic_workflow_enterprise_audit.sql').read_text(encoding='utf-8')) or ('erp_r22_transfer_cloud_cash' in r and "'cash_transfer_source'" in r22 and "'cash_transfer_target'" in r22 and 'cashTransactionId' in r22))
assert "'voucherNumber',out_voucher" in m and "'voucherNumber',in_voucher" in m
assert "'cash_transfer_source'" in m and "'cash_transfer_target'" in m
assert "erp_next_document_number(p_company_id,'journal_entry','JE'" in m
assert '_hasUsableSession' in pref and 'refreshSession' in pref
assert "error.code == '401'" in pref and "error.code == 'PGRST301'" in pref
assert ('version: 18.9.' in pub) or ('version: 22.9.8+229008' in pub)
print('PASS V7.5.5 FX transfer unique vouchers/references and authenticated UI preferences')
