from pathlib import Path

root = Path(__file__).resolve().parents[1]
migration = (root / 'supabase/migrations/20260813124053_maintenance_item_bound_accounting_and_issue_document.sql').read_text(encoding='utf-8')
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
need('Maintenance item bindings fail closed', all(value in migration for value in (
     'maintenance_material_revenue_account_missing',
     'maintenance_material_inventory_account_missing',
     'maintenance_material_cost_account_missing',
     'maintenance_service_revenue_account_missing')))
need('Customer billing uses line selling values',
     'coalesce(p.line_total_price,p.unit_price*p.quantity,0)' in migration
     and "'unitPrice',p.unit_price" in migration)
need('Material cost uses active authoritative FIFO totals', all(value in migration for value in (
     'sum(fc.total_cost) actual_cost', "fc.status='active'", "fc.item_type='product'")))
need('Revenue inventory and cost remain item-bound', all(value in migration for value in (
     "ac->>'revenueAccountId'", "ac->>'assetAccountId'", "ac->>'costExpenseAccountId'")))
need('Residual labor alone uses configured maintenance revenue',
     'v_labor_amount:=round(greatest(o.sale_price-v_bound_billing,0),2)' in migration
     and "defaults->>'maintenanceRevenueUsdAccountId'" in migration)
need('Exact journal identities remain owned by R57 reversal fields',
     'invoice_journal_entry_id=v_entry' in migration and 'cost_journal_entry_ids=v_entries' in migration)
need('RPC exposure remains least privilege',
     'from public,anon,authenticated' in migration
     and 'to authenticated,service_role' in migration)

if failures:
    raise SystemExit('R58 verification failed: ' + ', '.join(failures))
print('R58 maintenance warehouse/account binding verification PASS')
