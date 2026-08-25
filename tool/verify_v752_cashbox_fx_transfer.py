from pathlib import Path
root=Path(__file__).resolve().parents[1]
repo=(root/'lib/features/accounting/cashbox/repositories/cashbox_repository.dart').read_text(encoding='utf-8')
sql=(root/'supabase/migrations/20260806173000_v752_cashbox_fx_transfer_runtime.sql').read_text(encoding='utf-8')
v5=(root/'supabase/migrations/20260806193000_v755_fx_transfer_unique_vouchers_auth_preferences.sql').read_text(encoding='utf-8')
v2300=(root/'supabase/migrations/20260807180000_v2300_atomic_workflow_enterprise_audit.sql').read_text(encoding='utf-8')
r9=(root/'supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql').read_text(encoding='utf-8')
r22=(root/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql').read_text(encoding='utf-8')
checks={
 'Flutter calls supported transfer RPC': (("'erp_transfer_cloud_cash_v3'" in repo) or ("'erp_v2300_transfer_cloud_cash'" in repo) or ("'erp_r9_transfer_cloud_cash'" in repo and 'erp_v2300_transfer_cloud_cash' in r9 and 'p_transfer_date' in r9) or ("'erp_r22_transfer_cloud_cash'" in repo and 'create or replace function public.erp_r22_transfer_cloud_cash' in r22 and 'cashTransactionId' in r22 and 'cashAccountId' in r22)),
 'Transfer RPC chain exists': ('erp_transfer_cloud_cash_v3' in sql) and ('erp_transfer_cloud_cash_v5' in v5) and ('erp_v2300_transfer_cloud_cash' in v2300) and ('erp_transfer_cloud_cash_v5(' in v2300),
 'No historical missing helper': 'erp_ensure_workflow_fx_accounts' not in sql,
 'Reciprocal link resolver used': 'erp_resolve_linked_cash_account' in sql,
 'Separate currency clearing accounts': 'system-fx-clearing-' in sql,
 'Balanced source journal': "'totalDebit',p_source_amount,'totalCredit',p_source_amount" in sql,
 'Balanced target journal': "'totalDebit',p_target_amount,'totalCredit',p_target_amount" in sql,
 'PostgREST reload': "notify pgrst,'reload schema'" in sql,
}
missing=[k for k,v in checks.items() if not v]
if missing: raise SystemExit('FAIL V7.5.2: '+', '.join(missing))
print('PASS V7.5.2 linked FX cashbox transfer runtime')
