import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/accounting/models/account_type_presentation.dart';

void main() {
  tearDown(() => AppTranslation.localeCode = 'ar');

  test('ledger exposes all account groups in canonical accounting order', () {
    final groups = AccountTypePresentation.groupLedgerRows([
      {
        'accountType': 'expense',
        'accountCode': '5000',
        'entryDate': '2026-05-01',
      },
      {
        'accountType': 'liability',
        'accountCode': '2100',
        'entryDate': '2026-02-01',
      },
      {
        'accountType': 'asset',
        'accountCode': '1100',
        'entryDate': '2026-01-01',
      },
      {
        'accountType': 'equity',
        'accountCode': '3100',
        'entryDate': '2026-03-01',
      },
      {
        'accountType': 'revenue',
        'accountCode': '4100',
        'entryDate': '2026-04-01',
      },
    ]);

    expect(groups.keys.toList(), [
      'asset',
      'liability',
      'equity',
      'revenue',
      'expense',
    ]);
  });

  test('ledger sorts account code first and entry date second', () {
    final groups = AccountTypePresentation.groupLedgerRows([
      {
        'accountType': 'asset',
        'accountCode': '1200',
        'entryDate': '2026-03-01',
      },
      {
        'accountType': 'asset',
        'accountCode': '1100',
        'entryDate': '2026-02-01',
      },
      {
        'accountType': 'asset',
        'accountCode': '1100',
        'entryDate': '2026-01-01',
      },
    ]);

    expect(
      groups['asset']!.map(
        (row) => '${row['accountCode']}:${row['entryDate']}',
      ),
      ['1100:2026-01-01', '1100:2026-02-01', '1200:2026-03-01'],
    );
  });

  test('ledger group labels follow the selected language', () {
    AppTranslation.localeCode = 'ar';
    expect(
      AccountTypePresentation.orderedTypes.map(
        AccountTypePresentation.arabicLabel,
      ),
      ['الأصول', 'الخصوم', 'حقوق الملكية', 'الإيرادات', 'المصروفات'],
    );

    AppTranslation.localeCode = 'en';
    expect(
      AccountTypePresentation.orderedTypes
          .map(AccountTypePresentation.arabicLabel)
          .map(AppTranslation.translate),
      ['Assets', 'Liabilities', 'Equity', 'Revenue', 'Expenses'],
    );
  });
}
