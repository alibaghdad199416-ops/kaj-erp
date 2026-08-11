#!/usr/bin/env python3
from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
errors=[]; passed=[]
def read(rel): return (ROOT/rel).read_text(encoding='utf-8-sig',errors='replace')
def compact(value): return re.sub(r'\s+', ' ', value)
def has_call(value, function, argument):
    return re.search(
        re.escape(function) + r'\(\s*' + re.escape(argument) + r'\s*,?\s*\)',
        value,
    ) is not None
def gate(name, ok):
    (passed if ok else errors).append(name)
    print(('PASS ' if ok else 'FAIL ')+name)
model=read('lib/features/customer_service/models/opportunity_model.dart')
page=read('lib/features/customer_service/pages/add_opportunity_page.dart')
repo=read('lib/features/sales/workflow/repositories/sales_workflow_repository.dart')
r35=read('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql')
r49=read('supabase/migrations/20260810021000_r49_crm_business_reference_closure.sql')
r49e2e=read('supabase/migrations/20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql')
r49refs=read('supabase/migrations/20260810031000_r49_master_business_references.sql')
r49idempotency=read('supabase/migrations/20260810040000_r49_invoice_idempotency_quality_closure.sql')
r49completion=read('supabase/migrations/20260810050000_r49_installment_currency_fixed_asset_boundary.sql')
r49identity=read('supabase/migrations/20260810060000_r49_product_identity_accounting_integrity.sql')
r49permissions=read('supabase/migrations/20260810070000_r49_permission_scope_integrity.sql')
r49delivery=read('supabase/migrations/20260810080000_r49_independent_delivery_search_traceability.sql')
r49focused=read('supabase/migrations/20260810090000_r49_focused_final_permission_runtime_closure.sql')
r49finance=read('supabase/migrations/20260810100000_r49_financial_subledger_currency_integrity.sql')
r49profit=read('supabase/migrations/20260810110000_r49_accounting_profit_installment_surface_closure.sql')
supported_currency=read('lib/core/finance/supported_currency.dart')
permission_catalog=read('lib/features/settings/access/models/permission_catalog.dart')
opportunity_repo=read('lib/features/customer_service/repositories/opportunity_repository.dart')
opportunity_card=read('lib/features/customer_service/widgets/opportunity_card.dart')
planned_stock_page=read('lib/features/inventory/pages/planned_stock_page.dart')
inventory_repo=read('lib/features/inventory/data/inventory_repository.dart')
maintenance_repo=read('lib/features/maintenance/data/maintenance_repository.dart')
maintenance_page_edit=read('lib/features/maintenance/pages/add_maintenance_order_page.dart')
maintenance_controller_full=read('lib/features/maintenance/controllers/maintenance_controller.dart')
purchase_workflow_repo=read('lib/features/purchases/repositories/purchase_workflow_repository.dart')
financial_model_test=read('test/supported_currency_test.dart')
account_model=read('lib/features/accounting/models/account_model.dart')
cash_account_model=read('lib/features/accounting/cashbox/models/cash_account_model.dart')
financial_read_tests=read('test/authoritative_financial_read_models_test.dart')
accounting_root=read('supabase/migrations/20260807213000_v2302_runtime_accounting_root_closure.sql')
opp_controller=read('lib/features/customer_service/controllers/opportunities_controller.dart')
opp_list=read('lib/features/customer_service/pages/customer_service_page.dart')
r44=read('tool/verify_r44_thumbnail_performance_closure.py')
package=json.loads(read('package.json'))

route=read('lib/core/widgets/app_full_page_route.dart')
erp_display=read('lib/core/utils/erp_display_formatter.dart')
account_model=read('lib/features/accounting/models/account_model.dart')
journal_model=read('lib/features/accounting/models/journal_entry_model.dart')
maintenance_model=read('lib/features/maintenance/models/maintenance_order_model.dart')
expense_model=read('lib/features/accounting/expenses/models/expense_model.dart')
financial_read_test=read('test/authoritative_financial_read_models_test.dart')
workflow_card=read('lib/core/widgets/commercial_workflow_order_card.dart')

sales_controller=read('lib/features/sales/controllers/sales_controller.dart')
sales_page=read('lib/features/sales/pages/sales_page.dart')
sales_stats=read('lib/features/sales/widgets/sales_statistics.dart')
purchases_controller=read('lib/features/purchases/controllers/purchases_controller.dart')
purchases_page=read('lib/features/purchases/pages/purchases_page.dart')
inventory_controller=read('lib/features/inventory/controllers/inventory_controller.dart')
inventory_page=read('lib/features/inventory/pages/inventory_page.dart')
dashboard_model=read('lib/features/dashboard/models/dashboard_model.dart')
dashboard_repo=read('lib/features/dashboard/data/dashboard_repository.dart')
dashboard_page=read('lib/features/dashboard/pages/dashboard_page.dart')
report_model=read('lib/features/settings/reports/models/report_model.dart')
report_repo=read('lib/features/settings/reports/data/reports_repository.dart')
reports_page=read('lib/features/settings/reports/pages/reports_page.dart')
report_export=read('lib/features/settings/reports/services/report_export_service.dart')
cars_page=read('lib/features/inventory/cars/pages/cars_page.dart')
cars_stats=read('lib/features/inventory/cars/widgets/cars_statistics.dart')
installment_model=read('lib/features/accounting/installments/models/installment_model.dart')
installment_repo=read('lib/features/accounting/installments/data/installment_repository.dart')
installment_controller=read('lib/features/accounting/installments/controllers/installments_controller.dart')
installment_page=read('lib/features/accounting/installments/pages/installments_page.dart')
maintenance_controller=read('lib/features/maintenance/controllers/maintenance_controller.dart')
maintenance_page=read('lib/features/maintenance/pages/maintenance_page.dart')
transfer_stock_page=read('lib/features/inventory/pages/transfer_stock_page.dart')
car_transfers_page=read('lib/features/inventory/cars/pages/car_warehouse_transfers_page.dart')
fixed_assets_page=read('lib/features/accounting/fixed_assets/fixed_assets_page.dart')
sales_workflow_page=read('lib/features/sales/workflow/pages/sales_workflow_page.dart')
purchase_workflow_page=read('lib/features/purchases/pages/purchase_workflow_page.dart')
sales_draft_page=read('lib/features/sales/workflow/pages/sales_order_draft_page.dart')
purchase_draft_page=read('lib/features/purchases/pages/purchase_order_draft_page.dart')
accounting_page=read('lib/features/accounting/pages/accounting_page.dart')
fixed_assets_repo=read('lib/features/accounting/fixed_assets/data/fixed_assets_repository.dart')
modular_verifier=read('tool/verify_modular_runtime_architecture.py')
order_details_dialog=read('lib/features/sales/workflow/pages/order_details_dialog.dart')
invoice_payment_dialog=read('lib/core/finance/invoice_payment_batch_dialog.dart')
global_search_repo=read('lib/features/global_search/repositories/global_search_repository.dart')
global_search_page=read('lib/features/global_search/pages/global_search_page.dart')
global_search_model=read('lib/features/global_search/models/global_search_result.dart')
release_info=read('lib/core/release/app_release_info.dart')
web_version=json.loads(read('web/version.json'))
web_index=read('web/index.html')
readme_en=read('README.md')
readme_ar=read('README_AR.md')
start_here=read('START_HERE_AR.md')

legacy_sale_repo=read('lib/features/sales/data/sale_repository.dart')
legacy_purchase_repo=read('lib/features/purchases/repositories/purchase_repository.dart')
legacy_pdf=read('lib/core/printing/legacy_commercial_document_pdf_service.dart')
notification_repo=read('lib/features/notifications/repositories/notification_center_repository.dart')
gate('Expected Value uses thousands-aware parse on validation and save', "ThousandsInputFormatter.parse(v)" in page and "expectedValue: ThousandsInputFormatter.parse(_value.text) ?? 0" in page)
for f in ('currency','stage','probability','description','expectedCloseDate','winLossReason'):
    gate(f'Opportunity {f} persists through model map/read-back', f"'{f}':" in model and (f"value('{f}'" in model))
gate('Opportunity lifecycle UI includes new/contacted/qualified/proposal/negotiation/won/lost/closed', all(f"'{x}'" in page for x in ('new','contacted','qualified','proposal','negotiation','won','lost','closed')))
gate('Opportunity can find and reuse one linked sales order', 'findOrderByOpportunity' in page and 'erp_r9_find_sales_order_by_opportunity' in repo)
gate('Canonical workflow projects order/delivery/invoice/payment back to opportunity', all(x in r35 for x in ('salesOrderStatus','deliveryStatus','invoiceStatus','paymentStatus','paidAmount','remainingAmount')))
gate('Opportunity edits read back canonical server state after save', 'await _repository.update(item);' in opp_controller and 'await loadOpportunities();' in opp_controller)
gate('Opportunity pipeline totals never mix currencies into one number', 'pipelineValueByCurrency' in opp_controller and 'ErpDisplayFormatter.money' in opp_list and 'controller.pipelineValue.toStringAsFixed' not in opp_list)
gate('Opportunity stage/probability follow canonical sales workflow through paid closure', all(x in r49e2e for x in ("v_stage:='proposal'","v_stage:='negotiation'","v_stage:='won'","v_stage:='closed'","v_probability:=100","'paymentStatus'")))
gate('R49 business reference is 3 letters + 4 digits and unique per tenant', "'^OPP[0-9]{4}$'" in r49 and 'create unique index' in r49.lower())
gate('Cars and inventory receive compact references without replacing internal ids', all(x in r49refs for x in ("CAR'||lpad","PRD'||lpad",'custom references are intentionally not rewritten','erp_cars_r49_car_number_uq','erp_inventory_code_uq')))
gate('R49 reference assignment preserves UUID relational keys', 'record_id' not in r49 or 'opportunityNumber' in r49)
gate('R44 thumbnail regression verifier retained', 'per-card image load' in r44 and 'thumbnail' in r44.lower())
gate('R49 verifier registered', package.get('scripts',{}).get('verify:r49','').endswith('verify_r49_full_erp_functional_crm_ui_performance_closure.py'))
gate('Root README files identify R49 and point to the current validation entry point',
     all('R49' in x for x in (readme_en,readme_ar,start_here))
     and 'validate_r49_workspace.ps1' in readme_en
     and 'validate_r49_workspace.ps1' in readme_ar
     and 'START_HERE_AR.md' in readme_en
     and 'R15' not in readme_en.splitlines()[0]
     and 'R15' not in readme_ar.splitlines()[0])
# Direct large fixed dimensions were a recurring 100%-zoom overflow source.
large_fixed=[]
for dart in (ROOT/'lib').rglob('*.dart'):
    if dart.as_posix().endswith('/core/widgets/app_launch_shell.dart'):
        continue
    body=dart.read_text(encoding='utf-8',errors='replace')
    for match in re.finditer(r'\b(width|height)\s*:\s*(\d+(?:\.\d+)?)',body):
        if float(match.group(2)) >= 500:
            large_fixed.append(f'{dart.relative_to(ROOT)}:{match.group(1)}={match.group(2)}')
gate('No direct >=500px fixed UI dimensions remain outside the launch-shell breakpoint', not large_fixed)
deploy_r49=read('tool/deploy_r49_production.ps1')
gate('R49 production orchestrator validates workspace and permits only the eleven R49 migrations',
     'validate_r49_workspace.ps1' in deploy_r49
     and all(name in deploy_r49 for name in ('20260810021000_r49_crm_business_reference_closure.sql','20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql','20260810031000_r49_master_business_references.sql','20260810040000_r49_invoice_idempotency_quality_closure.sql','20260810050000_r49_installment_currency_fixed_asset_boundary.sql','20260810060000_r49_product_identity_accounting_integrity.sql','20260810070000_r49_permission_scope_integrity.sql','20260810080000_r49_independent_delivery_search_traceability.sql','20260810090000_r49_focused_final_permission_runtime_closure.sql','20260810100000_r49_financial_subledger_currency_integrity.sql','20260810110000_r49_accounting_profit_installment_surface_closure.sql'))
     and 'Unexpected pending migrations. Refusing production push' in deploy_r49
     and 'deploy_r49_production.ps1' in package.get('scripts',{}).get('deploy:production',''))
gate('Responsive module windows reflow instead of scaling a fixed canvas', 'FittedBox(' not in route and 'preferred.width.clamp(minimum.width, available.width)' in route and 'current.height + details.delta.dy' in route)
gate('Workspace AlertDialogs receive bounded responsive content instead of unconditional scroll constraints', 'dialog.scrollable' in route and 'width: double.infinity' in route and 'alignment: AlignmentDirectional.topStart' in route)
gate('Account codes remain text identifiers without numeric parsing', 'double.tryParse' not in erp_display.split('static String accountCode',1)[1].split('static String number',1)[0] and 'BigInt.parse' in erp_display and 'ErpDisplayFormatter.accountCode(raw)' in account_model)
gate('Workflow cards visibly separate logistics, accounting, invoice and payment', all(x in workflow_card for x in ('كمية فقط','القيد المحاسبي','Accounting entry','accountingOwner','invoiceRemaining','paymentStatus')))
gate('Sales invoice creation is backend-idempotent under concurrent retry',
     'erp_r49_guard_single_active_invoice' in r49idempotency
     and 'pg_advisory_xact_lock' in r49idempotency
     and 'if v_existing is not null then return v_existing; end if;' in r49idempotency
     and "document_type='invoice'" in r49idempotency
     and "errcode='23505'" in r49idempotency)
gate('Sales financial summaries stay separated by currency',
     all(x in sales_controller for x in ('revenueByCurrency','paidByCurrency','remainingByCurrency','_sumByCurrency'))
     and has_call(sales_page, 'CurrencyTotalsFormatter.format', 'controller.revenueByCurrency')
     and has_call(sales_stats, 'CurrencyTotalsFormatter.format', 'revenueByCurrency'))
gate('Purchases load their canonical list once and derive summaries locally',
     '_purchases = await _repository.getPurchases();' in compact(purchases_controller)
     and '_recalculateSummaries();' in purchases_controller
     and 'Future.wait<dynamic>([' not in purchases_controller
     and all(x in purchases_controller for x in ('totalPurchasesByCurrency','totalPaidByCurrency','totalRemainingByCurrency'))
     and has_call(purchases_page, 'CurrencyTotalsFormatter.format', 'controller.totalPurchasesByCurrency'))
gate('Inventory bootstrap avoids duplicate warehouse master-data requests',
     inventory_controller.count('_repository.getWarehouses(includeInactive: true)') == 1
     and '_warehouses = _allWarehouses' in inventory_controller)
gate('Product detail optional-load failures are visible instead of silently swallowed',
     'imagesLoadFailed = true' in inventory_page
     and 'stocksLoadFailed = true' in inventory_page
     and 'Some optional details could not be loaded' in inventory_page
     and 'catch (_) {}' not in inventory_page)


gate('Inventory and car valuation summaries stay separated by cost currency',
     'totalValueByCurrency' in inventory_controller
     and has_call(inventory_page, 'CurrencyTotalsFormatter.format', 'controller.totalValueByCurrency')
     and 'totalValueByCurrency' in cars_page
     and has_call(cars_stats, 'CurrencyTotalsFormatter.format', 'totalValueByCurrency'))
gate('Dashboard monetary source of truth is per-currency including live cost-layer valuation',
     'erp_r49_financial_summary_by_currency' in r49idempotency
     and 'erp_inventory_cost_layers' in r49idempotency
     and 'group by 1' in r49idempotency
     and all(x in dashboard_model for x in ('totalSalesByCurrency','inventoryValueByCurrency','totalReceivablesByCurrency'))
     and has_call(dashboard_repo, '_moneyMap', "row['inventoryValueByCurrency']")
     and has_call(dashboard_page, 'CurrencyTotalsFormatter.format', 'dashboard.inventoryValueByCurrency')
     and '_money(dashboard.inventoryValue)' not in dashboard_page)
gate('Report monetary summaries honor requested period and never export one mixed-currency scalar',
     'erp_r49_financial_report_summary_by_currency' in r49idempotency
     and 'between d1 and d2' in r49idempotency
     and 'p_start_date,p_end_date' in r49idempotency
     and all(x in report_model for x in ('totalSalesByCurrency','totalPurchaseDebtByCurrency','inventoryValueByCurrency'))
     and "_moneyMap(r['totalSalesByCurrency'])" in report_repo
     and 'CurrencyTotalsFormatter.format(report.totalSalesByCurrency)' in reports_page
     and '_currencyMap(r.totalSalesByCurrency)' in report_export
     and 'r.totalSales)' not in report_export)
gate('Mixed-currency financial trend charts are suppressed instead of plotting unlike currencies on one axis',
     'mixedCurrencies: _hasMultipleCurrencies' in dashboard_page
     and 'combined chart is hidden' in dashboard_page
     and 'currencies.length > 1' in reports_page
     and 'combined financial chart is hidden' in reports_page)


gate('Fixed-assets UI has a repository boundary and responsive field reflow',
     'Supabase.instance' not in fixed_assets_page
     and 'package:supabase_flutter' not in fixed_assets_page
     and 'FixedAssetsRepository' in fixed_assets_page
     and 'erp_r22_list_fixed_assets' in fixed_assets_repo
     and '_responsiveFieldGroup' in fixed_assets_page
     and "path.name.endswith('_page.dart')" in modular_verifier)
gate('Installments inherit canonical sale currency and never hard-code IQD totals',
     'erp_r49_list_installments' in r49completion
     and "installments.view" in r49completion
     and "s.data->>'currencyCode'" in r49completion
     and 'currencyCode' in installment_model
     and 'erp_r49_list_installments' in installment_repo
     and all(x in installment_controller for x in ('totalAmountByCurrency','totalPaidByCurrency','totalRemainingByCurrency'))
     and has_call(installment_page, 'CurrencyTotalsFormatter.format', 'controller.totalAmountByCurrency')
     and "currency: 'IQD'" not in installment_page)
gate('Maintenance aggregate cards never add unlike document currencies',
     all(x in maintenance_controller for x in ('paidRevenueByCurrency','totalCostByCurrency','_sumByCurrency'))
     and has_call(maintenance_page, 'CurrencyTotalsFormatter.format', 'controller.paidRevenueByCurrency')
     and has_call(maintenance_page, 'CurrencyTotalsFormatter.format', 'controller.totalCostByCurrency'))
gate('Dashboard installment exposure stays currency-aware end to end',
     'erp_r49_installment_dashboard_summary' in r49completion
     and "'outstandingInstallmentsByCurrency'" in r49completion
     and "- 'outstandingInstallments'" in r49completion
     and 'outstandingInstallmentsByCurrency' in dashboard_model
     and has_call(dashboard_repo, '_moneyMap', "row['outstandingInstallmentsByCurrency']")
     and has_call(dashboard_page, 'CurrencyTotalsFormatter.format', 'outstandingByCurrency')
     and 'currencyCode' in dashboard_model
     and re.search(r'MoneyFormatter\.withCurrency\(\s*item\.remainingAmount,\s*item\.currencyCode,?\s*\)', dashboard_page) is not None)
gate('Inventory transfer money display uses central currency precision without changing transfer payload values',
     'MoneyFormatter.withCurrency(car.totalCost, car.costCurrency ?? car.currency)' in transfer_stock_page
     and 'MoneyFormatter.withCurrency(cost, item.costCurrency ?? item.currency)' in transfer_stock_page
     and 'MoneyFormatter.withCurrency(line.unitCost, line.item.costCurrency ?? line.item.currency)' in transfer_stock_page
     and 'MoneyFormatter.withCurrency(car.totalCost, car.costCurrency ?? car.currency)' in car_transfers_page
     and "'cost': car.totalCost.toStringAsFixed(2)" in transfer_stock_page
     and "'cost': cost.toStringAsFixed(2)" in car_transfers_page)


gate('Invoice payment dialog never invents USD for malformed cashboxes',
     "account['currency']?.toString() ?? 'USD'" not in invoice_payment_dialog
     and '_normalizedCashboxCurrency' in invoice_payment_dialog
     and '_hasUsableCashboxIdentity' in invoice_payment_dialog
     and '_usableCashAccounts.isEmpty' in invoice_payment_dialog
     and "لا توجد صناديق نقدية معرفة." in invoice_payment_dialog)

gate('Existing financial documents never silently become USD when stored currency is missing',
     "order['currency']?.toString() ?? 'USD'" not in sales_workflow_page
     and "order['currency']?.toString() ?? 'USD'" not in purchase_workflow_page
     and "_currency = order['currency']?.toString() ?? 'USD'" not in sales_draft_page
     and "_currency = order['currency']?.toString() ?? 'USD'" not in purchase_draft_page
     and "storedCurrency != 'USD' && storedCurrency != 'IQD'" in sales_draft_page
     and "storedCurrency != 'USD' && storedCurrency != 'IQD'" in purchase_draft_page
     and re.search(
         r"final\s+currency\s*=\s*\(row\['currency'\]\s*\?\?\s*''\)\s*\.toString\(\)\s*\.trim\(\)\s*\.toUpperCase\(\)\s*;",
         accounting_page,
     ) is not None
     and "a['currency']?.toString() ?? 'USD'" not in fixed_assets_page)
gate('Financial read models never invent currency, posting status, or completed maintenance state',
     "value('currency', aliases: const ['currencyCode'])" in model
     and "final currency = _text(map['currency']).toUpperCase();" in account_model
     and "final rawCurrency = _text(map['currency']).toUpperCase();" in journal_model
     and "status: _text(map['status'])," in journal_model
     and "status: (map['status']?.toString().trim().isNotEmpty ?? false)" in maintenance_model
     and ": 'draft'," in maintenance_model
     and "currencyCode: map['currencyCode']?.toString().trim().toUpperCase() ?? ''" in maintenance_model
     and "fallback: 'pending'" in expense_model
     and "missing currency is never silently relabeled as USD or IQD" in financial_read_test)
gate('Commercial invoice accounting resolves stock/revenue/cost accounts from master data with currency guards',
     'erp_v764_definition_data' in accounting_root
     and 'erp_v764_definition_currency' in accounting_root
     and 'inventoryAssetAccountId' in accounting_root
     and 'salesCostExpenseAccountId' in accounting_root
     and 'salesRevenueUsdAccountId' in accounting_root
     and 'salesRevenueIqdAccountId' in accounting_root
     and 'erp_phase2_account_guard' in accounting_root
     and 'purchase_item_currency_mismatch' in accounting_root
     and 'purchase_supplier_missing' in accounting_root
     and 'sales_customer_missing' in accounting_root)
gate('Paid maintenance invoice requires the real customer ledger and forbids generic receivable fallback',
     'paid_maintenance_customer_required' in r49identity
     and 'erp_v764_assert_partner_dual_ledgers' in r49identity
     and 'erp_workflow_partner_account' in r49identity
     and "code='1400'" not in r49identity
     and 'erp_v736_post_maintenance_invoice_pre_r49_identity' in r49identity)

gate('Permission-scope administration is tenant-bound and cannot be escalated through users.update',
     all(name in r49permissions for name in ('erp_get_cloud_user_permission_override','erp_get_cloud_user_permissions','erp_set_cloud_user_permissions','erp_clear_cloud_user_permissions'))
     and "erp_cloud_user_has_permission(v_company,'permissions.scopes.manage')" in r49permissions
     and "erp_cloud_user_has_permission(v_company,'users.update')" not in r49permissions
     and r49permissions.count("entity_type='users' and record_id=p_user_id") >= 4
     and "p_user_id is distinct from v_self_id and not v_can_manage" in r49permissions
     and "raise exception 'user_not_found'" in r49permissions)

gate('Document attachments enforce the same sales/purchase permissions in UI, RPC and Storage',
     'PermissionAction.require(context, _updatePermission)' in order_details_dialog
     and 'erp_r49_document_can_read' in r49identity
     and 'erp_r49_document_can_write' in r49identity
     and all(x in r49identity for x in ("'sales.view'","'sales.update'","'purchases.view'","'purchases.update'"))
     and 'erp_link_cloud_document_pre_r49_identity' in r49identity
     and 'revoke all on function public.erp_link_cloud_document_pre_r49_identity(uuid,uuid,jsonb) from public,anon,authenticated;' in r49identity
     and 'create policy enterprise_documents_select' in r49identity
     and 'create policy enterprise_documents_insert' in r49identity
     and 'create policy enterprise_documents_update' in r49identity
     and 'erp_r49_try_uuid' in r49identity
     and 'public.erp_r49_try_uuid((storage.foldername(name))[1])' in r49identity
     and 'revoke all on function public.erp_r49_document_source_module(uuid,uuid) from public,anon,authenticated;' in r49identity
     and 'grant execute on function public.erp_r49_document_source_module(uuid,uuid) to service_role;' in r49identity)


gate('Release metadata is synchronized across Dart, web manifest and boot fallback',
     "22.9.8-r49-focused-final-completion" in release_info
     and web_version.get('syncEngine')=='22.9.8-r49-focused-final-completion'
     and web_version.get('operationalRevision')=='22.9.8-r49-focused-final-completion'
     and web_version.get('releaseToken')=='r49-focused-final-completion-20260810'
     and '22.9.8+229008-r49-focused-final-completion-20260810' in web_index)

gate('Global search includes tenant-safe CRM opportunities and currency-aware monetary results',
     'erp_r49_cloud_global_search' in r49delivery
     and "entity_type='opportunities'" in r49delivery
     and "'customer_service.view'" in r49delivery
     and 'is_active_company_member(p_company_id)' in r49delivery
     and "'opportunityNumber'" in r49delivery
     and "'expectedValue'" in r49delivery
     and "'currency'" in r49delivery
     and "'erp_r49_cloud_global_search'" in global_search_repo
     and 'currency: _currency' in global_search_repo
     and "'opportunity' => Icons.handshake_outlined" in global_search_repo
     and 'final String? currency;' in global_search_model
     and 'MoneyFormatter.withCurrency' in global_search_page)

gate('Global search cache invalidates on committed cross-module changes',
     'AppDataChangeBus.instance.events.listen' in global_search_page
     and '_queryCache.clear();' in global_search_page
     and 'unawaited(_search(query))' in global_search_page
     and 'unawaited(_changeSubscription!.cancel())' in compact(global_search_page))

gate('Global search never labels a missing journal status as posted',
     "b.row_payload->>'type'='القيود المحاسبية'" in r49delivery
     and "'unknown'" in r49delivery
     and "coalesce(j.data->>'status','posted')" not in r49delivery)

gate('Cashbox backend fails closed on permissions, currency and active-state integrity',
     'create or replace function public.erp_r42_save_cash_account' in r49delivery
     and "'accounting.create'" in r49delivery
     and "'accounting.update'" in r49delivery
     and 'cashbox_currency_required' in r49delivery
     and 'cashbox_active_state_required' in r49delivery
     and 'erp_r24_guard_cash_account_payload' in r49delivery)

gate('Cashbox deletion requires accounting.delete and rejects boxes with financial movements',
     'create or replace function public.erp_delete_cloud_cash_account' in r49delivery
     and "'accounting.delete'" in r49delivery
     and 'cashbox_has_financial_movements' in r49delivery)

gate('Financial active flags fail closed instead of inventing enabled master data',
     "_asBool(map['isActive'], fallback: false)" in account_model
     and 'fallback: false' in cash_account_model
     and 'missing financial active flags fail closed' in financial_read_tests)


gate('Existing-record currency editing fails closed while new records may use the application default',
     "return codes.contains(code) ? code : null;" in compact(supported_currency)
     and "normalize(stored) ?? (isNew ? defaultCode : '')" in compact(supported_currency)
     and 'existing records fail closed while new records may default to USD' in financial_model_test
     and "SupportedCurrency.initial(isNew: false, stored: null), ''" in financial_model_test
     and re.search(r'SupportedCurrency\.initial\(\s*isNew:\s*o\s*==\s*null,\s*stored:\s*o\?\.currency,?\s*\)', page) is not None)

gate('CRM CRUD permissions are granular in catalog, UI and backend command',
     all(code in compact(permission_catalog) for code in ("code: 'customer_service.create'","code: 'customer_service.update'","code: 'customer_service.delete'"))
     and "? 'customer_service.create'" in compact(page)
     and ": 'customer_service.update'" in compact(page)
     and has_call(opp_list, 'access.hasPermission', "'customer_service.update'")
     and has_call(opp_list, 'access.hasPermission', "'customer_service.delete'")
     and "public.erp_cloud_user_has_permission(v_company,'customer_service.create')" in r49focused
     and "public.erp_cloud_user_has_permission(v_company,'customer_service.update')" in r49focused
     and "public.erp_cloud_user_has_permission(v_company,'customer_service.delete')" in r49focused)

gate('Linked opportunity sales creation requires both CRM update and sales.create at the backend',
     "erp_r49_create_sales_order" in r49focused
     and "public.erp_cloud_user_has_permission(p_company_id,'sales.create')" in r49focused
     and "public.erp_cloud_user_has_permission(p_company_id,'customer_service.update')" in r49focused
     and "opportunity_not_found" in r49focused
     and "erp_r49_create_sales_order" in repo)

gate('Sales and purchase draft writes and approvals use protected R49 backend entry points',
     all(name in repo for name in ('erp_r49_create_sales_order','erp_r49_update_sales_order','erp_r49_approve_sales_order','erp_r49_get_sales_order_draft'))
     and all(name in read('lib/features/purchases/repositories/purchase_workflow_repository.dart') for name in ('erp_r49_create_purchase_order','erp_r49_update_purchase_order','erp_r49_approve_purchase_order','erp_r49_get_purchase_order_draft'))
     and "revoke execute on function public.erp_v2300_create_sales_order" in r49focused
     and "revoke execute on function public.erp_v2300_create_purchase_order" in r49focused
     and "'sales.approve'" in r49focused
     and "'purchases.approve'" in r49focused)

gate('Opportunity, sales and purchase edits reject stale multi-user versions',
     "'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String()" in opportunity_repo
     and r49focused.count("stale_record_conflict") >= 5
     and "stale_version_required" in r49focused
     and "'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String()" in repo
     and "'expectedUpdatedAt': expectedUpdatedAt.toUtc().toIso8601String()" in read('lib/features/purchases/repositories/purchase_workflow_repository.dart')
     and "This record was changed in another session" in read('lib/core/errors/user_facing_error.dart'))

gate('Planned stock changes require inventory.adjust and active same-tenant product/warehouse',
     "PermissionAction.require(context, 'inventory.adjust')" in planned_stock_page
     and "erp_r49_plan_inventory_movement" in inventory_repo
     and "'inventory.adjust'" in r49focused
     and "public.erp_try_boolean(data->>'isActive',false)" in r49focused
     and "warehouse_not_found_or_inactive" in r49focused
     and "product_not_found_or_inactive" in r49focused
     and "revoke execute on function public.erp_plan_inventory_movement" in r49focused)

gate('Logistics draft creation uses backend permission wrappers instead of exposed membership-only functions',
     all(name in repo for name in ('erp_r49_create_sales_delivery','erp_r49_create_sales_delivery_multi'))
     and all(name in purchase_workflow_repo for name in ('erp_r49_create_purchase_receipt','erp_r49_create_purchase_receipt_multi'))
     and all(name in r49focused for name in ('erp_r49_create_sales_delivery','erp_r49_create_sales_delivery_multi','erp_r49_create_purchase_receipt','erp_r49_create_purchase_receipt_multi'))
     and "'sales.update'" in r49focused
     and "'purchases.update'" in r49focused
     and 'revoke execute on function public.erp_create_cloud_sales_delivery' in r49focused
     and 'revoke execute on function public.erp_create_cloud_purchase_receipt' in r49focused)

gate('Maintenance create/update is permission-protected and stale edits are rejected',
     ('erp_r49_create_cloud_maintenance_order' in maintenance_repo
      or 'erp_r56_create_cloud_maintenance_order' in maintenance_repo)
     and 'erp_r49_update_cloud_maintenance_draft' in maintenance_repo
     and "'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String()" in maintenance_repo
     and 'required DateTime expectedUpdatedAt' in maintenance_controller_full
     and 'widget.order?.updatedAt' in maintenance_page_edit
     and "updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '')" in maintenance_model
     and 'erp_r9_list_cloud_maintenance_orders' in r49focused
     and "jsonb_build_object('updatedAt',o.updated_at)" in r49focused
     and "'maintenance.create'" in r49focused
     and "'maintenance.update'" in r49focused
     and 'stale_record_conflict' in r49focused
     and 'revoke execute on function public.erp_r39_create_cloud_maintenance_order' in r49focused
     and 'revoke execute on function public.erp_r39_update_cloud_maintenance_draft' in r49focused)

gate('Focused R49 migration keeps historical commercial implementations internal behind permission wrappers',
     'erp_v2300_create_sales_order' in r49focused
     and 'erp_v2300_update_sales_order' in r49focused
     and 'erp_approve_cloud_sales_order' in r49focused
     and 'erp_v2300_create_purchase_order' in r49focused
     and 'erp_v2300_update_purchase_order' in r49focused
     and 'erp_approve_cloud_purchase_order' in r49focused
     and r49focused.count('grant execute on function public.erp_r49_') >= 8)

gate('Inventory CRUD, receipt and transfers use granular backend permissions instead of role-only master-data access',
     all(name in inventory_repo for name in (
       'erp_r49_create_inventory_product','erp_r49_update_inventory_product',
       'erp_r49_adjust_product_opening_balance','erp_r49_receive_inventory_stock',
       'erp_r49_transfer_inventory_stock','erp_r49_transfer_inventory_stock_batch',
       'erp_r49_create_car_warehouse_transfer'))
     and all(name in read('lib/features/inventory/cars/data/car_warehouse_transfer_repository.dart') for name in (
       'erp_r49_create_car_warehouse_transfer_batch','erp_r49_create_car_warehouse_transfer',
       'erp_r49_edit_car_warehouse_transfer','erp_r49_reverse_car_warehouse_transfer'))
     and all(code in r49focused for code in (
       "'inventory.create'","'inventory.update'","'inventory.adjust'","'inventory.receive'","'inventory.transfer'"))
     and "qualityline.r49_master_permission" in r49focused
     and 'erp_cloud_user_has_permission' in r49focused
     and 'revoke execute on function public.erp_create_inventory_product' in r49focused
     and 'revoke execute on function public.erp_receive_inventory_stock' in r49focused
     and 'revoke execute on function public.erp_v2300_transfer_inventory_stock_batch' in r49focused
     and 'revoke execute on function public.erp_v2300_create_car_warehouse_transfer' in r49focused)

gate('Cloud listWhere filters canonical records server-side instead of downloading whole tables',
     "'erp_r49_list_cloud_master_where'" in read('lib/core/cloud/cloud_master_data_service.dart')
     and 'final rows = await list(table);' not in read('lib/core/cloud/cloud_master_data_service.dart')
     and 'erp_r15_list_cloud_master_records(p_company_id,p_table)' in r49focused
     and "p_table='erp_product_images' and p_field='productId'" in r49focused
     and "p_table='erp_warehouse_stock' and p_field in ('productId','warehouseId')" in r49focused
     and "p_table='erp_purchases' and p_field='supplierId'" in r49focused
     and 'unsupported_master_filter' in r49focused)



gate('Legacy commercial write surfaces are protected by granular permissions and stale-version checks',
     all(name in legacy_sale_repo for name in ('erp_r49_create_cloud_sale','erp_r49_create_cloud_resale','erp_r49_update_cloud_sale'))
     and all(name in legacy_purchase_repo for name in ('erp_r49_create_cloud_purchase','erp_r49_update_cloud_purchase'))
     and all(code in r49focused for code in ("'sales.create'","'sales.update'","'purchases.create'","'purchases.update'"))
     and 'stale_record_conflict' in r49focused
     and 'revoke execute on function public.erp_create_cloud_sale' in r49focused
     and 'revoke execute on function public.erp_create_cloud_purchase' in r49focused)

gate('Legacy commercial printing never fabricates payment or posted-journal detail rows',
     legacy_pdf.count('payments: const <Map<String, Object?>>[]') == 2
     and legacy_pdf.count('journalEntries: const <Map<String, Object?>>[]') == 2
     and "sale.paidAmount > 0 ? 'partial' : 'unpaid'" in legacy_pdf
     and "purchase.isPartial ? 'partial' : 'unpaid'" in legacy_pdf
     and "'status': 'posted'" not in legacy_pdf)

gate('Notification read/archive state is per-user and server identity replaces client-supplied selectors',
     'create table if not exists public.erp_notification_user_states' in r49focused
     and 'primary key(company_id,notification_id,user_key)' in r49focused
     and 'erp_r49_notification_visible' in r49focused
     and 'erp_r49_notification_user_key' in r49focused
     and 'erp_r49_list_cloud_notifications' in notification_repo
     and 'erp_r49_cloud_unread_notification_count' in notification_repo
     and 'erp_r49_mark_cloud_notification_read' in notification_repo
     and 'erp_r49_archive_cloud_notification' in notification_repo
     and 'p_user_id' not in notification_repo[notification_repo.find('Future<List<Map<String, Object?>>> loadPersistentNotifications'):]
     and 'revoke execute on function public.erp_list_cloud_notifications' in r49focused
     and 'revoke execute on function public.erp_mark_cloud_notification_read' in r49focused)

# Boundary preservation from canonical R46/R48 verifiers rather than duplicating SQL heuristics.
for rel, tokens, name in [
 ('tool/verify_r46_invoice_posting_boundary_closure.py',['purchase receipt is quantity-only','sales delivery is quantity-only','sales invoice owns posting','purchase invoice owns posting','maintenance invoice owns posting'],'Invoice-owned accounting and logistics boundaries retained'),
 ('tool/verify_r48_logistics_linked_payment_preservation.py',['secure payment backend enforces linked cashboxes','maintenance payments use secure linked payment chain'],'Cashbox/FX linked payment guards retained')]:
    txt=read(rel); gate(name, all(t in txt for t in tokens))
gate('Persisted subledger and reporting currencies fail closed instead of defaulting to USD',
     'erp_r49_assert_subledger_currency_integrity' in r49finance
     and 'erp_r49_assert_financial_reporting_currency_integrity' in r49finance
     and r49finance.count('financial_document_currency_invalid:') >= 7
     and "coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''),'USD')" not in r49finance
     and "coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''),'USD')" not in r49finance
     and "coalesce(nullif(btrim(l.currency),''),'USD')" not in r49finance)

gate('Dashboard and reports include both product and car FIFO inventory value by currency',
     r49finance.count("l.item_type in ('product','car')") >= 3
     and 'sum(l.remaining_quantity*l.unit_cost)' in r49finance
     and 'inventoryValueByCurrency' in r49finance)

gate('Financial report period includes canonical approved sales and purchase workflow invoices',
     "d.module='sales' and d.document_type='invoice'" in r49finance
     and "d.module='purchases' and d.document_type='invoice'" in r49finance
     and 'coalesce(d.effective_at,d.created_at)::date between d1 and d2' in r49finance)

gate('Internal financial aggregation helpers cannot bypass R9 browser field permissions',
     'revoke all on function public.erp_r49_financial_summary_by_currency(uuid,date) from public,anon,authenticated;' in r49finance
     and 'revoke all on function public.erp_r49_financial_report_summary_by_currency(uuid,date,date) from public,anon,authenticated;' in r49finance
     and 'grant execute on function public.erp_r49_financial_summary_by_currency(uuid,date) to service_role;' in r49finance
     and 'grant execute on function public.erp_r49_financial_report_summary_by_currency(uuid,date,date) to service_role;' in r49finance)

gate('Base subledger implementations are internal and canonical permission wrappers remain authoritative',
     all(x in r49finance for x in (
       'revoke all on function public.erp_cloud_receivables_payables(uuid) from public,anon,authenticated;',
       'revoke all on function public.erp_cloud_partner_subledger_details_v2(uuid,text) from public,anon,authenticated;',
       'revoke all on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) from public,anon,authenticated;')))


gate('Accounting profit KPI comes from posted GL revenue/expense lines instead of purchases-as-expense arithmetic',
     "a.account_type in ('revenue','expense')" in r49profit
     and "je.data->>'status'='posted'" in r49profit
     and 'erp_r49_accounting_net_profit_by_currency' in r49profit
     and "-coalesce((v_purchases" not in r49profit)
gate('Dashboard and reports use the R49 accounting-profit wrappers while retaining R9 field permissions',
     "'erp_r49_cloud_dashboard_snapshot'" in dashboard_repo
     and "'erp_r49_cloud_reports_summary'" in report_repo
     and 'erp_r9_cloud_dashboard_snapshot' in r49profit
     and 'erp_r9_cloud_reports_summary' in r49profit
     and "if v ? 'netProfitByCurrency'" in r49profit)
gate('Standalone installment schedule mutators are internal and browser repository is read-only',
     'revoke all on function public.erp_save_cloud_installment(uuid,jsonb) from public,anon,authenticated' in r49profit.lower()
     and 'revoke all on function public.erp_delete_cloud_installment(uuid,text) from public,anon,authenticated' in r49profit.lower()
     and 'erp_save_cloud_installment' not in installment_repo
     and 'erp_delete_cloud_installment' not in installment_repo
     and 'addInstallment(' not in installment_controller
     and 'updateInstallment(' not in installment_controller
     and 'deleteInstallment(' not in installment_controller)
gate('Accounting profit currency integrity fails closed with a bilingual user-facing error',
     'financial_account_currency_invalid' in r49profit
     and 'financial_account_currency_invalid' in read('lib/core/errors/user_facing_error.dart'))

if errors:
    print(f'FAIL R49 closure — {len(passed)} passed, {len(errors)} failed'); sys.exit(1)
print(f'PASS R49 FULL ERP FUNCTIONAL CRM UI PERFORMANCE CLOSURE — {len(passed)} gates')
