from pathlib import Path
from verification_text import normalized_text_sha256
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding='utf-8', errors='strict')

def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

migration_rel = 'supabase/migrations/20260808001500_r14_runtime_rpc_invoice_root_closure.sql'
migration = read(migration_rel)
master = read('lib/core/cloud/cloud_master_data_service.dart')
feature = read('lib/core/cloud/cloud_feature_command.dart')
readiness = read('lib/core/release/production_readiness_service.dart')
deploy = read('tool/deploy_r14_production.ps1')
package = read('package.json')
sales = read('lib/features/sales/workflow/repositories/sales_workflow_repository.dart')
purchases = read('lib/features/purchases/repositories/purchase_workflow_repository.dart')
v2302 = read('supabase/migrations/20260807213000_v2302_runtime_accounting_root_closure.sql')
v760 = read('supabase/migrations/20260807013000_v760_no_capitalization_accounting_integrity.sql')
r9_strict = read('supabase/migrations/20260807244000_r9_strict_master_permission_boundary.sql')
r15 = read('supabase/migrations/20260808014500_r15_canonical_state_reconciliation.sql')
r22 = read('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql') if (ROOT/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql').exists() else ''
r37 = read('supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql') if (ROOT/'supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql').exists() else ''
r35 = read('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql') if (ROOT/'supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql').exists() else ''
r27 = read('supabase/migrations/20260808162000_r27_complete_functional_closure.sql') if (ROOT/'supabase/migrations/20260808162000_r27_complete_functional_closure.sql').exists() else ''

# Runtime error 500: permission/payload reads must be total over legacy JSON.
need('erp_r14_try_boolean' in migration, 'safe legacy boolean parser missing')
need("public.erp_r14_try_boolean(r.payload->>'enabled',true)" in migration,
     'permission resolver still uses unsafe JSON boolean casting')
need("jsonb_typeof(p_payload)<>'object'" in migration,
     'master readable filter can still jsonb_each a non-object payload')
need('master_table_contract_invalid' in migration and 'to_regclass' in migration,
     'master list/get does not validate the table contract before dynamic SQL')
r14_master_tokens = [
    "'erp_r14_list_cloud_master_records'",
    "'erp_r14_get_cloud_master_record'",
    "'erp_r14_upsert_cloud_master_record'",
    "'erp_r14_soft_delete_cloud_master_record'",
    "'erp_r14_list_deleted_master_ids'",
]
r15_master_tokens = [
    "'erp_r15_list_cloud_master_records'",
    "'erp_r15_get_cloud_master_record'",
    "'erp_r15_upsert_cloud_master_record'",
    "'erp_r15_soft_delete_cloud_master_record'",
    "'erp_r15_list_deleted_master_ids'",
]
need(all(token in master for token in r14_master_tokens) or
     (all(token in master for token in r15_master_tokens) and
      (('select * from public.erp_r9_list_cloud_master_records($1,$2)' in r15) or ('select * from public.erp_r9_list_cloud_master_records(p_company_id,p_table)' in re.sub(r'\s+',' ',r15))) and
      (('select public.erp_r9_upsert_cloud_master_record($1,$2,$3,$4,$5)' in r15) or ('select public.erp_r9_upsert_cloud_master_record( p_company_id,p_table,p_record_id,p_data,p_expected_version)' in re.sub(r'\s+',' ',r15)))),
     'Flutter master gateway is not using a guarded R14/R15 master contract')
need('_readErrorMessage' in master, 'Flutter master reads do not expose PostgREST diagnostics')
need('erp_r14_master_table_contract_ok' in migration and
     all(col in migration for col in ["'company_id'","'id'","'data'","'version'","'updated_at'","'is_deleted'"]),
     'R14 master contract does not validate every column used by dynamic SQL')
need('erp_r14_master_contract_issues' in migration and 'masterContractsOk' in migration,
     'R14 runtime probe cannot report invalid legacy master table contracts')

# R9 trigger architecture: guarded generic RPC + revoked direct DML is the only
# place for user field filtering. Workflow-owned server writes must not be
# rewritten by a JSON trigger.
need('drop trigger if exists aa_r9_field_write_guard' in migration,
     'duplicated R9 JSON row guards are not removed')
need('v_any_user_field_changed boolean:=false' in migration,
     'commercial field guard does not distinguish user input from server-owned columns')
need('if not v_any_user_field_changed then return new; end if;' in migration,
     'workflow status/accounting updates can still require the generic update permission')
need(migration.index('if not v_any_user_field_changed then return new; end if;') <
     migration.index("v_base_permission:=case when TG_OP='INSERT'"),
     'base permission is checked before determining whether a user input changed')
need('revoke insert,update,delete on public.%I from authenticated' in r9_strict,
     'direct authenticated master DML is not revoked, so removing duplicate triggers would be unsafe')
need('v_guarded := public.erp_r9_guard_writable_master_json' in r9_strict,
     'guarded master RPC is not enforcing granular writes explicitly')

# Runtime error 404: browser uses an R14 facade and migration forces PostgREST
# schema cache reload after creating it.
r37_chain = (
    "'erp_r37_cloud_command'" in feature
    and 'create or replace function public.erp_r37_cloud_command' in r37
    and 'public.erp_r35_cloud_command($1,$2' in r37
    and 'create or replace function public.erp_r35_cloud_command' in r35
    and 'public.erp_r27_cloud_command($1,$2' in r35
    and 'create function public.erp_r27_cloud_command' in r27
    and 'public.erp_r14_phase26_cloud_command($1,$2' in r27
)
r14_or_r22_phase26 = (
    "'erp_r14_phase26_cloud_command'" in feature
    or ("'erp_r22_phase26_cloud_command'" in feature
        and 'create or replace function public.erp_r22_phase26_cloud_command' in r22
        and 'public.erp_r14_phase26_cloud_command($1,$2,$3)' in r22)
    or r37_chain
)
need(r14_or_r22_phase26,
     'CloudFeatureCommand is not using a verified successor of the retained R14 permission facade')
need('create or replace function public.erp_r14_phase26_cloud_command' in migration and
     'public.erp_r9_phase26_cloud_command($1,$2' in migration,
     'R14 Phase-26 facade does not delegate to the permission-aware R9 implementation')
need("notify pgrst,'reload schema'" in migration,
     'R14 migration does not explicitly reload the PostgREST schema cache')
need(("'erp_r14_runtime_contract_probe'" in feature or "'erp_r15_runtime_contract_probe'" in feature or "'erp_r16_runtime_contract_probe'" in feature or "'erp_r22_runtime_contract_probe'" in feature)
     and 'runtimeContractProbe' in feature,
     'Flutter does not expose the retained R14/R15/R16 contract or verified R22 runtime probe')
master_keys_ok = all(key in readiness for key in ['r14MasterList','r14MasterGet','r14MasterUpsert','r14MasterDelete']) or                  all(key in readiness for key in ['r15MasterList','r15MasterGet','r15MasterUpsert','r15MasterDelete'])
need(master_keys_ok, 'Production readiness does not require current guarded master contract keys')
need('masterContractsOk' in readiness, 'Production readiness does not require master contract health')
r14_readiness = all(key in readiness for key in ['r14Phase26','r14SalesApprove','r14PurchaseApprove'])
r22_readiness = all(key in readiness for key in ['r22Phase26','r22SalesApprove','r22PurchaseApprove','r22DirectPurchase'])
need(r14_readiness or (r22_readiness and 'create or replace function public.erp_r14_approve_sales_invoice' in r22
    and 'create or replace function public.erp_r14_approve_purchase_invoice' in r22),
    'Production readiness does not retain R14 guarantees through the verified R22 contract')

# Invoice approval: one current browser contract, explicit operation permission,
# latest V23.0.2 preflight and V7.6.2 integrity posting.
sales_current = "'erp_r14_approve_sales_invoice'" in sales or (
    "'erp_r22_approve_sales_invoice'" in sales
    and 'create or replace function public.erp_r14_approve_sales_invoice' in r22
    and 'erp_r22_approve_sales_invoice' in r22)
purchase_current = "'erp_r14_approve_purchase_invoice'" in purchases or (
    "'erp_r22_approve_purchase_invoice'" in purchases
    and 'create or replace function public.erp_r14_approve_purchase_invoice' in r22
    and 'erp_r22_approve_purchase_invoice' in r22)
need(sales_current, 'sales repository bypasses the R14 guarantee instead of using its verified R22 successor')
need(purchase_current, 'purchase repository bypasses the R14 guarantee instead of using its verified R22 successor')
for token in [
    'create or replace function public.erp_r14_approve_workflow_invoice',
    'erp_v767_invoice_policy_preflight',
    'erp_v762_approve_workflow_invoice',
    "'stage','preflight'",
    "'stage','posting'",
    "'sales.approve'",
    "'purchases.approve'",
]:
    need(token in migration, f'R14 approval contract missing {token}')

# Preserve the business policy from the beginning of the conversation.
need('drop trigger if exists trg_v764_sales_item_currency' in v2302,
     'sales definition-currency trigger is still active')
need('salesCrossDefinitionCurrencyAllowed' in v2302 and
     "erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,c)" in v2302,
     'sales invoice revenue/cost currency separation is not preserved')
need('purchase_item_currency_mismatch' in v2302,
     'purchase single-definition-currency guard is not preserved')
need("if jsonb_object_length(v_by_currency)=1 and v_by_currency ? v_currency" in v760 and
     "'mode','direct'" in v760,
     'same-currency purchase invoice is not normalized to direct Supplier/Inventory posting')

# Production deployment is DB-first and refuses unrelated pending migrations.
need('deploy:r14:production' in package and 'deploy_r14_production.ps1' in package,
     'R14 one-command production deployment is not exposed')
need('20260808001500_r14_runtime_rpc_invoice_root_closure.sql' in deploy and
     'Unexpected pending migrations. Refusing production push' in deploy,
     'R14 deploy script does not pin/refuse unexpected database migrations')
need(deploy.index('supabase db push --linked --yes') < deploy.index('firebase-tools deploy --only hosting'),
     'R14 deploy order does not apply Supabase before Firebase Hosting')
need('ReconfigureRuntime' not in deploy and 'dart_defines.json' in deploy,
     'R14 deploy script may reconfigure production runtime credentials')

# Production connection files are immutable across the runtime repair.
expected_hashes = {
    'dart_defines.json': '4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f',
    '.firebaserc': 'f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8',
    'firebase.json': 'ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a',
}
for rel, expected in expected_hashes.items():
    actual = normalized_text_sha256(ROOT / rel)
    need(actual == expected, f'local runtime/hosting baseline changed: {rel}')

# R14 must remain present and precede any later closure migrations.
migrations = sorted(p.name for p in (ROOT / 'supabase/migrations').glob('*.sql'))
need(Path(migration_rel).name in migrations,
     'R14 runtime closure migration is missing')
if '20260808014500_r15_canonical_state_reconciliation.sql' in migrations:
    need(migrations.index(Path(migration_rel).name) < migrations.index('20260808014500_r15_canonical_state_reconciliation.sql'),
         'R15 canonical state migration does not follow R14')

if errors:
    print('FAILED R14 runtime RPC/invoice root closure')
    for error in errors:
        print('  -', error)
    sys.exit(1)

print('PASS R14 runtime RPC/invoice root closure')
print('  - R14 master CRUD/tombstone contracts replace the failing R9 browser endpoint and validate legacy table structure')
print('  - workflow status/accounting writes no longer require unrelated *.update field permission')
print('  - Phase-26 browser contract is recreated behind an explicit PostgREST schema reload')
print('  - sales/purchase invoice approval uses one diagnosable R14 contract over V23.0.2/V7.6.2')
print('  - sales cross-definition currency and purchase single-currency accounting policies are retained')
print('  - Local Supabase/Firebase baseline hashes are unchanged')
