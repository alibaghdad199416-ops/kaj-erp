from pathlib import Path
from verification_text import normalized_text_sha256
import sys

ROOT = Path(__file__).resolve().parents[1]
errors=[]

def read(rel):
    return (ROOT/rel).read_text(encoding='utf-8', errors='strict')

def need(cond,msg):
    if not cond: errors.append(msg)

migration_rel='supabase/migrations/20260808014500_r15_canonical_state_reconciliation.sql'
m=read(migration_rel)
master=read('lib/core/cloud/cloud_master_data_service.dart')
readiness=read('lib/core/release/production_readiness_service.dart')
feature=read('lib/core/cloud/cloud_feature_command.dart')
access=read('lib/features/settings/access/controllers/access_controller.dart')
cash_model=read('lib/features/accounting/cashbox/models/cash_account_model.dart')
cash_form=read('lib/features/accounting/cashbox/pages/cash_account_form.dart')
package=read('package.json')
deploy=read('tool/deploy_r15_production.ps1') if (ROOT/'tool/deploy_r15_production.ps1').exists() else ''

# Tombstone precedence and anti-resurrection.
for token in [
    'erp_r15_pending_delete_exists',
    'deleted_master_record_requires_explicit_restore',
    'expected_version_required',
    'stale_master_record',
    "public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id)",
]: need(token in m, f'missing canonical tombstone/version contract: {token}')
need('restored_at is null' in m,
     'recycle-bin tombstone precedence does not respect explicit restore')
need("and u.purged_at is null" not in m,
     'permanently purged deletion history can still be overridden by a stale payload')
need("'erp_r15_list_cloud_master_records'" in master and
     "'erp_r15_get_cloud_master_record'" in master and
     "'erp_r15_upsert_cloud_master_record'" in master and
     "'erp_r15_soft_delete_cloud_master_record'" in master,
     'Flutter master gateway is not fully on R15')
need('_knownVersions' in master and '_rememberVersion' in master and
     "_knownVersions[_versionKey(table, id)]" in master,
     'Flutter does not preserve server versions across model conversion')
need('deleted_master_record_requires_explicit_restore' in master and 'stale_master_record' in master,
     'Flutter does not explain stale/deleted write rejection')
for signature in [
    'erp_r15_list_cloud_master_records(\n  p_company_id uuid,p_table text',
    'erp_r15_get_cloud_master_record(\n  p_company_id uuid,p_table text,p_record_id text',
    'erp_r15_upsert_cloud_master_record(\n  p_company_id uuid,p_table text,p_record_id text,p_data jsonb,p_expected_version bigint default null',
    'erp_r15_soft_delete_cloud_master_record(\n  p_company_id uuid,p_table text,p_record_id text,p_expected_version bigint default null',
    'erp_r15_list_deleted_master_ids(\n  p_company_id uuid,p_table text',
]:
    need(signature in m, 'R15 browser RPC parameters are not explicitly named: ' + signature.split('(')[0])
need(m.count('create or replace function public.erp_r15_soft_delete_cloud_master_record(')==1,
     'R15 soft-delete RPC is defined more than once in the same migration')

# Current accounting policy wins over old sync payloads.
for token in [
    'erp_r15_enforce_account_policy',
    'erp_v763_forbidden_capitalization_account(new.code,new.name)',
    "new.is_active:=false",
    "حساب تاريخي متوقف - رسملة ملغاة",
    'not public.erp_v763_forbidden_capitalization_account(a.code,a.name)',
    'staleSnapshotsSkipped',
    'excluded.source_updated_at>=erp_accounts.source_updated_at',
    'excluded.source_updated_at>=erp_partner_accounts.source_updated_at',
    'excluded.source_updated_at>=erp_item_costs.source_updated_at',
]: need(token in m, f'legacy/stale accounting state can still outrank current data: {token}')

# Historical capitalization is normalized from its source purchase invoice, not
# hidden by deleting one journal side. Closed historical dates use only a
# transaction-local technical period so the original effective date is retained.
for token in [
    'erp_r15_legacy_capitalized_purchase_invoices',
    'erp_r15_normalize_legacy_purchase_invoice',
    'erp_v760_normalize_purchase_invoice_posting',
    'R15-TECHNICAL-RECONCILIATION-',
    "'r15CanonicalReconciliation',true",
    'normalizedLegacyPurchaseInvoices',
    'failedLegacyPurchaseInvoices',
]: need(token in m, f'legacy capitalization source-normalization missing: {token}')
need("and (select n=0 from cap_lines)" in m,
     'canonical health can report ok while active legacy capitalization lines remain')

# Cashbox master is canonical for opening balance and cash-side journal account.
for token in [
    'erp_r15_rebind_cashbox_journals_internal',
    'opening_balance=v_opening',
    "'cashTransactionId',v_tx.id",
    "'cashAccountId',p_cash_account_id",
    "'r15CanonicalCashBinding',true",
    'erp_r15_cashbox_definition_changed',
    'deleted_cash_account_requires_explicit_restore',
    'cash_account_snapshot_version_required',
    'stale_cash_account',
]: need(token in m, f'cashbox/ledger continuous reconciliation missing: {token}')
need("normalized['_cloudUpdatedAt']" in cash_model and "normalized['updatedAt'] = cloudUpdatedAt" in cash_model,
     'legacy cashbox models do not carry a server freshness token into edits')
need('updatedAt: old?.updatedAt' in cash_form and 'updatedAt: old == null ? null : DateTime.now()' not in cash_form,
     'cashbox form fabricates a fresh timestamp instead of preserving the loaded concurrency snapshot')

# Health/probe surface is visible in production readiness.
need('erp_r15_current_state_health' in m and 'cashboxLedgerMismatchCount' in m and
     'resurrectedWarehouseCount' in m and 'resurrectedMasterCount' in m and 'activeLegacyCapitalizationAccountCount' in m and 'legacyCapitalizedPurchaseInvoiceCount' in m,
     'R15 data health does not expose legacy contamination')
need((("'erp_r15_runtime_contract_probe'" in feature and "'erp_r15_reconcile_company_state'" in feature) or
      ("'erp_r16_runtime_contract_probe'" in feature and "'erp_r16_reconcile_company_state'" in feature) or
      ("'erp_r22_runtime_contract_probe'" in feature and "'erp_r22_reconcile_company_state'" in feature)) and 'currentStateHealth' in readiness and
     'CANONICAL_DATA_STATE' in readiness,
     'production readiness does not enforce canonical data state through R15/R16 or verified R22')
need('_reconcileCanonicalStateAfterLogin' in access and 'if (isSystemAdmin)' in access and 'reconcileCanonicalState()' in access,
     'administrators do not reconcile canonical state before authenticated module loading')

# R15 is the current source migration and deployment is DB-first.
migrations=sorted(p.name for p in (ROOT/'supabase/migrations').glob('*.sql'))
need(Path(migration_rel).name in migrations,'R15 migration is missing')
if '20260808024500_r16_persistent_canonical_state.sql' in migrations:
    need(migrations.index(Path(migration_rel).name) < migrations.index('20260808024500_r16_persistent_canonical_state.sql'),'R16 does not follow R15')
need('verify:r15' in package and 'validate:r15:windows' in package,
     'R15 validation scripts are not exposed')
need('20260808001500_r14_runtime_rpc_invoice_root_closure.sql' in deploy and
     '20260808014500_r15_canonical_state_reconciliation.sql' in deploy and
     'Unexpected pending migrations. Refusing production push' in deploy,
     'R15 deploy script does not pin the expected migration')
if deploy:
    need(deploy.index('supabase db push --linked --yes') < deploy.index('firebase-tools deploy --only hosting'),
         'R15 deployment does not apply database before hosting')

expected={
 'dart_defines.json':'1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7',
 '.firebaserc':'f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8',
 'firebase.json':'ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a',
}
for rel,exp in expected.items():
    actual=normalized_text_sha256(ROOT/rel)
    need(actual==exp,f'production configuration changed: {rel}')

if errors:
    print('FAILED R15 canonical-state reconciliation')
    for e in errors: print('  -',e)
    sys.exit(1)
print('PASS R15 canonical-state reconciliation')
print('  - deleted/purged tombstones permanently outrank stale master payloads unless explicitly restored')
print('  - optimistic versions prevent older screens/devices from silently overwriting newer Supabase state')
print('  - stale accounting sync cannot overwrite newer account/partner/item-cost state')
print('  - obsolete capitalization accounts cannot reactivate; contaminated purchase invoices normalize from source')
print('  - deleted/stale cashbox edits cannot revive or overwrite current definitions')
print('  - cashbox opening balance and cash-side journals follow the current cashbox ledger binding continuously')
print('  - production readiness exposes canonical data health and reconciliation drift')
print('  - Supabase/Firebase production configuration hashes are unchanged')
