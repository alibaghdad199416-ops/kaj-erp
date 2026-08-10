#!/usr/bin/env python3
from pathlib import Path
import sys
import re

ROOT = Path(__file__).resolve().parents[1]
errors=[]

def read(rel): return (ROOT/rel).read_text(encoding='utf-8', errors='replace')
def need(cond,msg):
    if not cond: errors.append(msg)

migration=read('supabase/migrations/20260807180000_v2300_atomic_workflow_enterprise_audit.sql')
r49=read('supabase/migrations/20260810090000_r49_focused_final_permission_runtime_closure.sql')
purchase=read('lib/features/purchases/repositories/purchase_workflow_repository.dart')
sales=read('lib/features/sales/workflow/repositories/sales_workflow_repository.dart')
inventory_repo=read('lib/features/inventory/data/inventory_repository.dart')
transfer_page=read('lib/features/inventory/pages/transfer_stock_page.dart')
payment=read('lib/core/finance/invoice_payment_batch_dialog.dart')
cash_repo=read('lib/features/accounting/cashbox/repositories/cashbox_repository.dart')
cash_page=read('lib/features/accounting/cashbox/pages/cashbox_page.dart')
audit_repo=read('lib/features/settings/access/repositories/access_repository.dart')
audit_page=read('lib/features/settings/access/pages/users_page.dart')
excel=read('lib/core/exporting/excel_download_service_web.dart')
splash=read('lib/features/splash/pages/splash_page.dart')
login=read('lib/features/auth/pages/login_page.dart')
access=read('lib/features/settings/access/controllers/access_controller.dart')
startup=read('lib/core/startup/startup_coordinator.dart')
deploy=read('tool/deploy_production.ps1')
maintenance_repo=read('lib/features/maintenance/data/maintenance_repository.dart')
maintenance_details=read('lib/features/maintenance/pages/maintenance_order_details_dialog.dart')
details_repo=read('lib/features/sales/workflow/repositories/commercial_order_details_repository.dart')
order_details=read('lib/features/sales/workflow/pages/order_details_dialog.dart')
car_transfer_repo=read('lib/features/inventory/cars/data/car_warehouse_transfer_repository.dart')
car_transfer_page=read('lib/features/inventory/cars/pages/car_warehouse_transfers_page.dart')
policy_v764=read('supabase/migrations/20260807060000_v764_pre_runtime_business_policy_closure.sql')
invoice_v767=read('supabase/migrations/20260807080000_v767_invoice_export_runtime_closure.sql')
r14_runtime=read('supabase/migrations/20260808001500_r14_runtime_rpc_invoice_root_closure.sql') if (ROOT/'supabase/migrations/20260808001500_r14_runtime_rpc_invoice_root_closure.sql').exists() else ''
r22_runtime=read('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql') if (ROOT/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql').exists() else ''
posting_v760=read('supabase/migrations/20260807013000_v760_no_capitalization_accounting_integrity.sql')
payment_v757=read('supabase/migrations/20260806214500_v757_multicurrency_payment_chain_hardening.sql')
logistics_v736=read('supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql')

# Stable atomic PostgREST draft contracts: close the historical overloaded RPC/400 path.
need("'erp_r49_create_purchase_order'" in purchase and 'public.erp_v2300_create_purchase_order(' in r49,
     'purchase create does not use the current R49 wrapper over the stable v2300 RPC')
need("'erp_create_cloud_purchase_order'" not in purchase, 'historical purchase create RPC still called from repository')
need("'erp_r49_create_sales_order'" in sales and 'public.erp_v2300_create_sales_order(' in r49,
     'sales create does not use the current R49 wrapper over the stable v2300 RPC')
need('erp_v2300_create_purchase_order' in migration and 'erp_v2300_create_sales_order' in migration,
     'v2300 atomic draft SQL functions missing')
need("'effectiveAt': (effectiveAt ?? DateTime.now())" in purchase and "'effectiveAt': (effectiveAt ?? DateTime.now())" in sales,
     'commercial drafts do not send operational effectiveAt atomically')

# Definition-driven, single-currency order and invoice-owned accounting policy.
need('order_item_currency_mismatch' in policy_v764 and 'erp_v764_definition_currency' in policy_v764,
     'order items are not guarded by their definition currency')
need('salesRevenueUsdAccountId' in policy_v764 and 'salesRevenueIqdAccountId' in policy_v764 and
     'inventoryAssetAccountId' in policy_v764 and 'costExpenseAccountId' in policy_v764,
     'definition-driven inventory/cost/revenue account bindings are incomplete')
need('erp_v767_assert_partner_ledgers' in invoice_v767 and "'customer'" in invoice_v767 and "'supplier'" in invoice_v767,
     'dual-currency customer/supplier ledger preflight missing')
legacy_safe_approval = (
    "'erp_v767_approve_purchase_invoice_safe'" in purchase
    and "'erp_v767_approve_sales_invoice_safe'" in sales
)
r14_safe_approval = (
    "'erp_r14_approve_purchase_invoice'" in purchase
    and "'erp_r14_approve_sales_invoice'" in sales
    and 'erp_v767_invoice_policy_preflight' in r14_runtime
    and 'erp_v762_approve_workflow_invoice' in r14_runtime
)
r22_safe_approval = (
    "'erp_r22_approve_purchase_invoice'" in purchase
    and "'erp_r22_approve_sales_invoice'" in sales
    and 'erp_r22_invoice_preflight' in r22_runtime
    and 'erp_v767_invoice_policy_preflight' in r22_runtime
    and 'erp_r22_post_purchase_invoice_direct' in r22_runtime
)
need(legacy_safe_approval or r14_safe_approval or r22_safe_approval,
     'workflow repositories bypass the safe invoice policy preflight')
need('erp_v760_normalize_purchase_invoice_posting' in posting_v760 and
     "'definition_accounts_no_capitalization'" in posting_v760,
     'purchase invoice posting is not normalized to definition accounts without capitalization')
need('cashboxes_must_be_bidirectionally_linked_for_fx' in payment_v757 and "'paymentChainVersion','v757" in payment_v757,
     'linked cashbox multi-currency payment chain is not hardened')

need("'accountingOwner','invoice'" in logistics_v736 and
     'quantity-only; valuation owned by invoice' in logistics_v736 and
     'select null::text' in logistics_v736,
     'warehouse receipt/delivery still owns accounting instead of invoice approval')
need("'status','متوفرة'" in logistics_v736 and "'status','قيد البيع'" in logistics_v736,
     'car availability lifecycle is not updated by approved receipt/delivery')

# Operational date/time coverage for payments, warehouse transfers and cash transfers.
need('DateTime paymentDate = DateTime.now();' in payment and 'paymentDate: row.paymentDate' in payment,
     'payment rows do not carry independent operational timestamps')
need("DateFormat('yyyy-MM-dd HH:mm').format(row.paymentDate)" in payment,
     'payment date/time selector is not rendered')
need('erp_v2300_pay_cloud_workflow_invoice_batch' in purchase and 'erp_v2300_pay_cloud_workflow_invoice_batch' in sales,
     'sales/purchase payment batches bypass operational-date validator')
need('erp_v2300_record_maintenance_payment_batch' in maintenance_repo,
     'maintenance payment batch bypasses v2300 date validation')
need('erp_v2300_validate_payment_dates' in migration and 'erp_validate_operational_date(p_company_id,lower(p_module),v_date)' in migration and "erp_v2300_validate_payment_dates(p_company_id,'maintenance',p_payments)" in migration,
     'payment operational date SQL validation missing')
need('DateTime _effectiveAt = DateTime.now();' in transfer_page and 'effectiveAt: _effectiveAt' in transfer_page,
     'warehouse transfer UI does not propagate operational time')
need("'erp_r49_transfer_inventory_stock_batch'" in inventory_repo and
     "'erp_r49_create_car_warehouse_transfer'" in inventory_repo and
     'public.erp_v2300_transfer_inventory_stock_batch(' in r49 and
     'public.erp_v2300_create_car_warehouse_transfer(' in r49,
     'inventory transfers bypass the current R49 wrappers over v2300 operational contracts')
need("'erp_r49_create_car_warehouse_transfer_batch'" in car_transfer_repo and
     'effectiveAt: effectiveAt' in car_transfer_page and
     'public.erp_v2300_create_car_warehouse_transfer_batch(' in r49 and
     'p_notes,p_effective_at' in r49,
     'car batch transfer page bypasses the current permission/timestamp wrapper chain')
need("row['transferDate'] ?? row['effectiveAt'] ?? row['createdAt']" in car_transfer_page and
     "'currentWarehouseName': currentWarehouse['name']" in car_transfer_repo,
     'car transfer details can show creation time or stale warehouse label instead of live/effective data')
need('erp_v2300_create_car_warehouse_transfer_batch' in migration,
     'dated car batch transfer SQL wrapper missing')
r9_finance = read('supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql')
r9_cash_date_chain = (
    "'erp_r9_transfer_cloud_cash'" in cash_repo and
    "'p_transfer_date': transferDate.toUtc().toIso8601String()" in cash_repo and
    'transferDate: transferDate' in cash_page and
    'erp_r9_transfer_cloud_cash' in r9_finance and
    'erp_v2300_transfer_cloud_cash' in r9_finance and
    'p_exchange_rate,p_transfer_date,p_notes' in r9_finance.replace('\n', '')
)
r22_cash_date_chain = (
    "'erp_r22_transfer_cloud_cash'" in cash_repo and
    "'p_transfer_date': transferDate.toUtc().toIso8601String()" in cash_repo and
    'transferDate: transferDate' in cash_page and
    'create or replace function public.erp_r22_transfer_cloud_cash' in r22_runtime and
    "erp_validate_operational_date(p_company_id,'accounting',p_transfer_date)" in r22_runtime and
    "'cashTransactionId'" in r22_runtime and "'cashAccountId'" in r22_runtime
)
need(r9_cash_date_chain or r22_cash_date_chain,
    'cashbox transfer does not preserve selected operational timestamp through the current canonical wrapper chain',
)
need('erp_v2300_transfer_cloud_cash' in migration and "erp_validate_operational_date(p_company_id,'accounting',p_transfer_date)" in migration,
     'cash transfer operational period guard missing')

# Scrap posting must use item definition asset + warehouse dual-currency expense.
need('create or replace function public.erp_account_scrap_inventory_movement()' in migration,
     'scrap accounting trigger override missing')
need("erp_v764_definition_data(new.company_id,'product',v_product_id)" in migration,
     'scrap posting does not source asset account from item definition')
need('erp_v764_scrap_expense_account' in migration,
     'scrap posting does not resolve USD/IQD expense account')
need("'movementDate',v_effective_at,'effectiveAt',v_effective_at" in migration and
     "'entryDate',v_effective_at,'effectiveAt',v_effective_at" in migration,
     'scrap inventory/journal operational timestamps are not synchronized')

# Detail dialogs must expose live operational data, not only technical creation timestamps.
commercial_details_live = (
    ('erp_v2300_get_commercial_order_complete_details' in details_repo and
     'erp_v2300_get_commercial_order_complete_details' in migration)
    or
    ('erp_r28_get_commercial_order_complete_details' in details_repo and
     (ROOT/'supabase/migrations/20260808170000_r28_complete_runtime_closure.sql').is_file() and
     'erp_r28_get_commercial_order_complete_details' in read('supabase/migrations/20260808170000_r28_complete_runtime_closure.sql'))
)
need(commercial_details_live,
     'commercial details dialog does not use a canonical live details contract')
need("order['effectiveAt']" in order_details and 'Operational date and time' in order_details,
     'commercial details dialog omits the entered operational date/time')
need('_repository.getOrders()' in maintenance_details and '_repository.getOrderLines(_order.id)' in maintenance_details and
     'MaintenanceOrderModel? liveOrder' in maintenance_details,
     'maintenance details dialog does not refresh live order/line data')
need('Operational date and time' in maintenance_details and 'order.maintenanceDate' in maintenance_details,
     'maintenance details dialog omits the operational date/time')

# Enterprise audit must be real database audit data and exportable.
need("'erp_v2300_audit_feed'" in audit_repo and "'erp_v2300_record_app_audit'" in audit_repo,
     'access UI still uses legacy audit storage')
need('erp_install_audit_triggers' in migration and 'from public.erp_audit_log' in migration,
     'enterprise audit feed/trigger installation missing')
need('_exportAuditPdf' in audit_page and '_exportAuditExcel' in audit_page and "action: 'export'" in audit_page,
     'audit PDF/Excel export or export audit event missing')

# Excel web route must not rely only on old file_saver behavior.
need('html.Blob' in excel and 'AnchorElement' in excel and '.xlsx' in excel,
     'browser-native XLSX download path missing')

# Session and blue brand closure.
need('restorePersistedSession' in access and 'currentSession' in access,
     'persisted Supabase session restore missing')
need("..['authProvider'] = 'supabase'" in audit_repo,
     'ERP access bootstrap still labels Supabase authentication as Firebase')
need('KajDesignTokens.electricBlue' in splash and 'KajDesignTokens.electricBlue' in login,
     'launch/login blue branding missing')
need('_startupFuture!' not in startup, 'startup coordinator retains nullable future force-unwrap')
need('if ($ReconfigureRuntime)' in deploy and 'Using the existing dart_defines.json unchanged.' in deploy,
     'production deploy still reconfigures runtime connection values by default')

# Precision contract.
def max_decimal_digits(source):
    values=[int(v) for v in re.findall(r'decimalDigits:\s*(\d+)', source)]
    return max(values) if values else 0
need(max_decimal_digits(payment) >= 15 and max_decimal_digits(cash_page) >= 15,
     'FX input precision below 15 decimal places')
precision_sql = read('supabase/migrations/20260807233500_r9_fx_precision_and_field_guards.sql')
need('numeric(38,20)' in precision_sql and 'erp_payment_settlement_plans' in precision_sql,
     'database FX precision is not preserved at 20 decimal places')

if errors:
    print('FAILED V23.0.0 runtime/console closure')
    for e in errors: print('  -',e)
    sys.exit(1)
print('PASS V23.0.0 runtime/console closure')
print('- historical purchase-create PostgREST overload path replaced with atomic payload RPC')
print('- single-currency item policy, dual partner ledgers and invoice-owned definition accounting retained')
print('- operational date/time covers commercial drafts, payments, product/car warehouse and cash transfers')
print('- scrap accounting uses definition asset account + currency-specific scrap expense account')
print('- enterprise audit feed and PDF/Excel export use the real database audit trail')
print('- browser-native XLSX download, persisted session, blue entry branding and >=15-decimal FX retained')
