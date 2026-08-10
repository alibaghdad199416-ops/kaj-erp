import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/finance/currency_payment_validator.dart';

void main() {
  group('currency payment settlement', () {
    test('partial payment uses actual invoice equivalent', () {
      final result = CurrencyPaymentValidator.breakdown(
        invoiceCurrency: 'USD',
        paymentCurrency: 'IQD',
        invoiceAmount: 100,
        cashAmount: 120000,
        exchangeRate: 1500,
      );
      expect(result.actualInvoiceEquivalent, closeTo(80, 0.0001));
      expect(result.exchangeDifference, closeTo(-20, 0.0001));
    });

    test('full settlement exposes favorable sales difference', () {
      final result = CurrencyPaymentValidator.breakdown(
        invoiceCurrency: 'USD',
        paymentCurrency: 'IQD',
        invoiceAmount: 100,
        cashAmount: 165000,
        exchangeRate: 1500,
      );
      expect(result.actualInvoiceEquivalent, closeTo(110, 0.0001));
      expect(result.exchangeDifference, closeTo(10, 0.0001));
    });

    test(
      'partial settlement requires exact cash equivalent for requested amount',
      () {
        expect(
          () => CurrencyPaymentValidator.validateExact(
            invoiceCurrency: 'USD',
            paymentCurrency: 'IQD',
            invoiceAmount: 50,
            cashAmount: 60000,
            exchangeRate: 1500,
          ),
          throwsStateError,
        );
        expect(
          () => CurrencyPaymentValidator.validateExact(
            invoiceCurrency: 'USD',
            paymentCurrency: 'IQD',
            invoiceAmount: 50,
            cashAmount: 75000,
            exchangeRate: 1500,
          ),
          returnsNormally,
        );
      },
    );

    test('IQD invoice can be paid from USD cash account', () {
      final result = CurrencyPaymentValidator.breakdown(
        invoiceCurrency: 'IQD',
        paymentCurrency: 'USD',
        invoiceAmount: 150000,
        cashAmount: 100,
        exchangeRate: 1500,
      );
      expect(result.actualInvoiceEquivalent, closeTo(150000, 0.0001));
      expect(result.exchangeDifference, closeTo(0, 0.0001));
    });
  });
}
