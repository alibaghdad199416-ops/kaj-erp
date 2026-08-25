#!/usr/bin/env python3
from pathlib import Path
import hashlib, re, sys

ROOT=Path(__file__).resolve().parents[1]
errors=[]

def read(rel): return (ROOT/rel).read_text(encoding='utf-8',errors='replace')
def need(cond,msg):
    if not cond: errors.append(msg)
def sha(rel): return hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()

expected={
 'dart_defines.json':'1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7',
 '.firebaserc':'003c25fc2e4659367989cfd4ca9703505abad207657fe6effc49c9317877098e',
 'firebase.json':'ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a',
}
for f,h in expected.items(): need(sha(f)==h,f'{f} changed from the user supplied production configuration')

catalog=read('lib/features/settings/access/models/field_permission_catalog.dart')
controller=read('lib/features/settings/access/controllers/access_controller.dart')
widget=read('lib/features/settings/access/widgets/permission_action.dart')
perm_catalog=read('lib/features/settings/access/models/permission_catalog.dart')
users=read('lib/features/settings/access/pages/users_page.dart')
for resource in ['users','dashboard','cars','inventory','warehouses','customers','suppliers','sales','purchases','maintenance','opportunities','installments','accounting','cashbox','expenses','fixed_assets','reports','settings']:
    need(f"key: '{resource}'" in catalog,f'granular field catalog missing {resource}')


# Every declared field permission must have an implementation surface. Shared
# widgets and the R9 DB masking migration are included where they own the field.
field_blocks={m.group(1): re.findall(r"FieldPermissionDefinition\('([^']+)'",m.group(2))
              for m in re.finditer(r"FieldPermissionResourceDefinition\(\s*key: '([^']+)'.*?fields: \[(.*?)\]\s*,\s*\)",catalog,re.S)}
strict_master_path='supabase/migrations/20260807244000_r9_strict_master_permission_boundary.sql'
finance_guard_path='supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql'
report_guard_path='supabase/migrations/20260807241000_r9_report_field_enforcement.sql'
dashboard_guard_path='supabase/migrations/20260807243000_r9_dashboard_search_permission_security.sql'
field_paths={
 'users':['lib/features/settings/access',strict_master_path],
 'dashboard':['lib/features/dashboard',dashboard_guard_path],
 'cars':['lib/features/inventory/cars','lib/features/inventory/widgets/inventory_account_fields.dart',strict_master_path],
 'inventory':['lib/features/inventory',strict_master_path],
 'warehouses':['lib/features/inventory',strict_master_path],
 'customers':['lib/features/business_partners/customers',strict_master_path],
 'suppliers':['lib/features/business_partners/suppliers',strict_master_path],
 'sales':['lib/features/sales',finance_guard_path,strict_master_path],
 'purchases':['lib/features/purchases','lib/features/sales/workflow/pages/order_details_dialog.dart',finance_guard_path,strict_master_path],
 'maintenance':['lib/features/maintenance',finance_guard_path],
 'opportunities':['lib/features/customer_service',dashboard_guard_path],
 'installments':['lib/features/accounting/installments',finance_guard_path,strict_master_path],
 'accounting':['lib/features/accounting',finance_guard_path,report_guard_path],
 'cashbox':['lib/features/accounting/cashbox',finance_guard_path,strict_master_path],
 'expenses':['lib/features/accounting/expenses',finance_guard_path,strict_master_path],
 'fixed_assets':['lib/features/accounting/fixed_assets',finance_guard_path],
 'reports':['lib/features/settings/reports','lib/features/accounting/pages/accounting_center_page.dart',report_guard_path],
 'settings':['lib/features/settings','lib/core/widgets/app_top_navigation.dart','lib/core/widgets/app_workspace_top_bar.dart'],
}
for resource,fields in field_blocks.items():
    chunks=[]
    for rel in field_paths.get(resource,[]):
        path=ROOT/rel
        if path.is_dir():
            chunks.extend(x.read_text(encoding='utf-8',errors='replace') for x in path.rglob('*.dart'))
        elif path.exists():
            chunks.append(path.read_text(encoding='utf-8',errors='replace'))
    implementation='\n'.join(chunks)
    missing=[field for field in fields if not re.search(rf"['\"]{re.escape(field)}['\"]",implementation)]
    need(not missing,f'{resource} field permissions without implementation surface: '+', '.join(missing))
need('FieldPermissionCatalog.all' in perm_catalog,'field permission catalog is not merged into the permission catalog')
need('canViewField(' in controller and 'canEditField(' in controller and 'hasRestrictedFields(' in controller,
     'access controller granular field policy methods missing')
need('class FieldPermissionControl' in widget and 'class FieldPermissionVisibility' in widget,
     'reusable field permission widgets missing')
need('customPermissions' in users and 'controller.permissions' in users,
     'user permission UI does not expose the complete generated permission catalog')
for code in ['warehouses.view','warehouses.create','warehouses.update','warehouses.delete']:
    need(f"code: '{code}'" in perm_catalog,f'warehouse base permission missing: {code}')

# Display cards must respect field visibility, not only edit forms.
for f in [
 'lib/features/inventory/cars/widgets/car_card.dart',
 'lib/features/inventory/widgets/inventory_card.dart',
 'lib/features/business_partners/customers/widgets/customer_card.dart',
 'lib/features/business_partners/suppliers/widgets/supplier_card.dart',
 'lib/features/customer_service/widgets/opportunity_card.dart',
 'lib/features/purchases/widgets/purchase_card.dart',
 'lib/features/sales/widgets/sale_card.dart',
 'lib/features/accounting/cashbox/widgets/cash_transaction_card.dart',
 'lib/features/accounting/expenses/widgets/expense_card.dart',
]:
    need('FieldPermissionVisibility' in read(f),f'field-level display visibility missing in {f}')
users_compact = re.sub(r'\s+', '', users)
need('controller:_tabs' in users_compact and 'TabBarView(controller:_tabs' in users_compact,
     'users/permissions TabController runtime null closure regressed')

# Literal base permissions referenced by field/action widgets must exist in the catalog.
known_codes=set(re.findall(r"code:\s*'([^']+)'",perm_catalog))
used_codes=set()
for dart in (ROOT/'lib').rglob('*.dart'):
    text=dart.read_text(encoding='utf-8',errors='replace')
    for pattern in [r"viewPermission:\s*'([^']+)'",r"writePermission:\s*'([^']+)'",r"hasPermission\(\s*'([^']+)'\s*\)"]:
        used_codes.update(re.findall(pattern,text))
undefined=sorted(code for code in used_codes if '.fields.' not in code and code not in known_codes)
need(not undefined,'undefined literal base permissions: '+', '.join(undefined))

# Main editable module surfaces must consume granular permissions.
field_files=[
 'lib/features/sales/workflow/pages/sales_order_draft_page.dart',
 'lib/features/purchases/pages/purchase_order_draft_page.dart',
 'lib/features/maintenance/pages/add_maintenance_order_page.dart',
 'lib/features/inventory/pages/add_inventory_page.dart',
 'lib/features/inventory/cars/pages/add_car_page.dart',
 'lib/features/inventory/cars/pages/edit_car_page.dart',
 'lib/features/business_partners/customers/pages/add_customer_page.dart',
 'lib/features/business_partners/customers/pages/edit_customer_page.dart',
 'lib/features/business_partners/suppliers/pages/add_supplier_page.dart',
 'lib/features/customer_service/pages/add_opportunity_page.dart',
 'lib/features/accounting/cashbox/pages/add_cash_transaction_page.dart',
 'lib/features/accounting/cashbox/pages/cash_account_form.dart',
 'lib/features/accounting/cashbox/pages/cashbox_page.dart',
 'lib/features/accounting/pages/add_journal_entry_page.dart',
 'lib/features/accounting/expenses/pages/add_expense_page.dart',
 'lib/features/accounting/fixed_assets/fixed_assets_page.dart',
 'lib/features/accounting/pages/accounting_center_page.dart',
 'lib/features/inventory/pages/warehouse_management_page.dart',
 'lib/features/inventory/pages/transfer_stock_page.dart',
 'lib/features/inventory/pages/product_warehouse_transfers_page.dart',
 'lib/features/inventory/cars/pages/car_warehouse_transfers_page.dart',
 'lib/features/settings/pages/settings_page.dart',
 'lib/features/settings/reports/pages/reports_page.dart',
]
for f in field_files:
    text=read(f)
    need('FieldPermission' in text or 'canViewField(' in text or 'canEditField(' in text,
         f'granular field policy not connected to {f}')

periods=read('lib/features/settings/operational_periods/pages/operational_periods_page.dart')
recycle=read('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart')
need("'operationalPeriods'" in periods and 'canEditField(' in periods,'operational periods field policy missing')
need("'recycleBin'" in recycle and 'canViewField(' in recycle and 'canEditField(' in recycle,'recycle bin field policy missing')

# Commercial legacy tab must not bypass the authoritative order workflow.
purchases_old=read('lib/features/purchases/pages/purchases_page.dart')
sales_old=read('lib/features/sales/pages/sales_page.dart')
purchase_card=read('lib/features/purchases/widgets/purchase_card.dart')
sale_card=read('lib/features/sales/widgets/sale_card.dart')
need('AddPurchasePage' not in purchases_old and 'VoidCallback? onEdit' in purchase_card and 'if (onEdit != null)' in purchase_card,
     'legacy purchase invoice tab can still create/edit outside purchase workflow')
need('EditSalePage' not in sales_old and 'ResellCarPage' not in sales_old and 'VoidCallback? onEdit' in sale_card and 'if (onEdit != null)' in sale_card,
     'legacy sales invoice tab can still mutate outside sales workflow')

# 20-decimal FX is retained from UI through persisted DB columns.
for f in [
 'lib/features/accounting/cashbox/pages/cashbox_page.dart',
 'lib/core/finance/invoice_payment_batch_dialog.dart',
 'lib/features/sales/workflow/pages/sales_order_draft_page.dart',
 'lib/features/purchases/pages/purchase_order_draft_page.dart',
]:
    text=read(f)
    need('decimalDigits: 20' in text,f'20-decimal exchange-rate input missing in {f}')
fx=read('supabase/migrations/20260807233500_r9_fx_precision_and_field_guards.sql')
for table in ['erp_sales_orders_cloud','erp_purchase_orders_cloud','erp_payment_settlement_plans','erp_maintenance_orders','erp_maintenance_payments']:
    need(table in fx and 'numeric(38,20)' in fx,f'20-decimal FX storage migration missing {table}')
need('erp_r9_guard_input_fields' in fx and 'erp_cloud_user_can_edit_field' in fx,
     'database field-write guard missing')
need('revoke insert,update,delete on public.erp_sales_orders_cloud from authenticated' in fx and
     'revoke insert,update,delete on public.erp_purchase_orders_cloud from authenticated' in fx,
     'direct authenticated DML can bypass commercial RPC workflow')
for trig in ['trg_r9_sales_order_field_guard','trg_r9_purchase_order_field_guard','trg_r9_maintenance_order_field_guard']:
    need(trig in fx,f'database granular field trigger missing: {trig}')

strict_master=read(strict_master_path)
backend_field=read('supabase/migrations/20260807235000_r9_field_permission_backend_enforcement.sql')+strict_master
need('erp_r9_filter_readable_json' in backend_field and 'erp_r9_guard_writable_json' in backend_field,
     'backend readable/writable field masking helpers missing')
need('erp_r9_list_cloud_master_records' in backend_field and 'erp_r9_get_cloud_master_record' in backend_field,
     'restricted master-data reads can bypass field masking')
need('erp_access_cloud_snapshot' in backend_field and "'users'" in backend_field,
     'restricted user snapshot field masking missing')

role_migration=read('supabase/migrations/20260807232000_r9_granular_field_permissions.sql')
need('erp_set_cloud_role_permissions' in role_migration and "'permissions'" in role_migration,
     'role field permissions are not lazily persisted')
need('erp_cloud_user_can_view_field' in role_migration and 'erp_cloud_user_can_edit_field' in role_migration,
     'SQL field permission helpers missing')

fixed_asset_time=read('supabase/migrations/20260807234500_r9_fixed_asset_operational_timestamp.sql')
need('erp_post_fixed_asset_depreciation_at' in fixed_asset_time and 'p_effective_at timestamptz' in fixed_asset_time,
     'fixed-asset depreciation does not preserve user-selected operational timestamp')

# CloudMasterDataService must never send an unsupported table to the masked
# reader RPC. This catches runtime-only failures such as a repository using a
# table that was omitted from erp_r9_master_resource_for_table().
master_service=read('lib/core/cloud/cloud_master_data_service.dart')
backend=read('supabase/migrations/20260807235000_r9_field_permission_backend_enforcement.sql')+strict_master
service_tables=set()
for dart in (ROOT/'lib').rglob('*.dart'):
    text=dart.read_text(encoding='utf-8',errors='replace')
    if 'CloudMasterDataService' not in text:
        continue
    constants=dict(re.findall(r"static const String\s+(\w+)\s*=\s*'([^']+)'",text))
    service_tables.update(re.findall(r"(?:_cloud|CloudMasterDataService\.instance)\.(?:list|listWhere|getById|upsert|delete)\(\s*'([^']+)'",text))
    for variable in re.findall(r"(?:_cloud|CloudMasterDataService\.instance)\.(?:list|listWhere|getById|upsert|delete)\(\s*(\w+)",text):
        if variable in constants:
            service_tables.add(constants[variable])
for table in sorted(service_tables):
    need(f"when '{table}' then" in backend,f'CloudMasterDataService table unsupported by masked RPC: {table}')
need("when 'erp_purchases' then 'purchases'" in backend and "when 'erp_purchase_items' then 'purchases'" in backend,
     'legacy purchase archive tables are not routed through the masked R9 reader')
need("when 'purchases' then case" in backend and "when 'invoiceNumber' then 'invoice'" in backend,
     'legacy purchase archive fields are not mapped to granular purchase permissions')

# Finance/report endpoints must be server-side guarded, not only hidden in UI.
finance_guard=read('supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql')
report_guard=read('supabase/migrations/20260807241000_r9_report_field_enforcement.sql')
for fn in [
 'erp_r9_save_cloud_cash_account','erp_r9_post_cloud_cash_transaction','erp_r9_transfer_cloud_cash',
 'erp_r9_post_cloud_expense','erp_r9_save_cloud_ledger_account','erp_r9_post_cloud_manual_journal',
 'erp_r9_update_cloud_manual_journal','erp_r9_list_cloud_sales_workflow_orders',
 'erp_r9_list_cloud_purchase_workflow_orders','erp_r9_list_cloud_maintenance_orders',
]:
    need(f'function public.{fn}' in finance_guard,f'R9 server field guard missing: {fn}')
for fn in [
 'erp_r9_cloud_trial_balance','erp_r9_cloud_detailed_accounting_report','erp_r9_cloud_cash_flow_hierarchy',
 'erp_r9_cloud_reports_summary','erp_r9_cloud_contextual_report','erp_r9_cloud_model_report',
 'erp_r9_cloud_customer_service_report','erp_r9_cloud_report_audit',
]:
    need(f'function public.{fn}' in report_guard,f'R9 report field guard missing: {fn}')
need('erp_r9_can_view_report_module' in report_guard and "when 'sales' then 'sales.view'" in report_guard and "when 'purchases' then 'purchases.view'" in report_guard,
     'contextual reports do not enforce the selected module view permission at the server boundary')

reports_ui=read('lib/features/settings/reports/pages/reports_page.dart')
for field in ['contextualDetails','auditDetails','summaryCards','monthlyTrend','netProfit','receivablesPayables','cashBalances','inventoryValue']:
    need(f"'{field}'" in reports_ui,f'report UI granular visibility missing: {field}')
need("_reportValue('contextualDetails', _buildContextualDetails())" in reports_ui and
     "_reportValue('auditDetails', _buildExecutionActivity())" in reports_ui,
     'report contextual/audit sections use the wrong field permission')

# Operational date/time must be user-selectable in financial entry points.
cash_tx=read('lib/features/accounting/cashbox/pages/add_cash_transaction_page.dart')
journal=read('lib/features/accounting/pages/add_journal_entry_page.dart')
need('_pickTransactionDateTime' in cash_tx and "'operationalDate'" in cash_tx,
     'cash voucher operational date/time selector missing')
need('_pickEntryDateTime' in journal and "'entryDate'" in journal,
     'manual journal date/time selector missing')

# Source-side null crash hardening.
need('cloudUser.email!' not in controller,'persisted auth restore still force-unwraps nullable cloud email')
need('_currency = value!' not in journal,'journal currency dropdown still force-unwraps nullable value')


# R9 backend read/write closure: restricted fields must not be bypassable via
# direct Supabase table reads or legacy unfiltered finance/report RPCs.
finance_migration=read('supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql')
report_migration=read('supabase/migrations/20260807241000_r9_report_field_enforcement.sql')
master_migration=read('supabase/migrations/20260807235000_r9_field_permission_backend_enforcement.sql')+strict_master
master_service=read('lib/core/cloud/cloud_master_data_service.dart')
r14_runtime=read('supabase/migrations/20260808001500_r14_runtime_rpc_invoice_root_closure.sql')
r22_runtime=read('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql') if (ROOT/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql').exists() else ''
r15_runtime=read('supabase/migrations/20260808014500_r15_canonical_state_reconciliation.sql') if (ROOT/'supabase/migrations/20260808001500_r14_runtime_rpc_invoice_root_closure.sql').exists() else ''

for token in [
 'erp_r9_list_cloud_ledger_accounts','erp_r9_list_journal_lines','erp_r9_list_fixed_assets',
 'erp_r9_save_fixed_asset','erp_r9_save_cloud_cash_account','erp_r9_post_cloud_cash_transaction',
 'erp_r9_transfer_cloud_cash','erp_r9_post_cloud_expense','erp_r9_save_cloud_ledger_account',
 'erp_r9_post_cloud_manual_journal','erp_r9_update_cloud_manual_journal',
 'erp_r9_list_cloud_sales_workflow_orders','erp_r9_list_cloud_purchase_workflow_orders',
 'erp_r9_list_cloud_maintenance_orders','erp_r9_get_cloud_maintenance_order_lines',
 'erp_r9_post_fixed_asset_depreciation_at'
]:
    need(token in finance_migration,f'R9 backend finance field boundary missing {token}')
for token in [
 'erp_r9_cloud_trial_balance','erp_r9_cloud_account_balance_before','erp_r9_cloud_receivables_payables',
 'erp_r9_cloud_partner_subledger_details_v2','erp_r9_cloud_partner_subledger_documents',
 'erp_r9_cloud_detailed_accounting_report','erp_r9_cloud_cash_flow_hierarchy',
 'erp_r9_cloud_reports_summary','erp_r9_cloud_contextual_report','erp_r9_cloud_model_report',
 'erp_r9_cloud_customer_service_report','erp_r9_cloud_report_audit'
]:
    need(token in report_migration,f'R9 server-side report permission boundary missing {token}')
need("cmd='SELECT'" in finance_migration and "fields.restrict" in finance_migration,
     'R9 does not remove permissive direct SELECT policies for restricted resources')
need('aa_r9_field_write_guard' in finance_migration and 'erp_cash_transactions' in finance_migration and 'erp_expenses' in finance_migration,
     'R9 JSON write guard is not attached to finance master tables')

# Every literal table used by CloudMasterDataService must have a server mapping.
cloud_tables=set()
for dart in (ROOT/'lib').rglob('*.dart'):
    text=dart.read_text(encoding='utf-8',errors='replace')
    for m in re.finditer(r"_cloud\.(?:list|listWhere|getById|upsert|delete)\(\s*['\"](erp_[a-z0-9_]+)['\"]",text):
        cloud_tables.add(m.group(1))
for table in sorted(cloud_tables):
    need(f"when '{table}'" in master_migration,
         f'CloudMasterDataService table lacks R9 server resource mapping: {table}')
uses_r9_master_reads = "'erp_r9_list_cloud_master_records'" in master_service and "'erp_r9_get_cloud_master_record'" in master_service
uses_r14_master_reads = "'erp_r14_list_cloud_master_records'" in master_service and "'erp_r14_get_cloud_master_record'" in master_service
r14_wraps_r9_reads = (
    'create or replace function public.erp_r14_list_cloud_master_records' in r14_runtime
    and 'select * from public.erp_r9_list_cloud_master_records($1,$2)' in r14_runtime
    and 'create or replace function public.erp_r14_get_cloud_master_record' in r14_runtime
    and 'select public.erp_r9_get_cloud_master_record($1,$2,$3)' in r14_runtime
)
uses_r15_master_reads = "'erp_r15_list_cloud_master_records'" in master_service and "'erp_r15_get_cloud_master_record'" in master_service
r15_wraps_r9_reads = (
    'create or replace function public.erp_r15_list_cloud_master_records' in r15_runtime
    and ('select * from public.erp_r9_list_cloud_master_records($1,$2)' in r15_runtime or 'select * from public.erp_r9_list_cloud_master_records(p_company_id,p_table)' in re.sub(r'\s+',' ',r15_runtime))
    and 'create or replace function public.erp_r15_get_cloud_master_record' in r15_runtime
    and ('select public.erp_r9_get_cloud_master_record($1,$2,$3)' in r15_runtime or 'select public.erp_r9_get_cloud_master_record(p_company_id,p_table,p_record_id)' in re.sub(r'\s+',' ',r15_runtime))
)
need(uses_r9_master_reads or (uses_r14_master_reads and r14_wraps_r9_reads) or
     (uses_r15_master_reads and r15_wraps_r9_reads),
     'CloudMasterDataService can bypass masked R9/R14/R15 read RPCs')

uses_r9_master_writes = "'erp_r9_upsert_cloud_master_record'" in master_service and "'erp_r9_soft_delete_cloud_master_record'" in master_service
uses_r14_master_writes = "'erp_r14_upsert_cloud_master_record'" in master_service and "'erp_r14_soft_delete_cloud_master_record'" in master_service
uses_r15_master_writes = "'erp_r15_upsert_cloud_master_record'" in master_service and "'erp_r15_soft_delete_cloud_master_record'" in master_service
r14_wraps_r9_writes = (
    'create or replace function public.erp_r14_upsert_cloud_master_record' in r14_runtime
    and 'select public.erp_r9_upsert_cloud_master_record($1,$2,$3,$4,$5)' in r14_runtime
    and 'create or replace function public.erp_r14_soft_delete_cloud_master_record' in r14_runtime
    and 'select public.erp_r9_soft_delete_cloud_master_record($1,$2,$3,$4)' in r14_runtime
)
r15_wraps_r9_writes = (
    'create or replace function public.erp_r15_upsert_cloud_master_record' in r15_runtime
    and ('select public.erp_r9_upsert_cloud_master_record($1,$2,$3,$4,$5)' in r15_runtime or 'select public.erp_r9_upsert_cloud_master_record( p_company_id,p_table,p_record_id,p_data,p_expected_version)' in re.sub(r'\s+',' ',r15_runtime))
    and 'create or replace function public.erp_r15_soft_delete_cloud_master_record' in r15_runtime
    and ('select public.erp_r9_soft_delete_cloud_master_record($1,$2,$3,$4)' in r15_runtime or 'return public.erp_r9_soft_delete_cloud_master_record( p_company_id,p_table,p_record_id,p_expected_version)' in re.sub(r'\s+',' ',r15_runtime))
)
need(uses_r9_master_writes or (uses_r14_master_writes and r14_wraps_r9_writes) or
     (uses_r15_master_writes and r15_wraps_r9_writes),
     'CloudMasterDataService can bypass guarded R9/R14/R15 write RPCs')
need(("'erp_r14_list_deleted_master_ids'" in master_service and
      'create or replace function public.erp_r14_list_deleted_master_ids' in r14_runtime) or
     ("'erp_r15_list_deleted_master_ids'" in master_service and
      'create or replace function public.erp_r15_list_deleted_master_ids' in r15_runtime),
     'master tombstone reconciliation bypasses the R9/R14/R15 permission boundary')
need("'erp_upsert_cloud_master_record'" not in master_service and "'erp_soft_delete_cloud_master_record'" not in master_service,
     'CloudMasterDataService still references legacy unguarded master writes')
for token in [
 'erp_r9_master_required_permission','erp_r9_master_field_for_table_key',
 'erp_r9_filter_readable_master_json','erp_r9_guard_writable_master_json',
 'erp_r9_upsert_cloud_master_record','erp_r9_soft_delete_cloud_master_record',
 'Unknown keys are default-deny','pg_policies','r9_strict_select'
]:
    need(token in strict_master,f'R9 strict master boundary missing {token}')
need("erp_r9_master_required_permission(p_table,'view')" in strict_master,
     'SECURITY DEFINER master reads do not enforce module view permission')
need('revoke all on function public.erp_upsert_cloud_master_record' in strict_master and
     'revoke all on function public.erp_soft_delete_cloud_master_record' in strict_master,
     'legacy unguarded master write RPCs remain executable')
need("cmd in ('SELECT','ALL')" in strict_master and 'drop policy if exists' in strict_master and
     "not public.erp_cloud_user_has_permission(company_id,%L)" in strict_master,
     'strict RLS does not remove historical permissive read policies and force restricted users through masking RPCs')
need('revoke insert,update,delete on public.%I from authenticated' in strict_master,
     'direct authenticated JSON DML is not revoked')

# No user-facing Dart code may directly select protected field-level tables.
protected_tables={
 'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses','erp_inventory',
 'erp_inventory_groups','erp_product_images','erp_car_warehouse_transfers','erp_warehouse_transfers',
 'erp_warehouse_transfer_items','erp_warehouse_stock','erp_inventory_movements','erp_cash_accounts',
 'erp_cash_transactions','erp_expenses','erp_journal_entries','erp_journal_lines','erp_installments','erp_sales',
 'erp_fixed_assets','erp_sales_orders_cloud','erp_sales_order_items_cloud','erp_purchase_orders_cloud',
 'erp_purchase_order_items_cloud','erp_maintenance_orders','erp_maintenance_parts','erp_maintenance_payments'
}
for dart in (ROOT/'lib').rglob('*.dart'):
    text=dart.read_text(encoding='utf-8',errors='replace')
    for table in protected_tables:
        need(re.search(r"\.from\(['\"]"+re.escape(table)+r"['\"]\)",text) is None,
             f'direct protected-table read remains in {dart.relative_to(ROOT)}: {table}')

# Client must use only the guarded R9 finance/report endpoints once legacy
# execute rights are revoked in the migrations.
legacy_rpc_names={
 'erp_list_cloud_ledger_accounts','erp_cloud_cash_account_balances','erp_cloud_cash_ledger_reconciliation',
 'erp_cloud_cash_currency_summary','erp_post_cloud_cash_transaction','erp_save_cloud_cash_account',
 'erp_post_cloud_expense','erp_save_fixed_asset','erp_post_fixed_asset_depreciation_at',
 'erp_post_cloud_manual_journal','erp_update_cloud_manual_journal','erp_save_cloud_ledger_account',
 'erp_list_cloud_sales_workflow_orders','erp_list_cloud_purchase_workflow_orders',
 'erp_list_cloud_maintenance_orders','erp_get_cloud_maintenance_order_lines','erp_list_cloud_maintenance_eligible_cars',
 'erp_cloud_trial_balance','erp_cloud_account_balance_before','erp_cloud_receivables_payables',
 'erp_cloud_partner_subledger_details_v2','erp_cloud_partner_subledger_documents',
 'erp_cloud_detailed_accounting_report','erp_cloud_cash_flow_hierarchy','erp_cloud_reports_summary',
 'erp_cloud_contextual_report','erp_cloud_model_report','erp_cloud_customer_service_report','erp_cloud_report_audit'
}
for dart in (ROOT/'lib').rglob('*.dart'):
    text=dart.read_text(encoding='utf-8',errors='replace')
    for rpc in legacy_rpc_names:
        need(re.search(r"['\"]"+re.escape(rpc)+r"['\"]",text) is None,
             f'legacy unguarded RPC still called by {dart.relative_to(ROOT)}: {rpc}')

# R9 dashboard/search/legacy JSON-command/settings closure.
latest_security=read('supabase/migrations/20260807243000_r9_dashboard_search_permission_security.sql')
cloud_command=read('lib/core/cloud/cloud_feature_command.dart')
dashboard_repo=read('lib/features/dashboard/data/dashboard_repository.dart')
search_repo=read('lib/features/global_search/repositories/global_search_repository.dart')
system_monitor=read('lib/features/settings/system_monitor/pages/system_monitor_page.dart')
settings_hub=read('lib/features/settings/pages/settings_hub_page.dart')
settings_page=read('lib/features/settings/pages/settings_page.dart')
for token in [
 'erp_r9_cloud_dashboard_snapshot','erp_r9_cloud_global_search',
 'erp_r9_system_monitor_command','erp_r9_phase26_cloud_command',
 'erp_r9_can_edit_settings_field'
]:
    need(token in latest_security,f'R9 late security boundary missing {token}')
r49_profit = read('supabase/migrations/20260810110000_r49_accounting_profit_installment_surface_closure.sql')
uses_permission_filtered_dashboard = (
    "'erp_r9_cloud_dashboard_snapshot'" in dashboard_repo
    or ("'erp_r49_cloud_dashboard_snapshot'" in dashboard_repo
        and 'v:=public.erp_r9_cloud_dashboard_snapshot(p_company_id,p_reference_day);' in r49_profit
        and "if v ? 'netProfitByCurrency'" in r49_profit)
)
need(uses_permission_filtered_dashboard and
     "pendingSyncOperations: _i(row['pendingSyncOperations'])" in dashboard_repo,
     'dashboard is not using the permission-filtered R9 chain')
r49_search = read('supabase/migrations/20260810080000_r49_independent_delivery_search_traceability.sql')
uses_server_search = (
    "'erp_r9_cloud_global_search'" in search_repo
    or ("'erp_r49_cloud_global_search'" in search_repo
        and 'create or replace function public.erp_r49_cloud_global_search' in r49_search
        and 'is_active_company_member(p_company_id)' in r49_search
        and "entity_type='opportunities'" in r49_search)
)
need(uses_server_search,
     'global search is not using a server-side tenant-safe canonical RPC')
uses_r9_phase26 = "'erp_r9_phase26_cloud_command'" in cloud_command
uses_r14_phase26 = "'erp_r14_phase26_cloud_command'" in cloud_command
uses_r22_phase26 = "'erp_r22_phase26_cloud_command'" in cloud_command
uses_r37_cloud = "'erp_r37_cloud_command'" in cloud_command
r14_wraps_r9 = (
    'create or replace function public.erp_r14_phase26_cloud_command' in r14_runtime
    and 'public.erp_r9_phase26_cloud_command($1,$2' in r14_runtime
)
r22_wraps_r14 = (
    'create or replace function public.erp_r22_phase26_cloud_command' in r22_runtime
    and 'public.erp_r14_phase26_cloud_command($1,$2,$3)' in r22_runtime
    and r14_wraps_r9
)
# R37 is the current browser-facing facade. Verify its complete server-side
# wrapper chain rather than forcing the client back to an older RPC name:
# R37 -> R35 -> R27 -> R14 -> R9 -> protected legacy Phase-26 command.
r37_runtime = read('supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql').lower()
r35_runtime = read('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql').lower()
r27_runtime = read('supabase/migrations/20260808162000_r27_complete_functional_closure.sql').lower()
r37_wraps_r9 = (
    uses_r37_cloud
    and 'create or replace function public.erp_r37_cloud_command' in r37_runtime
    and 'public.erp_r35_cloud_command($1,$2' in r37_runtime
    and 'create or replace function public.erp_r35_cloud_command' in r35_runtime
    and 'public.erp_r27_cloud_command($1,$2' in r35_runtime
    and 'create function public.erp_r27_cloud_command' in r27_runtime
    and 'public.erp_r14_phase26_cloud_command($1,$2' in r27_runtime
    and r14_wraps_r9
)
stripped_phase26 = (cloud_command
    .replace('erp_r9_phase26_cloud_command','')
    .replace('erp_r14_phase26_cloud_command','')
    .replace('erp_r22_phase26_cloud_command','')
    .replace('erp_r37_cloud_command',''))
need((uses_r9_phase26 or (uses_r14_phase26 and r14_wraps_r9) or (uses_r22_phase26 and r22_wraps_r14) or r37_wraps_r9) and
     'erp_phase26_cloud_command' not in stripped_phase26,
     'CloudFeatureCommand can bypass the protected Phase-26 permission facade chain')
need('revoke execute on function public.erp_phase26_cloud_command(text,text,jsonb) from authenticated' in latest_security,
     'legacy Phase-26 command remains directly executable by browser users')
need("when 'opportunities' then case" in master_migration and "when 'opportunityNumber' then 'opportunityNumber'" in master_migration,
     'opportunity JSON is not mapped into server-side granular field enforcement')
need("v_item.key not in (" in master_migration and 'business properties are default-deny' in master_migration,
     'unknown JSON business keys are not default-deny in restricted mode')
need("('erp_installments','installments')" in master_migration and "when 'installments' then case" in master_migration,
     'installments are not protected as their own granular resource')
for field in ['systemMonitor','systemHealth','systemMetrics','systemSyncDetails','productionReadiness','retryFailedJobs']:
    need(f"'{field}'" in system_monitor or (field=='systemMonitor' and f"'{field}'" in settings_hub),
         f'system-monitor settings field not wired: {field}')
for field in ['companyProfile','branches','currencies','financialDefaults','language']:
    need(f"'{field}'" in settings_page,f'granular settings UI missing {field}')
need('erp_save_cloud_company_settings' in latest_security and
     'erp_save_cloud_branch' in latest_security and
     'erp_save_cloud_currency' in latest_security,
     'granular settings writes are not enforced by Supabase')

# Source-package cleanliness is verified separately by verify:package.

if errors:
    print('FAILED R9 complete closure')
    for e in errors: print('  -',e)
    sys.exit(1)
print('PASS R9 complete closure')
print('- production Supabase/Firebase configuration hashes unchanged')
print('- granular field permissions are catalogued, assignable, UI-enforced and server-enforced across master, finance, commercial and report reads/writes')
print('- legacy invoice tabs no longer bypass authoritative order workflows')
print('- FX precision is 20 decimals in key UI inputs and persisted workflow/payment columns')
print('- operational date/time and null-runtime hardening retained')
print('- source-package cleanliness is delegated to verify:package')
