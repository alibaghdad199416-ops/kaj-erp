from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'supabase/migrations/20260807043000_v763_zero_capitalization_balance_reconciliation.sql').read_text(encoding='utf-8')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
release=(root/'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
for token in [
 'erp_v763_forbidden_capitalization_account',
 'capitalization_account_forbidden',
 "('1391','1392')",
 'erp_v763_validate_journal_line',
 'invalid_journal_line_sides',
 'journal_line_account_currency_mismatch',
 'erp_v763_account_family',
 'accounts_receivable','accounts_payable','cost_of_goods_sold',
 'movementDifference','absoluteDifference',"'balanced'",
 'orphanAccountLineCount','inactiveAccountLineCount','capitalizationLineCount',
 'erp_v763_accounting_integrity_audit']:
    assert token in sql, token
assert ('version: 18.9.33+189330' in pub) or ('version: 22.9.8+229008' in pub)
assert ("static const String version = '18.9.33';" in release) or ("static const String version = '22.9.8';" in release)
print('PASS V7.6.3 zero-capitalization policy and debit/credit/balance reconciliation')
