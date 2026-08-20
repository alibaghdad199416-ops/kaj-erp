import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/accounting/pages/accounting_center_page.dart';

void main() {
  test('trial balance uses opening plus period equals closing', () {
    expect(
      trialBalanceRowIsConsistent(<String, Object?>{
        'currency': 'USD',
        'openingDebit': 125,
        'openingCredit': 25,
        'periodDebit': 75,
        'periodCredit': 50,
        'closingDebit': 125,
        'closingCredit': 0,
      }),
      isTrue,
    );

    expect(
      trialBalanceRowIsConsistent(<String, Object?>{
        'currency': 'IQD',
        'openingDebit': 100,
        'openingCredit': 0,
        'periodDebit': 0,
        'periodCredit': 25,
        'closingDebit': 50,
        'closingCredit': 0,
      }),
      isFalse,
    );
  });
}
