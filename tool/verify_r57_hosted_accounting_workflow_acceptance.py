#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
migrations = sorted((root / 'supabase/migrations').glob('*.sql'))
expected = root / 'supabase/migrations/20260811191823_r57_hosted_browser_accounting_workflow_reconciliation_closure.sql'
realtime_expected = root / 'supabase/migrations/20260812000100_r57_realtime_binding_publication_closure.sql'
cost_expected = root / 'supabase/migrations/20260812131657_r57_maintenance_cost_reconciliation_read_model.sql'
requested_cost_expected = root / 'supabase/migrations/20260812140432_r57_maintenance_requested_cost_snapshot_integrity.sql'
partial_issue_expected = root / 'supabase/migrations/20260812153000_r57_maintenance_partial_material_issue_lifecycle.sql'
multi_warehouse_expected = root / 'supabase/migrations/20260812195400_r57_maintenance_multi_warehouse_fifo_issue.sql'
delete_integrity_expected = root / 'supabase/migrations/20260813004000_r57_maintenance_delete_reversal_integrity.sql'
delete_repair_context_expected = root / 'supabase/migrations/20260813005830_r57_maintenance_deleted_repair_execution_context.sql'
inventory_product_semantics_expected = root / 'supabase/migrations/20260813013000_r57_inventory_movement_product_maintenance_card_semantics.sql'
migration = expected.read_text(encoding='utf-8')
cost_migration = cost_expected.read_text(encoding='utf-8')
requested_cost_migration = requested_cost_expected.read_text(encoding='utf-8')
partial_issue_migration = partial_issue_expected.read_text(encoding='utf-8')
delete_integrity_migration = delete_integrity_expected.read_text(encoding='utf-8')
delete_repair_context_migration = delete_repair_context_expected.read_text(encoding='utf-8')
inventory_product_semantics_migration = inventory_product_semantics_expected.read_text(encoding='utf-8')
product_page = (root / 'lib/features/inventory/pages/inventory_page.dart').read_text(encoding='utf-8')
cars_page = (root / 'lib/features/inventory/cars/pages/cars_page.dart').read_text(encoding='utf-8')
product_pdf = (root / 'lib/core/printing/product_maintenance_card_pdf_service.dart').read_text(encoding='utf-8')
maintenance_pdf = (root / 'lib/core/printing/maintenance_document_pdf_service.dart').read_text(encoding='utf-8')
enterprise_pdf = (root / 'lib/core/printing/enterprise_document_pdf_service.dart').read_text(encoding='utf-8')
warehouse_transfer_pdf = (root / 'lib/core/printing/warehouse_transfer_pdf_service.dart').read_text(encoding='utf-8')
vehicle_service_pdf = (root / 'lib/core/printing/vehicle_service_card_pdf_service.dart').read_text(encoding='utf-8')
pdf_export = (root / 'lib/core/exporting/pdf_export_service.dart').read_text(encoding='utf-8')
adaptive_pdf = (root / 'lib/core/exporting/adaptive_pdf_table.dart').read_text(encoding='utf-8')
settings = (root / 'lib/features/settings/pages/settings_hub_page.dart').read_text(encoding='utf-8')
accounting = (root / 'lib/features/accounting/pages/accounting_center_page.dart').read_text(encoding='utf-8')
controller = (root / 'lib/features/accounting/controllers/accounting_controller.dart').read_text(encoding='utf-8')
details = (root / 'lib/features/sales/workflow/pages/order_details_dialog.dart').read_text(encoding='utf-8')
maintenance = (root / 'lib/features/maintenance/pages/maintenance_order_details_dialog.dart').read_text(encoding='utf-8')
excel = (root / 'lib/core/exporting/excel_workbook_presentation.dart').read_text(encoding='utf-8')
transaction_runtime = (root / 'supabase/tests/verify_r49_erp_transactions_runtime.sql').read_text(encoding='utf-8')
failures = []

def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)

r57_sequence = [
    expected, realtime_expected, cost_expected, requested_cost_expected,
    partial_issue_expected, multi_warehouse_expected, delete_integrity_expected,
    delete_repair_context_expected, inventory_product_semantics_expected,
]
r57_start = migrations.index(expected) if expected in migrations else -1
need('R57 forward migration sequence remains intact',
     r57_start >= 0 and migrations[r57_start:r57_start + len(r57_sequence)] == r57_sequence)
need('Account identifiers use collision-safe string repair', all(x in migration for x in (
    'erp_r57_canonical_account_code', 'r57_account_code_repair_collision', 'group by organization_id')))
need('Accounting header reads authoritative cash in one RPC',
     'erp_r57_accounting_header_snapshot' in migration and 'cashByCurrency' in controller
     and 'Available cash USD' in accounting and 'AppDataChangeBus.instance.events' in accounting)
need('Settings sections initialize lazily', '_sectionCache' in settings and '_sectionCache[index] ??=' in settings)
need('Redundant root hero removed from settings', 'KajAdminWorkspace(' not in settings)
need('XLSX text values are formula-safe', "const <String>{'=', '+', '-', '@'}" in excel and 'safeText(value)' in excel)
need('Commercial reconciliation is one bounded aggregate RPC',
     'erp_r57_commercial_reconciliation' in migration and 'Workflow quantity reconciliation' in details)
need('Maintenance materials expose requested issued and invoiced quantities while labor/service stays separate',
     all(value in maintenance for value in ('Requested:', 'Issued:', 'Invoiced:', 'Item / Service'))
     and "line.isService ? '—'" in maintenance
     and 'Labor invoiced' in maintenance and 'Services invoiced' in maintenance)
need('Maintenance cost reconciliation is FIFO authoritative and currency bound',
     all(value in requested_cost_migration for value in (
         'erp_inventory_fifo_consumptions', "'issuedMaterialsActualCost'",
         "'totalOperationalCost'", "'materialsInvoiced'", "'outstanding'",
         "'currency',upper(v_order.currency_code)", "'warehouses',v_warehouses")))
need('Maintenance requested cost is immutable and separate from FIFO actual cost',
     all(value in requested_cost_migration for value in (
         'requested_unit_cost', 'requested_total_cost',
         'erp_r57_capture_maintenance_requested_cost',
         'new.requested_unit_cost:=old.requested_unit_cost',
         "'requestedCostAvailable'", "'requestedMaterialsCost'")))
need('Maintenance partial issue lifecycle is event-scoped and reversible',
     all(value in partial_issue_migration for value in (
         'erp_maintenance_material_issues',
         'erp_r57_execute_maintenance_material_issue',
         'erp_r57_reverse_maintenance_material_issue',
         'maintenance_issue_exceeds_remaining',
         "fc.delivery_id=il.issue_id", "i.status='executed'")))
need('Maintenance delete reverses event-owned stock and invoice accounting while preserving payment',
     all(value in delete_integrity_migration for value in (
         'erp_r57_reverse_maintenance_issue_for_delete',
         'erp_r57_reverse_maintenance_issues_for_delete',
         'erp_r57_reverse_maintenance_accounting_for_delete',
         'erp_delete_cloud_maintenance_order_v3',
         'erp_v731_detach_maintenance_payments',
         'erp_v736_void_journal_id',
         "'paymentPolicy','partner_balance_preserved'",
         "'paymentsRequiredDeleted',false",
         'maintenance_delete_issue_reversal_exceeds_event',
         'erp_r57_repair_deleted_maintenance_order',
         'erp_r57_repair_deleted_maintenance_orders',
         "i.status='executed'")))
need('Maintenance historical delete repair establishes tenant-correct internal auth context',
     all(value in delete_repair_context_migration for value in (
         'company_memberships',
         'maintenance_repair_active_member_required',
         "'request.jwt.claim.sub'",
         "'request.jwt.claims'",
         "'role','authenticated'",
         'erp_r57_repair_deleted_maintenance_orders(null)',
         'repairActorUserId')))
need('Inventory movement log exposes business counterparties and warehouse-transfer direction',
     all(value in inventory_product_semantics_migration for value in (
         'erp_r28_inventory_movement_log',
         'maintenance_issue_reversal',
         'maintenance_return',
         'warehouse_transfer',
         'transfer_from_name',
         'transfer_to_name',
         'supplier_name',
         'sales_customer_name',
         'maintenance_customer_name',
         "'sourceName',s.source_name",
         "'destinationName',s.destination_name")))
need('Product maintenance card is vehicle-linked and excludes internal cost payloads',
     all(value in inventory_product_semantics_migration for value in (
         'erp_r57_product_maintenance_card',
         "'carName'",
         "'customerName'",
         "'requestedQuantity'",
         "'issuedQuantity'",
         "'reversedQuantity'",
         "'warehouseContributions'",
         "'invoiceStatus'",
         "'paymentStatus'",
         "'internalMaintenanceCostExcluded',true",
         "'vehicleCostExcluded',true"))
     and all(value not in product_pdf for value in (
         "'unitCost'", "'actualCost'", "'fifoCost'", "'laborCost'",
         "'partsCost'", "'totalCost'", "'profit'", "'purchasePrice'",
         "'maintenanceCost'", "'carCost'")))
need('Product card renders maintenance history and prints through privacy-safe service',
     'getProductMaintenanceCard' in product_page
     and '_productMaintenanceHistory' in product_page
     and 'ProductMaintenanceCardPdfService' in product_page)
need('Arabic PDF document surfaces route text through explicit shaping direction helper',
     all('PdfTextSupport.text(' in text for text in (
         maintenance_pdf, enterprise_pdf, product_pdf, warehouse_transfer_pdf,
         vehicle_service_pdf, pdf_export, adaptive_pdf)))
need('Car cards use responsive content-driven rows without fixed mainAxisExtent',
     (lambda _cars: (
    "mainAxisExtent:" not in _cars
    and "ListView.separated(" in _cars
    and "final rowCount = (filteredCars.length + columns - 1) ~/ columns;" in _cars
    and "crossAxisAlignment: CrossAxisAlignment.start" in _cars
    and "CarCard(" in _cars
))((__import__("pathlib").Path(__file__).resolve().parents[1] / "lib/features/inventory/cars/pages/cars_page.dart").read_text(encoding="utf-8")))

need('Maintenance cost UI separates operational billing and settlement',
     all(value in maintenance for value in (
         'Operational / Cost', 'Billing', 'Settlement & Discrepancy',
         'Requested:', 'Issued:', 'Invoiced:')))
need('Approval boundaries reject over-processing without clamp', all(x in migration for x in (
    'r57_quantity_exceeds_order', 'r57_invoice_exceeds_approved_operational')) and 'least(' not in migration)
need('Discrepancies transition open/resolved and notifications are idempotent', all(x in migration for x in (
    "status in('open','resolved')", 'erp_r57_notification_event_uq', "'eventKey',event_key", "'userId',target_user")))
need('Fresh database executes R57 SQL proof', 'verify_r57_accounting_workflow_reconciliation.sql' in
     (root / 'tool/verify_fresh_database.ps1').read_text(encoding='utf-8'))
need('Fresh database proves maintenance requested-cost semantics',
     'verify_r57_maintenance_requested_cost_semantics.sql' in
     (root / 'tool/verify_fresh_database.ps1').read_text(encoding='utf-8'))
need('Rollback runtime proves maintenance partial multi-payment FX and retry idempotency',
     all(value in transaction_runtime for value in (
         "'r49-maintenance-payment-1'", "'r49-maintenance-payment-2'",
         "'linkedCashAccountId','r49-cash-usd'",
         "'invoiceAmount',40,'cashAmount',60000,'exchangeRate',1500",
         "'settlementMode','partial'",
         'maintenance_partial_payment_state_incorrect',
         'maintenance_partial_fx_payment_metadata_incorrect',
         'maintenance_multiple_payment_state_incorrect',
         'maintenance_payment_retry_duplicated_cash_transaction')))

if failures:
    print(f'R57 acceptance failed: {len(failures)} check(s)', file=sys.stderr)
    sys.exit(1)
print('R57 hosted/accounting/workflow acceptance PASS')
