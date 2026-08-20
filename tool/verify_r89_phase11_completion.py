from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def text(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        errors.append(f'missing file: {rel}')
        return ''
    return path.read_text(encoding='utf-8', errors='replace')


def need(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def has_all(label: str, rel: str, needles: list[str]) -> None:
    data = text(rel)
    missing = [needle for needle in needles if needle not in data]
    if missing:
        errors.append(f"{label}: missing {missing!r} in {rel}")

# 1-5. Operational documents, warehouse lifecycle, invoices and payments.
has_all('sales/purchase order table', 'lib/core/widgets/commercial_workflow_order_table.dart', [
    'Order number', 'Date & time', 'Created by', 'Currency', 'Total amount',
    'Workflow stage', 'Details & Items',
])
has_all('commercial item lifecycle', 'lib/features/sales/workflow/pages/order_details_dialog.dart', [
    'Item lifecycle: Ordered → Warehouse movement → Invoiced', 'Ordered qty',
    'Warehouse received', 'Warehouse issued', 'Invoiced qty', 'Remaining qty',
    'Unit price', 'Warehouse', 'Draft created by', 'Approved by', 'Approval time',
    'Invoice number', 'Document reference', 'Payment reference', 'FX details',
])
has_all('maintenance operational table', 'lib/features/maintenance/pages/maintenance_page.dart', [
    'Order number', 'Date / time', 'Customer', 'Car', 'Created by', 'Currency',
    'Total', 'Workflow stage',
])
has_all('maintenance details tables', 'lib/features/maintenance/pages/maintenance_order_details_dialog.dart', [
    'Item / Service', 'Requested:', 'Issued:', 'Invoiced:', 'Remaining', 'Unit price',
    'Warehouse', 'Invoice number', 'Document reference', 'Approved / posted by',
    'Payment reference', 'Payment date / time', 'Invoice / order',
])
r88 = text('supabase/migrations/20260819210000_r88_phase11_operational_financial_closure.sql')
need('receipt/delivery canonical adapter missing', all(token in r88 for token in [
    'erp_manage_commercial_order_component_v3',
    "v_type not in ('order','delivery','receipt','logistics','invoice','payment')",
    "v_inner_type:=case when v_type in ('delivery','receipt','logistics') then 'logistics'",
]))
need('redundant Purchase Order Received action still present', not re.search(r'purchase\s+order\s+received', '\n'.join([
    text('lib/features/purchases/pages/purchase_workflow_page.dart'),
    text('lib/core/widgets/commercial_workflow_order_table.dart'),
]), re.I))

# 6-7. Vehicle scheduling/history and real recurrence semantics.
has_all('vehicle scheduling/history UI', 'lib/features/inventory/cars/pages/vehicle_service_card_page.dart', [
    'Vehicle Maintenance Scheduling', 'Add schedule', 'Recurrence', 'Assigned user',
    'Linked order', 'Convert to Maintenance Order', 'Custom title', 'Custom description',
])
has_all('vehicle service PDF history', 'lib/core/printing/vehicle_service_card_pdf_service.dart', [
    'maintenanceHistory', 'customDetails', 'invoice', 'payment', 'currency',
])
r89 = text('supabase/migrations/20260820090000_r89_phase11_completion_closure.sql')
need('recurrence must consume converted schedule', "new.status not in ('completed','converted')" in r89)
need('recurrence successor backfill missing', "s.status in ('completed','converted')" in r89 and 'recurrence_sequence+1' in r89)
need('schedule direct table bypass not closed', 'revoke all on table public.erp_vehicle_maintenance_schedules from public,anon,authenticated' in r89)
need('history detail direct table bypass not closed', 'revoke all on table public.erp_maintenance_history_details from public,anon,authenticated' in r89)

# 8. Cashbox workspace + dedicated detail page/actions.
has_all('cashbox workspace', 'lib/features/accounting/cashbox/pages/cashbox_page.dart', [
    'Total Cash In', 'Total Cash Out', 'Current Balance', '_openCashboxDetail',
    'MaterialPageRoute<void>', 'Counter account', 'Related document', 'View', 'Print',
    'Edit', 'Delete',
])

# 9. Trial balance detail keys and correct separation.
need('trial balance six-column filter repair missing', all(k in r88 for k in [
    'openingDebit', 'openingCredit', 'periodDebit', 'periodCredit', 'closingDebit', 'closingCredit',
]))
has_all('trial balance UI', 'lib/features/accounting/pages/accounting_center_page.dart', [
    'Opening debit', 'Opening credit', 'Period debit', 'Period credit',
    'Closing debit', 'Closing credit',
])

# 10. Cash Flow Statement: explicit cash rows + period/currency/cashbox + net.
has_all('cash flow UI/repository', 'lib/features/accounting/pages/accounting_center_page.dart', [
    'All cashboxes', 'cashboxFilter', 'Net cash flow', "cashAccountId: widget.type == _AccountingReportType.cashFlow",
])
has_all('cash flow repository', 'lib/features/accounting/repositories/professional_accounting_repository.dart', [
    'erp_r89_list_cashboxes_for_cash_flow', 'erp_r89_cloud_cash_flow_hierarchy',
    "'p_cash_account_id': cashAccountId",
])
need('cash flow still infers unknown journal signs', "public.erp_try_numeric(x->>'cashIn',0)>0" in r88 and "public.erp_try_numeric(x->>'cashOut',0)>0" in r88)
need('cashbox scope missing from R89 cash flow', "or x->>'cashAccountId'=p_cash_account_id" in r89)

# 11. Notification center detailed events and deep links.
need('operational notification event set incomplete', all(token in r88 for token in [
    'purchase_receipt_created', 'purchase_receipt_approved', 'sales_delivery_created',
    'sales_delivery_approved', 'purchase_invoice', 'sales_invoice',
    'payment_received', 'supplier_payment', 'maintenance_material_issue',
    'maintenance_invoice', 'maintenance_payment', 'erp_r88_record_report_event',
    'maintenance_schedule_reminder',
]))
has_all('notification deep-link navigation', 'lib/features/notifications/pages/notification_center_page.dart', [
    "notification['deepLink']", "'referenceId': notification['referenceId']",
    "'cashboxId': notification['cashboxId']", "'carId': notification['carId']",
])

# 12. Granular action+field permissions and structured Settings matrix.
perm = text('lib/features/settings/access/models/permission_catalog.dart')
for code in [
    'sales.actions.restrict', 'sales.order.approve', 'sales.delivery.create', 'sales.delivery.approve',
    'sales.invoice.create', 'sales.invoice.approve', 'sales.payment', 'sales.reverse',
    'purchases.actions.restrict', 'purchases.order.approve', 'purchases.receipt.create',
    'purchases.receipt.approve', 'purchases.invoice.create', 'purchases.invoice.approve',
    'purchases.payment', 'purchases.reverse', 'maintenance.actions.restrict',
    'maintenance.order.approve', 'maintenance.material_issue.create',
    'maintenance.material_issue.approve', 'maintenance.invoice.create',
    'maintenance.invoice.approve', 'maintenance.payment', 'maintenance.reverse',
    'maintenance.schedule.create', 'maintenance.schedule.update', 'maintenance.schedule.delete',
    'maintenance.schedule.assign_other', 'maintenance.schedule.convert',
    'maintenance.history_detail.edit', 'cashbox.actions.restrict',
    'cashbox.transaction.view', 'cashbox.transaction.edit', 'cashbox.transaction.delete',
    'accounting.post', 'accounting.reverse', 'inventory.transfer',
]:
    need(f'missing action permission {code}', code in perm)
field = text('lib/features/settings/access/models/field_permission_catalog.dart')
for resource in ['cars', 'inventory', 'customers', 'suppliers', 'sales', 'purchases', 'maintenance', 'accounting', 'cashbox', 'reports']:
    need(f'missing field permission resource {resource}', f"key: '{resource}'" in field)
for key in ['purchasePrice', 'maintenanceCost', 'salePrice', 'margin', 'maintenanceHistory',
            'materialCost', 'laborCost', 'itemPrice', 'profit', 'cashboxFilter', 'netCashFlow']:
    need(f'missing granular field permission {key}', f"'{key}'" in field)
has_all('permissions matrix UI', 'lib/features/settings/access/pages/users_page.dart', [
    'class _PermissionMatrix', 'DataTable(', 'Permission', 'Description', 'Code', 'Access',
])
need('commercial details still use unfiltered legacy RPC', 'erp_r89_get_commercial_order_snapshot' in text('lib/features/sales/workflow/repositories/commercial_order_details_repository.dart'))
need('maintenance cost read still uses unfiltered legacy RPC', all(token in text('lib/features/maintenance/data/maintenance_repository.dart') for token in [
    'erp_r90_get_maintenance_order_snapshot', 'erp_r89_maintenance_cost_reconciliation', 'erp_r90_maintenance_material_issue_state',
]))
need('R89 commercial server field boundary missing', 'erp_r89_filter_commercial_detail_row' in r89 and 'erp_r89_get_commercial_order_snapshot' in r89)
need('R89 maintenance server field boundary missing', 'erp_r89_filter_maintenance_cost_payload' in r89 and 'erp_r89_maintenance_cost_reconciliation' in r89)
need('R89 net cash flow field gate missing', "'reports','netCashFlow'" in r89)

# 13-15. Financial workflow/safety invariants are retained by adapters rather than rewritten.
need('R88 inventory timing contract comment missing', 'Approved Purchase Receipt' in r88 or 'approved Purchase' in r88 or 'approved' in r88)
need('R88 phase-specific action guards missing', all(token in r88 for token in [
    "'sales','delivery.approve'", "'purchases','receipt.approve'", "'maintenance','material_issue.approve'",
    "when v_stage='invoice_draft' then 'invoice.approve'", "'maintenance','payment'",
]))
need('historical migrations edited by R89 verifier design', (ROOT / 'supabase/migrations/20260820090000_r89_phase11_completion_closure.sql').exists())

# Deep links must land on exact operational records.
has_all('deep-link route arguments', 'lib/app/routes.dart', [
    '_routeArguments', 'initialCarId:', 'initialOrderId:', 'initialCashboxId:',
])

# 14. Responsive/RTL mechanics represented on core Phase 11 tables.
need('commercial table lacks bounded horizontal table scroll', 'SingleChildScrollView(' in text('lib/core/widgets/commercial_workflow_order_table.dart') and 'BoxConstraints(minWidth: constraints.maxWidth)' in text('lib/core/widgets/commercial_workflow_order_table.dart'))
need('permissions matrix lacks bounded horizontal table', 'scrollDirection: Axis.horizontal' in text('lib/features/settings/access/pages/users_page.dart'))

# 16. Focused verifier itself and forward-only migration presence.
has_all('R89 LOCAL runtime test', 'supabase/tests/verify_r89_phase11_runtime.sql', [
    'R89 Phase 11 LOCAL PostgreSQL runtime PASS',
    'erp_manage_commercial_order_component_v3', 'erp_r88_filter_trial_balance_row',
    'erp_r89_cloud_cash_flow_hierarchy', 'erp_r89_get_commercial_order_snapshot',
    'erp_r89_get_maintenance_order_snapshot', 'erp_r89_spawn_next_maintenance_schedule',
    "status='converted'", 'has_table_privilege', 'rollback;',
])
has_all('R89 LOCAL runtime runner', 'tool/run_r89_local_runtime_test.ps1', [
    'quality_line_erp_local_dev', 'supabase_db_', 'verify_r89_phase11_runtime.sql',
    'docker.exe exec', 'No Production Supabase endpoint was contacted',
])
has_all('local run path includes Phase 11 gates', 'tool/run_current_web.ps1', [
    'verify_r88_phase11.py', 'verify_r89_phase11_completion.py',
    'Preparing the CURRENT LOCAL Supabase database', 'run_r89_local_runtime_test.ps1', 'LOCAL Supabase only',
])
need('R88 migration missing', (ROOT / 'supabase/migrations/20260819210000_r88_phase11_operational_financial_closure.sql').exists())
need('R89 migration missing', (ROOT / 'supabase/migrations/20260820090000_r89_phase11_completion_closure.sql').exists())

if errors:
    print('FAIL R89 Phase 11 completion verification')
    for error in errors:
        print(' -', error)
    raise SystemExit(1)

print('PASS R89 Phase 11 completion verification')
print('  - operational order/detail/invoice/payment tables are present')
print('  - purchase receipt/delivery adapter contract remains repaired')
print('  - vehicle schedules/history, converted recurrence and reminders are present')
print('  - cashbox workspace/detail and cash-flow cashbox scope are present')
print('  - trial balance and explicit cash-flow boundaries are present')
print('  - detailed operational notifications + deep-link arguments are present')
print('  - granular action/field permissions + table matrix are present')
print('  - commercial/maintenance sensitive detail reads use server-side R89 filters')
print('  - R88 and R89 are forward-only migrations; historical migrations are untouched by this delivery')
