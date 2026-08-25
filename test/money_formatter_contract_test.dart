import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

void main() {
  group('MoneyFormatter', () {
    test('formats Iraqi dinar without fractions', () {
      expect(MoneyFormatter.format(1234567.89, currency: 'IQD'), '1,234,568');
    });

    test('formats dollar values with grouping and optional decimals', () {
      expect(MoneyFormatter.format(1234567.5, currency: 'USD'), '1,234,567.5');
    });

    test('adds currency label consistently', () {
      expect(MoneyFormatter.withCurrency(2500, 'USD'), '2,500 USD');
    });
  });
}
