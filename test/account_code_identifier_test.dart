import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';

void main() {
  test('account codes remain text identifiers with hierarchy punctuation', () {
    expect(ErpDisplayFormatter.accountCode('1000.05'), '1000.05');
    expect(ErpDisplayFormatter.accountCode('1,000.009999999'), '1000.01');
    expect(ErpDisplayFormatter.accountCode('3000.019999999'), '3000.02');
    expect(ErpDisplayFormatter.accountCode('5000.020000000'), '5000.02');
    expect(ErpDisplayFormatter.accountCode('1000.001'), '1000.001');
    expect(ErpDisplayFormatter.accountCode('1000.01.02'), '1000.01.02');
    expect(ErpDisplayFormatter.accountCode(' A-10.02 '), 'A-10.02');
  });

  test('account model read-back does not parse account code as money', () {
    final account = AccountModel.fromMap(<String, Object?>{
      'id': 'account-1',
      'code': '1000.05',
      'name': 'Inventory',
      'type': 'asset',
      'currency': 'USD',
      'openingBalance': 0,
      'isActive': true,
      'createdAt': '2026-08-10T00:00:00Z',
    });
    expect(account.code, '1000.05');
  });

  test('account model repairs only recognizable legacy float artifacts', () {
    final account = AccountModel.fromMap(<String, Object?>{
      'id': 'account-legacy',
      'code': '1,000.009999999',
      'name': 'Cash',
      'type': 'asset',
      'currency': 'USD',
      'openingBalance': 0,
      'isActive': true,
      'createdAt': '2026-08-10T00:00:00Z',
    });
    expect(account.code, '1000.01');
  });
}
