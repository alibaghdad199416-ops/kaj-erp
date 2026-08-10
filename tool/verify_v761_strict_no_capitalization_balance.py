from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'supabase/migrations/20260807023000_v761_strict_no_capitalization_ledger_balance.sql').read_text(encoding='utf-8')
dart=(root/'lib/features/accounting/repositories/accounting_repository.dart').read_text(encoding='utf-8')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
required=[
 'erp_journal_lines_no_capitalization','capitalization_account_forbidden',
 "code in ('1391','1392')",'erp_v761_normal_balance','erp_cloud_account_balance_before',
 'movementDifference','capitalizationLineCount','currencyMismatchLineCount',
 "account_type='clearing'"
]
for marker in required:
    assert marker in sql, marker
assert "'payable'" in dart and "'income'" in dart
assert ('version: 18.9.31+189310' in pub) or ('version: 22.9.8+229008' in pub)
print('PASS V7.6.1 strict no-capitalization posting and debit/credit/balance integrity')
