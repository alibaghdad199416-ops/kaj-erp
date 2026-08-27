import 'package:quality_line_erp/core/finance/currency_payment_validator.dart';

class SalesOrderItemInput {
  const SalesOrderItemInput({
    required this.itemType,
    required this.itemId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String itemType; // car | product
  final String itemId;
  final String description;
  final int quantity;
  final double unitPrice;

  double get lineTotal => quantity * unitPrice;

  void validate() {
    if (itemType != 'car' && itemType != 'product') {
      throw ArgumentError('نوع مادة أمر البيع غير مدعوم');
    }
    if (itemId.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('بيانات مادة أمر البيع غير مكتملة');
    }
    if (quantity <= 0 || (itemType == 'car' && quantity != 1)) {
      throw ArgumentError('كمية مادة أمر البيع غير صحيحة');
    }
    if (!unitPrice.isFinite || unitPrice < 0) {
      throw ArgumentError('سعر البيع لا يمكن أن يكون سالباً أو غير صالح');
    }
    if (!lineTotal.isFinite) {
      throw ArgumentError('إجمالي مادة أمر البيع غير صالح');
    }
  }
}

class InvoicePaymentInput {
  const InvoicePaymentInput({
    required this.cashAccountId,
    required this.paymentCurrency,
    required this.invoiceAmount,
    required this.cashAmount,
    required this.exchangeRate,
    required this.paymentDate,
    this.notes,
    this.settlementMode = PaymentSettlementMode.partial,
  });

  final String cashAccountId;
  final String paymentCurrency;
  final double invoiceAmount;
  final double cashAmount;
  final double exchangeRate;
  final DateTime paymentDate;
  final String? notes;
  final PaymentSettlementMode settlementMode;

  void validate() {
    if (cashAccountId.trim().isEmpty) {
      throw ArgumentError('يجب اختيار الصندوق المالي');
    }
    if (paymentCurrency != 'USD' && paymentCurrency != 'IQD') {
      throw ArgumentError('عملة الدفعة غير مدعومة');
    }
    if (!invoiceAmount.isFinite ||
        !cashAmount.isFinite ||
        invoiceAmount <= 0 ||
        cashAmount <= 0) {
      throw ArgumentError('مبلغ الدفعة يجب أن يكون أكبر من صفر وصالحاً');
    }
    if (!exchangeRate.isFinite || exchangeRate <= 0) {
      throw ArgumentError('معامل التحويل يجب أن يكون أكبر من صفر وصالحاً');
    }
  }
}
