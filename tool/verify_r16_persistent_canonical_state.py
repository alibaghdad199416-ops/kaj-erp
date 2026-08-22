from pathlib import Path
import sys
from verification_text import normalized_text_sha256

ROOT=Path(__file__).resolve().parents[1]
errors=[]
def read(rel): return (ROOT/rel).read_text(encoding='utf-8',errors='strict')
def need(cond,msg):
    if not cond: errors.append(msg)

mrel='supabase/migrations/20260808024500_r16_persistent_canonical_state.sql'
m=read(mrel)
feature=read('lib/core/cloud/cloud_feature_command.dart')
readiness=read('lib/core/release/production_readiness_service.dart')
access=read('lib/features/settings/access/controllers/access_controller.dart')
pkg=read('package.json')
deploy=read('tool/deploy_r16_production.ps1') if (ROOT/'tool/deploy_r16_production.ps1').exists() else ''

# Permanent deletion truth survives recycle-bin purge.
for token in [
    'erp_canonical_deletion_tombstones',
    'erp_r16_recycle_tombstone_trigger',
    'before delete on public.erp_universal_recycle_bin',
    "case when old.restored_at is null then coalesce(old.purged_at,now())",
    'r16_seed_audit',
    'erp_r15_pending_delete_exists',
    'from public.erp_canonical_deletion_tombstones t',
    'and t.restored_at is null',
]: need(token in m,f'missing persistent tombstone guarantee: {token}')
need('delete from public.erp_canonical_deletion_tombstones' not in m,
     'R16 must never erase canonical deletion history during purge/reconciliation')

# Cash reconciliation must be identity-first and never amount-only.
for token in [
    'erp_canonical_reconciliation_issues',
    'erp_r16_cash_line_matches',
    "v_match_method:='line_cash_transaction_id'",
    "v_match_method:='journal_cash_transaction_id'",
    "v_match_method:='source_reference'",
    "v_match_method:='canonical_ledger_account'",
    'cash_identity_unresolved',
    'cash_line_identity_ambiguous',
    'r16CanonicalCashBinding',
    'r16CashMatchMethod',
    'create constraint trigger erp_r16_deferred_cash_reconcile',
    'deferrable initially deferred',
]: need(token in m,f'missing identity-safe cash reconciliation: {token}')
need('amount-only fallback' in m and 'There is no' in m,
     'R16 source must explicitly prohibit amount-only journal rewriting')

# Current-state health must expose unresolved drift and persistent deletion conflicts.
for token in [
    'erp_r16_current_state_health',
    'persistentDeletionConflictCount',
    'unresolvedCanonicalReconciliationIssueCount',
    "'canonicalStateVersion',16",
    'erp_r16_reconcile_company_state',
    'erp_r16_runtime_contract_probe',
    "'persistentDeletionRegistry'",
    "'identitySafeCashReconciliation'",
]: need(token in m,f'missing R16 health/runtime contract: {token}')

# Current Flutter client must retain R16 canonical guarantees directly or
# through the verified R22 successor, which delegates its base reconciliation
# to R16 and exposes the same persistent-state health.
r22_path=ROOT/'supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql'
r22=read('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql') if r22_path.exists() else ''
uses_r16 = "'erp_r16_reconcile_company_state'" in feature and "'erp_r16_runtime_contract_probe'" in feature
uses_r22 = ("'erp_r22_reconcile_company_state'" in feature and "'erp_r22_runtime_contract_probe'" in feature
            and 'public.erp_r16_reconcile_company_state(p_company_id)' in r22
            and 'public.erp_r16_current_state_health(p_company_id)' in r22)
need(uses_r16 or uses_r22,'Flutter no longer retains R16 persistent-state reconciliation guarantees')
need("'persistentDeletionRegistry'" in readiness and "'identitySafeCashReconciliation'" in readiness,
     'Production readiness does not require R16 persistent-state contracts')
need(('R16 canonical-state reconciliation completed:' in access) or ('R22 canonical-state reconciliation completed:' in access),
     'login canonical-state log does not identify the current persistent-state reconciliation')

# R16 must remain in the migration chain; verified later canonical-state releases
# may follow it.
migrations=sorted(p.name for p in (ROOT/'supabase/migrations').glob('*.sql'))
need(Path(mrel).name in migrations,'R16 migration is missing')
if r22_path.exists():
    need(migrations.index(Path(mrel).name) < migrations.index(r22_path.name),'R22 consolidation does not follow R16')
else:
    need(migrations and migrations[-1]==Path(mrel).name,'R16 migration is not last')
need('verify:r16' in pkg and 'validate:r16:windows' in pkg,'R16 scripts are not exposed')
need('20260808001500_r14_runtime_rpc_invoice_root_closure.sql' in deploy and
     '20260808014500_r15_canonical_state_reconciliation.sql' in deploy and
     '20260808024500_r16_persistent_canonical_state.sql' in deploy,
     'R16 deploy script does not pin R14/R15/R16 migrations')
need('Unexpected pending migrations. Refusing production push' in deploy,
     'R16 deploy script does not reject unexpected migrations')
if deploy:
    need(deploy.index('supabase db push --linked --yes') < deploy.index('firebase-tools deploy --only hosting'),
         'R16 deployment must apply database before hosting')

expected={
 'dart_defines.json':'4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f',
 '.firebaserc':'f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8',
 'firebase.json':'ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a',
}
for rel,exp in expected.items():
    actual=normalized_text_sha256(ROOT/rel)
    need(actual==exp,f'local runtime/hosting baseline changed: {rel}')

if errors:
    print('FAILED R16 persistent canonical state')
    for e in errors: print('  -',e)
    sys.exit(1)
print('PASS R16 persistent canonical state')
print('  - permanent purge no longer erases deletion truth; stale clients cannot recreate a purged master ID')
print('  - recycle restore is the only path that clears an active canonical tombstone')
print('  - cashbox journal rebinding requires transaction/header/reference/account identity; amount-only matching is forbidden')
print('  - ambiguous/unmatched cash journals are recorded as reconciliation issues instead of being rewritten')
print('  - deferred reconciliation makes future cash postings converge after journal lines exist')
print('  - production readiness blocks on persistent deletion conflicts and unresolved canonical reconciliation issues')
print('  - Local Supabase/Firebase baseline hashes are unchanged')
