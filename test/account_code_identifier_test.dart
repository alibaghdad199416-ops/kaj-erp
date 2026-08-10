import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';

void main() {
  test('account codes remain text identifiers with hierarchy punctuation', () {
    expect(ErpDisplayFormatter.accountCode('1000.05'), '1000.05');
    expect(ErpDisplayFormatter.accountCode('1000.029999'), '1000.029999');
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
}
