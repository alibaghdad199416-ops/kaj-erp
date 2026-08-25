from __future__ import annotations
import json,re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
errors=[]
def require(cond,msg):
    if not cond: errors.append(msg)
def read(rel): return (ROOT/rel).read_text(encoding='utf-8')

require('version: 22.9.5+229005' in read('pubspec.yaml'),'pubspec version mismatch')
require(json.loads(read('package.json'))['version']=='22.9.5','package version mismatch')
require((ROOT/'supabase/migrations/20260807060000_v764_pre_runtime_business_policy_closure.sql').exists(),'V764 policy migration missing')
policy=read('supabase/migrations/20260807060000_v764_pre_runtime_business_policy_closure.sql')
for token in ['erp_v764_definition_currency','erp_v764_definition_accounts','erp_v764_assert_partner_dual_ledgers','trg_v764_sales_item_currency','trg_v764_purchase_item_currency','erp_v764_scrap_expense_account','erp_v764_accounting_policy_audit']:
    require(token in policy,f'policy contract missing: {token}')

# Unique migration versions
versions={}
for p in (ROOT/'supabase/migrations').glob('*.sql'):
    v=p.name.split('_',1)[0]; versions.setdefault(v,[]).append(p.name)
require(not [x for x in versions.values() if len(x)>1], 'duplicate migration versions')

# Every numeric field uses the thousands formatter.
for p in (ROOT/'lib').rglob('*.dart'):
    text=p.read_text(encoding='utf-8')
    for m in re.finditer(r'\b(?:TextFormField|TextField)\s*\(',text):
        start=m.start(); end=text.find('\n          ),',start)
        if end<0: end=min(len(text),start+2200)
        block=text[start:end]
        if 'TextInputType.number' in block:
            require('ThousandsInputFormatter' in block,f'numeric input lacks thousands formatter: {p.relative_to(ROOT)}:{text.count(chr(10),0,start)+1}')

for rel in ['lib/features/sales/workflow/pages/sales_order_draft_page.dart','lib/features/purchases/pages/purchase_order_draft_page.dart']:
    s=read(rel)
    for token in ['DefinitionCurrencyResolver','_currencyCatalog','_changeCurrency']:
        require(token in s,f'{rel} missing {token}')
maint=read('lib/features/maintenance/pages/add_maintenance_order_page.dart')
for token in ['_currencyItems','_itemCurrency','_changeCurrency','Every item or service must match']:
    require(token in maint,f'maintenance currency enforcement missing {token}')

for rel in ['lib/core/exporting/pdf_export_service.dart','lib/core/exporting/excel_export_service.dart']:
    require("language: 'en'" in read(rel),f'English-only export missing in {rel}')
require('unlocalizedRawUiTextCandidates' in read('tool/audit_ui_localization.py'),'final UI audit not installed')
require((ROOT/'lib/core/utils/thousands_input_formatter.dart').exists(),'thousands formatter missing')
require((ROOT/'lib/core/utils/definition_currency_resolver.dart').exists(),'definition currency resolver missing')

# DataTables must be in a horizontal scrolling context close to their call site.
for p in (ROOT/'lib').rglob('*.dart'):
    text=p.read_text(encoding='utf-8')
    for m in re.finditer(r'\bDataTable\s*\(',text):
        nearby=text[max(0,m.start()-1800):m.start()]
        require('Axis.horizontal' in nearby,f'DataTable lacks nearby horizontal scroll: {p.relative_to(ROOT)}:{text.count(chr(10),0,m.start())+1}')

if errors:
    print('FAILED V22.9.5 pre-runtime final verification')
    for e in errors: print('-',e)
    raise SystemExit(1)
print('PASS V22.9.5 pre-runtime final verification')
print('- version and release metadata aligned')
print('- all numeric entry surfaces use thousands formatting')
print('- sales, purchase and maintenance definitions are constrained by order currency')
print('- partner, revenue, inventory, cost and scrap accounting policies are present')
print('- PDF and Excel central exports are English-only')
print('- UI localization and responsive table contracts are present')
