import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/accounting/models/account_type_presentation.dart';

void main() {
  test('account types keep the required accounting order and labels', () {
    expect(AccountTypePresentation.orderedTypes, [
      'asset',
      'liability',
      'equity',
      'revenue',
      'expense',
    ]);
    expect(AccountTypePresentation.arabicLabel('asset'), 'الأصول');
    expect(AccountTypePresentation.arabicLabel('liability'), 'الخصوم');
    expect(AccountTypePresentation.arabicLabel('equity'), 'حقوق الملكية');
    expect(AccountTypePresentation.arabicLabel('revenue'), 'الإيرادات');
    expect(AccountTypePresentation.arabicLabel('expense'), 'المصروفات');
  });

  test('general-ledger rows are grouped and sorted by account type', () {
    final groups = AccountTypePresentation.groupLedgerRows([
      {
        'accountType': 'expense',
        'accountCode': '5000',
        'entryDate': '2026-02-01',
      },
      {
        'accountType': 'asset',
        'accountCode': '1200',
        'entryDate': '2026-02-01',
      },
      {
        'accountType': 'asset',
        'accountCode': '1100',
        'entryDate': '2026-01-01',
      },
      {
        'accountType': 'revenue',
        'accountCode': '4000',
        'entryDate': '2026-01-01',
      },
    ]);
    expect(groups.keys.toList(), ['asset', 'revenue', 'expense']);
    expect(groups['asset']!.map((row) => row['accountCode']), ['1100', '1200']);
  });
}
