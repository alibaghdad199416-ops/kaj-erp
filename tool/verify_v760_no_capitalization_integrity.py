from pathlib import Path
root=Path(__file__).resolve().parents[1]
sql=(root/'supabase/migrations/20260807013000_v760_no_capitalization_accounting_integrity.sql').read_text(encoding='utf-8')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
dart=(root/'lib/features/accounting/repositories/accounting_repository.dart').read_text(encoding='utf-8')
assert ('version: 18.9.30+189300' in pub) or ('version: 22.9.8+229008' in pub)
for token in [
 'erp_v760_normalize_purchase_invoice_posting',
 'definition_accounts_no_capitalization',
 "code in ('1391','1392')",
 "is_active=false",
 'erp_v760_is_credit_nature',
 "'absoluteDifference'",
 'invalidLineCount',
 'erp_v760_approve_workflow_invoice'
]: assert token in sql, token
assert 'رسملة مخزون فاتورة الشراء' not in sql
assert 'account.type.toLowerCase()' in dart
assert "'movementDebit': _toDouble(row['movementDebit'])" in dart
print('PASS V7.6.0 no capitalization, definition-owned purchase posting, and debit/credit/balance integrity')
