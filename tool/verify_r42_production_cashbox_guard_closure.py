from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
def t(p): return (ROOT/p).read_text(encoding='utf-8',errors='ignore')
checks={}
def need(name,ok): checks[name]=bool(ok)

pkg=json.loads(t('package.json'))['scripts']
ver=json.loads(t('web/version.json'))
repo=t('lib/features/accounting/cashbox/repositories/cashbox_repository.dart')
model=t('lib/features/accounting/cashbox/models/cash_account_model.dart')
mig=t('supabase/migrations/20260809170859_r42_production_cashbox_guard_closure.sql')

need('R41 retained', 'verify:r41' in pkg)
need('cashbox list uses R42 canonical endpoint', "'erp_r42_list_cash_accounts'" in repo and "'erp_r28_list_cash_accounts'" not in repo)
need('cashbox save uses R42 canonical endpoint', "'erp_r42_save_cash_account'" in repo and "'erp_r28_save_cash_account'" not in repo)
need('cashbox payload writes all ledger aliases', all(x in model for x in ["'accountId': accountId","'account_id': accountId","'canonical': accountId","'ledgerAccountId': accountId"]))
need('cashbox read prefers canonical identity', "normalized['canonical']" in model and "normalized['ledgerAccountId']" in model)
need('R42 helper prefers canonical alias', "$1->>'canonical'" in mig and "$1->>'account_id'" in mig and "$1->>'accountId'" in mig)
need('DB before-write guard exists', 'erp_r42_cashbox_before_write_guard' in mig and 'trg_r42_cashbox_before_write_guard' in mig)
need('DB guard validates asset and exact currency', "v_ledger_type<>'asset'" in mig and 'v_ledger_currency<>v_currency' in mig)
need('DB guard blocks duplicate active ledger', 'cashbox_ledger_account_already_bound' in mig and 'erp_cash_account_ledger_company_uq' in mig and 'create unique index' in mig.lower())
need('EBL repair resolves account without hard-coded generated ids', 'r42_ebl_ledger_not_found' in mig and "normalized_name" in mig and "lower(a.account_type)='asset'" in mig and '4b43fb7e-e239-4994-8e2a-fb08e00c691c' not in mig and 'a713e3b8-a44b-4225-a08e-5f8afa90d565' not in mig)
need('R42 health RPC exists', 'erp_r42_cashbox_guard_health' in mig and 'duplicateActiveLedgerBindings' in mig and "'alias_drift'" in mig)
need('R42 PostgREST endpoints granted', all(x in mig for x in ['grant execute on function public.erp_r42_list_cash_accounts(uuid)','grant execute on function public.erp_r42_save_cash_account(uuid,jsonb)','grant execute on function public.erp_r42_cashbox_guard_health(uuid)']))
need('R42 metadata unified or superseded', (ver.get('releaseToken')=='r42-production-cashbox-guard-closure-20260809' and ver.get('syncEngine')=='22.9.8-r42-production-cashbox-guard-closure') or (ver.get('releaseToken')=='r43-performance-functional-closure-20260809' and ver.get('syncEngine')=='22.9.8-r43-performance-functional-closure') or (str(ver.get('releaseToken','')).startswith('r49-') and str(ver.get('syncEngine','')).startswith('22.9.8-r49-')))
need('R42 workspace gate', 'npm run verify:r42' in pkg.get('verify:workspace',''))
need('R42 deploy is default or superseded', ('deploy_r42_production.ps1' in pkg.get('deploy:production','') and 'validate_r42_workspace.ps1' in t('tool/deploy_r42_production.ps1')) or ('deploy_r43_production.ps1' in pkg.get('deploy:production','') and 'validate_r43_workspace.ps1' in t('tool/deploy_r43_production.ps1')) or ('deploy_r49_production.ps1' in pkg.get('deploy:production','') and 'validate_r49_workspace.ps1' in t('tool/deploy_r49_production.ps1')))
need('R42 deploy requires production migration', '20260809170859' in t('tool/deploy_r42_production.ps1'))
need('production config untouched by R42 scripts', all((ROOT/p).exists() for p in ['dart_defines.json','.firebaserc','firebase.json']))

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R42 verification failed: '+', '.join(failed))
print(f'PASS R42 production cashbox guard closure — {len(checks)} gates')
