#!/usr/bin/env python3
from pathlib import Path
import hashlib
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8', errors='replace')

def need(cond, msg):
    if not cond:
        errors.append(msg)

pill = read('lib/core/widgets/app_pill_tab_bar.dart')
users = read('lib/features/settings/access/pages/users_page.dart')
sales = read('lib/features/sales/workflow/pages/sales_order_draft_page.dart')
repo = read('lib/features/accounting/repositories/professional_accounting_repository.dart')
center = read('lib/features/accounting/pages/accounting_center_page.dart')
migration = read('supabase/migrations/20260807213000_v2302_runtime_accounting_root_closure.sql')

need('final TabController? controller;' in pill and 'controller: effectiveController' in pill,'AppPillTabBar does not explicitly bind its TabController')
need('DefaultTabController.maybeOf(context)' in pill and 'effectiveController.length != tabs.length' in pill,'AppPillTabBar is not guarded against a missing/mismatched controller')
users_tab = users[users.find('child: AppPillTabBar('):users.find('body: Consumer<AccessController>')]
need('controller: _tabs' in users_tab,'Users/Permissions TabBar still does not share the TabBarView controller')
need('controller: _tabs' in users[users.find('TabBarView('):],'Users/Permissions TabBarView no longer uses the explicit controller')
need('List<_CatalogItem> get _salesCatalog => _catalog;' in sales,'sales catalog is still filtered by definition currency')
need('DefinitionCurrencyResolver.matches' not in sales,'sales order UI still rejects cross-definition-currency items')
need("Cost currency" in sales and 'definitionCurrency' in sales,'sales picker does not expose item cost/definition currency')
need("'p_report_type': type," in repo,'accounting repository does not pass the requested report type directly')
need("type == 'trialBalance' ? 'generalLedger'" not in repo,'trial balance is still aliased to general ledger')
need("total(group, 'periodDebit')" in center and "total(group, 'periodCredit')" in center,'trial balance summary does not total period debit/credit')
need("currencyGroups" in center and "containsKey('USD')" in center and "containsKey('IQD')" in center,'accounting summary still mixes USD and IQD numerically')
need('drop trigger if exists trg_v764_sales_item_currency' in migration,'sales item currency guard was not removed')
need('drop trigger if exists trg_v764_purchase_item_currency' not in migration,'purchase currency guard must remain active')
need('sales_item_currency_mismatch' not in migration,'V23.0.2 preflight still rejects sales definition currency mismatch')
need("erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,c)" in migration,'sales preflight does not resolve revenue using invoice currency')
need("'costCurrency',v_cost_currency" in migration and "erp_phase2_account_guard(p_company_id,v_asset,'asset',v_cost_currency)" in migration and "erp_phase2_account_guard(p_company_id,v_expense,'expense',v_cost_currency)" in migration,'inventory/COGS accounts are not guarded in definition currency')
need('salesRevenueUsdAccountId' in migration and 'salesRevenueIqdAccountId' in migration and "erp_phase2_account_guard(p_company_id,v_revenue,'revenue',v_invoice_currency)" in migration,'sales revenue is not selected/guarded by invoice currency')
need('purchase_item_currency_mismatch' in migration,'purchase invoice no longer enforces definition/order currency')
for token in ('transfer_in', 'transfer_out', 'customer_receipt', 'supplier_payment'):
    need(migration.count(token) >= 3, f'cash balance functions do not consistently classify {token}')
need('erp_cloud_cash_account_balances' in migration and 'erp_cloud_cash_currency_summary' in migration and 'erp_cloud_cash_ledger_reconciliation' in migration,'cash balance/reconciliation closure functions are incomplete')

expected = {
    'dart_defines.json': '1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7',
    '.firebaserc': '003c25fc2e4659367989cfd4ca9703505abad207657fe6effc49c9317877098e',
    'firebase.json': 'ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a',
}
for rel, digest in expected.items():
    actual = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
    need(actual == digest, f'{rel} changed; runtime/deployment configuration must be preserved')

if errors:
    print('FAILED V23.0.2 runtime/accounting root closure')
    for error in errors:
        print('  -', error)
    sys.exit(1)

print('PASS V23.0.2 runtime/accounting root closure')
print('- release-web TabBar null crash controller mismatch closed')
print('- sales supports cross-definition-currency stock with invoice-currency revenue')
print('- purchase definition-currency guard retained')
print('- trial balance uses the real report and separates USD/IQD totals')
print('- cash transfer IN/OUT is reflected by balances and reconciliation')
print('- Supabase/Firebase runtime configuration hashes are unchanged')
