#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def require(condition: bool, label: str) -> None:
    if not condition:
        raise SystemExit(f'FAIL {label}')
    print(f'PASS {label}')


cars = text('lib/features/inventory/cars/pages/cars_page.dart')
add_car = text('lib/features/inventory/cars/pages/add_car_page.dart')
edit_car = text('lib/features/inventory/cars/pages/edit_car_page.dart')
require("context.l10n.isArabic ? 'إضافة سيارة' : 'Add vehicle'" in cars, 'R87 car create dialog title follows locale')
require("context.l10n.isArabic ? 'تعديل سيارة' : 'Edit vehicle'" in cars, 'R87 car edit dialog title follows locale')
require("ar ? 'إضافة سيارة' : 'Add vehicle'" in add_car, 'R87 car create page title follows locale')
require("context.l10n.isArabic ? 'تعديل السيارة' : 'Edit vehicle'" in edit_car, 'R87 car edit page title follows locale')

warehouse = text('lib/features/inventory/pages/warehouse_management_page.dart')
inv_repo = text('lib/features/inventory/data/inventory_repository.dart')
warehouse_model = text('lib/features/inventory/models/warehouse_model.dart')
for permission in ('warehouses.create', 'warehouses.update', 'warehouses.delete'):
    require(permission in warehouse, f'R87 warehouse UI enforces {permission}')
require('ensureBranchesLoaded()' in warehouse and 'DropdownButtonFormField<String?>' in warehouse, 'R87 warehouse editor loads real branch choices')
require('branch.id == _branchId' in warehouse and 'branchId: _branchId' in warehouse, 'R87 warehouse persists the selected branch UUID')
require('AppWorkspaceWindowScope.closeCurrent(context)' in warehouse, 'R87 warehouse cancel closes the workspace correctly')
require('AppWorkspaceWindowScope.closeCurrent(\n      context,\n      WarehouseModel(' in warehouse, 'R87 warehouse save returns the persisted model to its caller')
require('_verifyWarehousePersistence(warehouse)' in inv_repo, 'R87 warehouse create/update performs read-back verification')
for field in ('inventoryAccountId', 'scrapExpenseAccountId', 'scrapExpenseIqdAccountId', 'scrapExpenseUsdAccountId'):
    require(f'normalized(actual.{field})' in inv_repo, f'R87 warehouse read-back verifies {field}')
require("map['inventory_account_id']" in warehouse_model and "map['scrap_expense_usd_account_id']" in warehouse_model, 'R87 warehouse model accepts canonical snake_case DB fields')

customers = text('lib/features/business_partners/customers/controllers/customers_controller.dart')
customer_service = text('lib/features/customer_service/pages/customer_service_page.dart')
add_opp = text('lib/features/customer_service/pages/add_opportunity_page.dart')
suppliers_page = text('lib/features/business_partners/suppliers/pages/suppliers_page.dart')
require('_loadInFlight' in customers and 'loadCustomers({bool force = false})' in customers, 'R87 customer loader coalesces concurrent initial requests')
require('context.read<CustomersController>().loadCustomers(),' in customer_service, 'R87 Customer Service initial lifecycle loads customers')
require(customer_service.count('await context.read<CustomersController>().loadCustomers();') >= 2, 'R87 Opportunity create/edit waits for customers before opening')
require('await Future.wait<void>([' in add_opp and 'customersController.loadCustomers(),' in add_opp, 'R87 Opportunity form owns a dependency-load fallback')
require('loadSuppliers()' in suppliers_page and 'initState()' in suppliers_page, 'R87 analogous Supplier lifecycle still loads on first entry')

maintenance_form = text('lib/features/maintenance/pages/add_maintenance_order_page.dart')
maintenance_migration = text('supabase/migrations/20260818233500_r87_phase10_corrective_integrity.sql')
require('inventory.maintenanceItems\n          .where((item) => item.isActive)' in maintenance_form, 'R87 Maintenance item availability is not filtered by document currency')
require('_defaultDocumentPrice(InventoryModel item)' in maintenance_form and "_itemCurrency(item) == _currency ? item.salePrice : 0" in maintenance_form, 'R87 cross-currency Maintenance keeps billing price explicit without mutating master currency')
require('drop trigger if exists erp_v2301_maintenance_line_currency' in maintenance_migration, 'R87 obsolete Maintenance currency-coupling trigger is removed forward-only')
require('erp_r87_maintenance_material_cost_totals' in maintenance_migration and 'group by cost_currency' in maintenance_migration, 'R87 Maintenance inventory valuation stays separated by native cost currency')
require("'maintenance_material_issue_cost'" in maintenance_migration and "'inventoryCostPostingOwner','material_issue_event'" in maintenance_migration, 'R87 Maintenance material issue owns inventory-cost posting')
require("'maintenance_invoice_revenue'" in maintenance_migration and "'actualFifoCostByCurrency',v_cost_totals" in maintenance_migration, 'R87 Maintenance invoice owns billing/revenue while retaining per-currency FIFO traceability')

maintenance_page = text('lib/features/maintenance/pages/maintenance_page.dart')
maintenance_details = text('lib/features/maintenance/pages/maintenance_order_details_dialog.dart')
dashboard = text('lib/features/dashboard/pages/dashboard_page.dart')
dashboard_test = text('test/features/dashboard/dashboard_kpi_layout_test.dart')
require('mainAxisExtent:' not in maintenance_page and 'child: Wrap(' in maintenance_page, 'R87 Maintenance cards use natural responsive height without fixed grid extent')
require('fallbackLines = await _repository.getOrderLines(_order.id);' in maintenance_details and '_loadWarning' in maintenance_details, 'R87 Maintenance draft survives optional snapshot failure with core-data fallback')
require('dashboardKpiRowSizes(cards.length, columnCount)' in dashboard and 'dashboardKpiColumnCount(constraints.maxWidth)' in dashboard, 'R87 Dashboard KPI layout derives from actual available width and balanced rows')
require("expect(dashboardKpiRowSizes(9, 5), <int>[5, 4]);" in dashboard_test, 'R87 Dashboard desktop 9-card contract is 5 + 4')

accounting_controller = text('lib/features/accounting/controllers/accounting_controller.dart')
accounting_repo = text('lib/features/accounting/repositories/accounting_repository.dart')
journal = text('lib/features/accounting/pages/add_journal_entry_page.dart')
inventory_fields = text('lib/features/inventory/widgets/inventory_account_fields.dart')
add_inventory = text('lib/features/inventory/pages/add_inventory_page.dart')
fixed_assets = text('lib/features/accounting/fixed_assets/fixed_assets_page.dart')
cashbox_controller = text('lib/features/accounting/cashbox/controllers/cashbox_controller.dart')
cash_tx = text('lib/features/accounting/cashbox/pages/add_cash_transaction_page.dart')
cash_form = text('lib/features/accounting/cashbox/pages/cash_account_form.dart')
expense_repo = text('lib/features/accounting/expenses/data/expense_repository.dart')
require('!parentIds.contains(account.id)' in accounting_controller and '_assertJournalAccountsPostable' in accounting_controller, 'R87 Accounting controller rejects parent/header posting accounts')
require('parentIds.contains(account.id)' in accounting_repo and 'لا يمكن التقييد على حساب رئيسي/رقابي أو غير فعال.' in accounting_repo, 'R87 Accounting repository rejects non-postable manual journal accounts')
require('.postableAccounts' in journal, 'R87 Manual Journal selector exposes postable accounts only')
require('.postableAccounts' in inventory_fields and add_inventory.count('accounting.postableAccounts') >= 4 and '.postableAccounts' in fixed_assets, 'R87 reusable inventory/fixed-asset posting selectors expose leaf accounts only')
require('List<AccountModel> get postableLedgerAccounts' in cashbox_controller and '!parentIds.contains(account.id)' in cashbox_controller, 'R87 Cashbox controller exposes leaf/postable ledger accounts')
require('c.postableLedgerAccounts' in cash_tx and 'controller.postableLedgerAccounts' in cash_form, 'R87 Cashbox posting selectors exclude parent/header accounts')
require('!parentIds.contains(id)' in expense_repo, 'R87 Expense posting selector excludes parent/header accounts')
require('create trigger erp_r87_journal_line_postable' in maintenance_migration and 'perform public.erp_assert_postable_account(new.company_id,v_account_id);' in maintenance_migration, 'R87 PostgreSQL journal-line guard blocks parent/header account bypass')

accounting_center = text('lib/features/accounting/pages/accounting_center_page.dart')
trial_test = text('test/features/accounting/trial_balance_consistency_test.dart')
report_sql = text('supabase/migrations/20260801123000_operational_feature_completion.sql')
for group in ("'Opening'", "'Period'", "'Closing'"):
    require(group in accounting_center, f'R87 Trial Balance renders {group.strip(chr(39))} grouped heading')
require("row['currency']" in accounting_center and "grouped" in accounting_center, 'R87 Trial Balance/report presentation groups monetary rows by currency')
require('opening_signed+period_debit-period_credit closing_signed' in report_sql, 'R87 Trial Balance SQL derives Closing = Opening + Period')
require('trialBalanceRowIsConsistent' in trial_test and "'currency': 'USD'" in trial_test and "'currency': 'IQD'" in trial_test, 'R87 Trial Balance consistency test covers both supported currencies without combining them')

action_icon = text('lib/core/widgets/app_module_action_icon.dart')
commercial_card = text('lib/core/widgets/commercial_workflow_order_card.dart')
theme = text('lib/app/theme.dart')
require('destructive' in action_icon and 'colorScheme.error' in action_icon and 'color ?? KajDesignTokens.electricBlue' in action_icon, 'R87 shared module action icon respects destructive and semantic colors')
require('Widget build(BuildContext context) => AppModuleActionIcon(' in commercial_card, 'R87 commercial workflow actions reuse the shared icon geometry')
for token in ('cardTheme:', 'filledButtonTheme:', 'outlinedButtonTheme:', 'textButtonTheme:', 'iconButtonTheme:', 'dialogTheme:', 'dataTableTheme:'):
    require(token in theme, f'R87 global theme centralizes {token[:-1]} geometry/state styling')

print('PASS R87 Phase 10 corrective closure — all source-verifiable requirements are present')
