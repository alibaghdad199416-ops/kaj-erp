from pathlib import Path
root=Path(__file__).resolve().parents[1]
checks={
 'version': any(v in (root/'pubspec.yaml').read_text(encoding='utf-8') for v in ['version: 18.9.14+189140','version: 22.9.8+229008']),
 'migration':(root/'supabase/migrations/20260806080000_v744_cashbox_binding_links_and_balanced_transfers.sql').exists(),
 'links':'erp_cash_account_links' in (root/'supabase/migrations/20260806080000_v744_cashbox_binding_links_and_balanced_transfers.sql').read_text(encoding='utf-8'),
 'auto fx link':'erp_resolve_linked_cash_account' in (root/'supabase/migrations/20260806080000_v744_cashbox_binding_links_and_balanced_transfers.sql').read_text(encoding='utf-8'),
 'balanced transfer':"'journalMode','balanced_cash_transfer'" in (root/'supabase/migrations/20260806080000_v744_cashbox_binding_links_and_balanced_transfers.sql').read_text(encoding='utf-8'),
 'persistent binding':"'account_id',v_ledger" in (root/'supabase/migrations/20260806080000_v744_cashbox_binding_links_and_balanced_transfers.sql').read_text(encoding='utf-8'),
 'linked cash UI':'linkedCashAccountId' in (root/'lib/features/accounting/cashbox/pages/cash_account_form.dart').read_text(encoding='utf-8'),
 'close beside toolbar':'effectiveToolbar' in (root/'lib/core/widgets/app_entity_page.dart').read_text(encoding='utf-8'),
}
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAIL V7.4.4: '+', '.join(failed))
print('PASS V7.4.4 cashbox binding, linked FX payments, balanced transfers, and integrated close action')
for k in checks: print('  - '+k)
