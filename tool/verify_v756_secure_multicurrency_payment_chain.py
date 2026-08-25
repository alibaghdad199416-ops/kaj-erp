from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'supabase/migrations/20260806203000_v756_secure_multicurrency_payment_chain.sql').read_text(encoding='utf-8')
need=[
'erp_execute_secure_linked_payment_v1',
"p_module not in ('sales','purchases','maintenance')",
'erp_transfer_cloud_cash_v5(',
"p_module in ('sales','maintenance')",
"'paymentChainVersion','v756'",
'create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch',
'create or replace function public.erp_v737_record_maintenance_payment',
"notify pgrst,'reload schema'",
]
missing=[x for x in need if x not in sql]
if missing: raise SystemExit('FAIL V7.5.6 missing: '+', '.join(missing))
if "'voucherNumber',v_settlement_voucher" not in sql: raise SystemExit('FAIL unique settlement voucher missing')
if sql.count('erp_next_document_number') < 4: raise SystemExit('FAIL document sequencing incomplete')
print('PASS V7.5.6 secure linked multi-currency payment chain for sales, purchases, and maintenance')
