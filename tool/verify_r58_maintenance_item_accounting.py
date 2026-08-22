from pathlib import Path

root = Path(__file__).resolve().parents[1]
legacy = (root / 'supabase/migrations/20260813124053_maintenance_item_bound_accounting_and_issue_document.sql').read_text(encoding='utf-8')
r87 = (root / 'supabase/migrations/20260818233500_r87_phase10_corrective_integrity.sql').read_text(encoding='utf-8')
runtime = (root / 'supabase/tests/verify_r58_maintenance_item_accounting_runtime.sql').read_text(encoding='utf-8')
pdf = (root / 'lib/core/printing/maintenance_document_pdf_service.dart').read_text(encoding='utf-8')
dialog = (root / 'lib/features/maintenance/pages/maintenance_order_details_dialog.dart').read_text(encoding='utf-8')
failures = []


def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)


need('Warehouse PDF consumes executed issue-event rows',
     "event['status']?.toString() != 'executed'" in pdf and 'maintenanceWarehouseIssueRows' in pdf
     and 'issueEvents: costs.issueEvents' in dialog)
need('Warehouse aggregation key retains product and warehouse identity',
     "final key = '$productId\\u0000$warehouseId'" in pdf)
need('Warehouse PDF excludes internal FIFO cost fields',
     'actualCost' not in pdf and 'fifoCost' not in pdf and 'profit' not in pdf)
need('Maintenance item bindings fail closed', all(value in r87 for value in (
     'maintenance_material_revenue_account_missing',
     'maintenance_material_inventory_account_missing',
     'maintenance_material_cost_account_missing',
     'maintenance_service_revenue_account_missing')))
need('Customer billing uses line selling values',
     'coalesce(p.line_total_price,p.unit_price*p.quantity,0)' in r87
     and "'unitPrice',p.unit_price" in r87)
need('Material issue owns authoritative FIFO cost posting', all(value in r87 for value in (
     'create or replace function public.erp_r57_execute_maintenance_material_issue(',
     'erp_inventory_fifo_consumptions(',
     "'maintenance_material_issue_cost'",
     "v_accounts->>'costExpenseAccountId'",
     "v_accounts->>'assetAccountId'",
     "'currency',v_cost_currency",
     'journal_entry_id=v_cost_journal')))
need('Invoice owns receivable/revenue without duplicate inventory cost posting',
     "'maintenance_invoice_revenue'" in r87
     and "'inventoryCostPostingOwner','material_issue_event'" in r87
     and "cost_journal_entry_ids='[]'::jsonb" in r87)
need('Native inventory costs remain grouped by definition currency',
     'erp_r87_maintenance_material_cost_totals' in r87
     and 'group by cost_currency' in r87
     and 'erp_v764_definition_currency' in r87)
need('Revenue and inventory-cost bindings remain item-bound', all(value in r87 for value in (
     "ac->>'revenueAccountId'", "v_accounts->>'assetAccountId'", "v_accounts->>'costExpenseAccountId'")))
need('Residual labor alone uses configured maintenance revenue',
     'v_labor_amount:=round(greatest(o.sale_price-v_bound_billing,0),2)' in r87
     and "defaults->>'maintenanceRevenueUsdAccountId'" in r87)
need('Exact journal identities are owned by their lifecycle events',
     'invoice_journal_entry_id=v_entry' in r87
     and 'journal_entry_id=v_cost_journal' in r87)
need('RPC exposure remains least privilege',
     'revoke all on function public.erp_maintenance_bound_accounts(uuid,text,text,boolean)' in legacy
     and 'from public,anon,authenticated' in legacy
     and 'to service_role' in legacy)
need('Runtime regression protects R87 ownership split', all(value in runtime for value in (
     'r58_material_issue_cost_posting_not_active',
     'r58_invoice_revenue_ownership_not_active',
     'r58_native_cost_currency_aggregation_not_active',
     'r58_active_issue_fifo_cost_mismatch')))

if failures:
    raise SystemExit('R58 verification failed: ' + ', '.join(failures))
print('R58 maintenance warehouse/account binding verification PASS')
