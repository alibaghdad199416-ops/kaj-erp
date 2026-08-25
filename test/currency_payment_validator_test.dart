import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/finance/currency_payment_validator.dart';

void main() {
  group('CurrencyPaymentValidator', () {
    test('same currency requires equal amounts', () {
      expect(
        CurrencyPaymentValidator.expectedCashAmount(
          invoiceCurrency: 'USD',
          paymentCurrency: 'USD',
          invoiceAmount: 250,
          exchangeRate: 1500,
        ),
        250,
      );
    });

    test('converts USD invoice to IQD cash', () {
      expect(
        CurrencyPaymentValidator.expectedCashAmount(
          invoiceCurrency: 'USD',
          paymentCurrency: 'IQD',
          invoiceAmount: 100,
          exchangeRate: 1500,
        ),
        150000,
      );
    });

    test('converts IQD invoice to USD cash', () {
      expect(
        CurrencyPaymentValidator.expectedCashAmount(
          invoiceCurrency: 'IQD',
          paymentCurrency: 'USD',
          invoiceAmount: 150000,
          exchangeRate: 1500,
        ),
        100,
      );
    });

    test('rejects inconsistent cash amount', () {
      expect(
        () => CurrencyPaymentValidator.validate(
          invoiceCurrency: 'USD',
          paymentCurrency: 'IQD',
          invoiceAmount: 100,
          cashAmount: 100000,
          exchangeRate: 1500,
        ),
        throwsStateError,
      );
    });
  });
}
