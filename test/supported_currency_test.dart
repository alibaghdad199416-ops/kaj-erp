import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';

void main() {
  test('normalizes only supported ERP currencies', () {
    expect(SupportedCurrency.normalize(' usd '), 'USD');
    expect(SupportedCurrency.normalize('iqd'), 'IQD');
    expect(SupportedCurrency.normalize('EUR'), isNull);
    expect(SupportedCurrency.normalize(''), isNull);
    expect(SupportedCurrency.normalize(null), isNull);
  });

  test('existing records fail closed while new records may default to USD', () {
    expect(SupportedCurrency.initial(isNew: true, stored: null), 'USD');
    expect(SupportedCurrency.initial(isNew: false, stored: null), '');
    expect(SupportedCurrency.initial(isNew: false, stored: 'EUR'), '');
    expect(SupportedCurrency.initial(isNew: false, stored: 'IQD'), 'IQD');
  });
}
