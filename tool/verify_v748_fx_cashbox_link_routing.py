from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text(encoding='utf-8')
ui=read('lib/features/accounting/cashbox/pages/cashbox_page.dart')
sql=read('supabase/migrations/20260806114500_v748_fx_cashbox_link_routing_repair.sql')
release=read('lib/core/release/app_release_info.dart')
checks={
'UI auto-resolves configured link':'configuredLinkedAccount' in ui and 'allowedTargets' in ui,
'UI blocks unconfigured FX target':'destination is not the configured link' in ui,
'reciprocal table repair':'select l.company_id,l.target_cash_account_id,l.source_cash_account_id' in sql,
'resolver accepts either direction':'l.target_cash_account_id=p_source_cash_account_id' in sql,
'JSON alias fallback':"linked_cash_account_id" in sql and 'linkedCashAccountId' in sql,
'correct release': ("static const String version = '22.9.8'" in release) or ("18.9.18" in release and 'v748-fx-cashbox-link-routing' in release),
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL V7.4.8: '+', '.join(failed))
print('PASS V7.4.8 reciprocal FX cashbox link routing and transfer selection')
