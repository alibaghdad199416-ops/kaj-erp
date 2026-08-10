enum PaymentSettlementMode { partial, fullWithExchangeDifference }

class CurrencyPaymentBreakdown {
  const CurrencyPaymentBreakdown({
    required this.expectedCashAmount,
    required this.actualInvoiceEquivalent,
    required this.exchangeDifference,
  });

  final double expectedCashAmount;
  final double actualInvoiceEquivalent;
  final double exchangeDifference;
}

class CurrencyPaymentValidator {
  const CurrencyPaymentValidator._();

  static const supportedCurrencies = <String>{'USD', 'IQD'};

  static double expectedCashAmount({
    required String invoiceCurrency,
    required String paymentCurrency,
    required double invoiceAmount,
    required double exchangeRate,
  }) {
    _validateCurrencies(invoiceCurrency, paymentCurrency);
    if (invoiceAmount <= 0 || exchangeRate <= 0) {
      throw ArgumentError('المبلغ ومعامل التحويل يجب أن يكونا أكبر من صفر');
    }
    if (invoiceCurrency == paymentCurrency) return invoiceAmount;
    if (invoiceCurrency == 'USD' && paymentCurrency == 'IQD') {
      return invoiceAmount * exchangeRate;
    }
    return invoiceAmount / exchangeRate;
  }

  static double invoiceEquivalent({
    required String invoiceCurrency,
    required String paymentCurrency,
    required double cashAmount,
    required double exchangeRate,
  }) {
    _validateCurrencies(invoiceCurrency, paymentCurrency);
    if (cashAmount <= 0 || exchangeRate <= 0) {
      throw ArgumentError('المبلغ ومعامل التحويل يجب أن يكونا أكبر من صفر');
    }
    if (invoiceCurrency == paymentCurrency) return cashAmount;
    if (invoiceCurrency == 'USD' && paymentCurrency == 'IQD') {
      return cashAmount / exchangeRate;
    }
    return cashAmount * exchangeRate;
  }

  static CurrencyPaymentBreakdown breakdown({
    required String invoiceCurrency,
    required String paymentCurrency,
    required double invoiceAmount,
    required double cashAmount,
    required double exchangeRate,
  }) {
    final expected = expectedCashAmount(
      invoiceCurrency: invoiceCurrency,
      paymentCurrency: paymentCurrency,
      invoiceAmount: invoiceAmount,
      exchangeRate: exchangeRate,
    );
    final actualEquivalent = invoiceEquivalent(
      invoiceCurrency: invoiceCurrency,
      paymentCurrency: paymentCurrency,
      cashAmount: cashAmount,
      exchangeRate: exchangeRate,
    );
    return CurrencyPaymentBreakdown(
      expectedCashAmount: expected,
      actualInvoiceEquivalent: actualEquivalent,
      exchangeDifference: actualEquivalent - invoiceAmount,
    );
  }

  static void validateExact({
    required String invoiceCurrency,
    required String paymentCurrency,
    required double invoiceAmount,
    required double cashAmount,
    required double exchangeRate,
    double relativeTolerance = 0.005,
  }) {
    final result = breakdown(
      invoiceCurrency: invoiceCurrency,
      paymentCurrency: paymentCurrency,
      invoiceAmount: invoiceAmount,
      cashAmount: cashAmount,
      exchangeRate: exchangeRate,
    );
    final tolerance = (result.expectedCashAmount.abs() * relativeTolerance)
        .clamp(0.01, 1000.0);
    if ((cashAmount - result.expectedCashAmount).abs() > tolerance) {
      throw StateError(
        'مبلغ الصندوق لا يطابق مبلغ الفاتورة ومعامل التحويل. '
        'المبلغ المتوقع: ${result.expectedCashAmount.toStringAsFixed(paymentCurrency == 'IQD' ? 0 : 2)} $paymentCurrency',
      );
    }
  }

  static void validate({
    required String invoiceCurrency,
    required String paymentCurrency,
    required double invoiceAmount,
    required double cashAmount,
    required double exchangeRate,
    double relativeTolerance = 0.005,
  }) {
    validateExact(
      invoiceCurrency: invoiceCurrency,
      paymentCurrency: paymentCurrency,
      invoiceAmount: invoiceAmount,
      cashAmount: cashAmount,
      exchangeRate: exchangeRate,
      relativeTolerance: relativeTolerance,
    );
  }

  static void _validateCurrencies(
    String invoiceCurrency,
    String paymentCurrency,
  ) {
    if (!supportedCurrencies.contains(invoiceCurrency) ||
        !supportedCurrencies.contains(paymentCurrency)) {
      throw ArgumentError('العملة غير مدعومة');
    }
  }
}
