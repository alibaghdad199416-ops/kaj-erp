import 'package:quality_line_erp/core/finance/currency_payment_validator.dart';

class PurchaseOrderItemInput {
  const PurchaseOrderItemInput({
    required this.itemType,
    required this.itemId,
    required this.description,
    required this.quantity,
    required this.unitCost,
  });

  final String itemType; // car or product
  final String itemId;
  final String description;
  final int quantity;
  final double unitCost;

  double get lineTotal => quantity * unitCost;

  void validate() {
    if (itemType != 'car' && itemType != 'product') {
      throw ArgumentError('نوع بند الشراء غير مدعوم');
    }
    if (itemId.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('بيانات بند الشراء غير مكتملة');
    }
    if (quantity <= 0 || unitCost < 0) {
      throw ArgumentError('كمية أو كلفة بند الشراء غير صحيحة');
    }
    if (itemType == 'car' && quantity != 1) {
      throw ArgumentError('كمية السيارة يجب أن تكون سيارة واحدة');
    }
    if (!unitCost.isFinite || !lineTotal.isFinite) {
      throw ArgumentError('كلفة بند الشراء غير صالحة');
    }
  }
}

class PurchaseInvoicePaymentInput {
  const PurchaseInvoicePaymentInput({
    required this.cashAccountId,
    required this.paymentCurrency,
    required this.invoiceAmount,
    required this.cashAmount,
    required this.exchangeRate,
    this.paymentDate,
    this.notes,
    this.settlementMode = PaymentSettlementMode.partial,
  });

  final String cashAccountId;
  final String paymentCurrency;
  final double invoiceAmount;
  final double cashAmount;
  final double exchangeRate;
  final DateTime? paymentDate;
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
        cashAmount <= 0 ||
        !exchangeRate.isFinite ||
        exchangeRate <= 0) {
      throw ArgumentError(
        'مبالغ الدفعة ومعامل التحويل يجب أن تكون أكبر من صفر وصالحة',
      );
    }
  }
}
