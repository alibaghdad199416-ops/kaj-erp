from pathlib import Path
root=Path(__file__).resolve().parents[1]
m=(root/'supabase/migrations/20260806143000_v750_rpc_runtime_recovery.sql').read_text(encoding='utf-8')
checks=['erp_transfer_cloud_cash_v2','erp_manage_commercial_order_component_v2','erp_delete_cloud_sales_order_v4','erp_v750_approve_workflow_invoice_resilient',"notify pgrst,'reload schema'"]
for x in checks:
 assert x in m,x
cash_repo=(root/'lib/features/accounting/cashbox/repositories/cashbox_repository.dart').read_text(encoding='utf-8')
r9_finance=(root/'supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql').read_text(encoding='utf-8')
assert any(x in cash_repo for x in ["erp_transfer_cloud_cash_v2","erp_transfer_cloud_cash_v3","erp_v2300_transfer_cloud_cash","erp_r9_transfer_cloud_cash","erp_r22_transfer_cloud_cash"])
if "erp_r9_transfer_cloud_cash" in cash_repo:
 assert "erp_v2300_transfer_cloud_cash" in r9_finance and "p_transfer_date" in r9_finance
if "erp_r22_transfer_cloud_cash" in cash_repo:
 r22=(root/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql').read_text(encoding='utf-8')
 assert "create or replace function public.erp_r22_transfer_cloud_cash" in r22
 assert "cashTransactionId" in r22 and "cashAccountId" in r22 and "erp_v762_assert_posted_journal_balanced" in r22
 assert "create or replace function public.erp_r9_transfer_cloud_cash" in r22
assert any(x in (root/'lib/features/sales/workflow/repositories/sales_workflow_repository.dart').read_text(encoding='utf-8') for x in ["erp_manage_commercial_order_component_v2","erp_manage_commercial_order_component_v3"])
print('PASS V7.5.0 RPC runtime recovery')
