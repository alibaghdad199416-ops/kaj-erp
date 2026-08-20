from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'supabase/migrations/20260807033000_v762_definition_only_posting_balance_hardening.sql').read_text(encoding='utf-8')
for token in [
 'erp_v762_account_family','erp_v762_validate_journal_line',
 'invalid_journal_line_sides','capitalization_account_forbidden',
 'journal_line_account_currency_mismatch','erp_cloud_account_statement',
 'erp_cloud_trial_balance','erp_v762_accounting_integrity_audit',
 "code in ('1391','1392')",'capitalizationLineCount','movementDifference']:
    assert token in sql, token
assert any(v in (root/'pubspec.yaml').read_text(encoding='utf-8') for v in ["version: 18.9.32+189320","version: 22.9.8+229008"])
model=(root/'lib/features/accounting/models/account_model.dart').read_text(encoding='utf-8')
ui=(root/'lib/features/accounting/models/account_type_presentation.dart').read_text(encoding='utf-8')
# AccountModel preserves the authoritative persisted type; presentation-only aliases
# live in the centralized AccountTypePresentation helper so data is never silently rewritten.
assert 'final type = rawType' in model
for t in ['receivable','payable','income','cost','cogs','clearing']:
    assert f"'{t}'" in ui
assert "'payable' => 'liability'" in ui
assert "'cost' || 'cogs' => 'expense'" in ui
print('PASS V7.6.2 definition-only posting and debit/credit/balance hardening')
