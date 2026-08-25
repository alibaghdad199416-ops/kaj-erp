import 'package:quality_line_erp/core/models/model_value_reader.dart';

class PurchaseModel {
  const PurchaseModel({
    required this.id,
    required this.invoiceNumber,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseDate,
    required this.paymentMethod,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.currencyCode = 'USD',
    this.exchangeRate = 1,
  });

  final String id;
  final String invoiceNumber;

  final String supplierId;
  final String supplierName;

  final DateTime purchaseDate;

  /// Cash
  /// Credit
  /// Partial
  final String paymentMethod;

  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;

  final String? notes;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final String currencyCode;
  final double exchangeRate;

  bool get isPaid => remainingAmount <= 0;

  bool get isPartial => paidAmount > 0 && remainingAmount > 0;

  bool get isCredit => paidAmount == 0 && remainingAmount > 0;

  PurchaseModel copyWith({
    String? id,
    String? invoiceNumber,
    String? supplierId,
    String? supplierName,
    DateTime? purchaseDate,
    String? paymentMethod,
    double? totalAmount,
    double? paidAmount,
    double? remainingAmount,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? currencyCode,
    double? exchangeRate,
  }) {
    return PurchaseModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currencyCode: currencyCode ?? this.currencyCode,
      exchangeRate: exchangeRate ?? this.exchangeRate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoiceNumber': invoiceNumber,
      'supplierId': supplierId,
      'supplierName': supplierName,
      'purchaseDate': purchaseDate.toIso8601String(),
      'paymentMethod': paymentMethod,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'remainingAmount': remainingAmount,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'currencyCode': currencyCode,
      // Keep the invoice total in its selected currency. Conversion belongs
      // exclusively to payment and settlement records.
      'exchangeRate': 1,
      'amountUsd': currencyCode == 'USD' ? totalAmount : 0,
      'amountIqd': currencyCode == 'IQD' ? totalAmount : 0,
    };
  }

  factory PurchaseModel.fromMap(Map<String, dynamic> map) {
    return PurchaseModel(
      id: ModelValueReader.string(map, 'id'),
      invoiceNumber: ModelValueReader.string(map, 'invoiceNumber'),
      supplierId: ModelValueReader.string(map, 'supplierId'),
      supplierName: ModelValueReader.string(map, 'supplierName'),
      purchaseDate: ModelValueReader.requiredDateTime(
        map,
        'purchaseDate',
        aliases: const [
          'effectiveAt',
          'createdAt',
          'updatedAt',
          '_cloudUpdatedAt',
        ],
      ),
      paymentMethod: ModelValueReader.string(map, 'paymentMethod'),
      totalAmount: ModelValueReader.decimal(map, 'totalAmount'),
      paidAmount: ModelValueReader.decimal(map, 'paidAmount'),
      remainingAmount: ModelValueReader.decimal(map, 'remainingAmount'),
      notes: ModelValueReader.nullableString(map, 'notes'),
      createdAt: ModelValueReader.requiredDateTime(
        map,
        'createdAt',
        aliases: const ['updatedAt', '_cloudUpdatedAt', 'purchaseDate'],
      ),
      currencyCode: ModelValueReader.string(map, 'currencyCode').toUpperCase(),
      exchangeRate: ModelValueReader.decimal(map, 'exchangeRate', fallback: 1),
      updatedAt: ModelValueReader.dateTime(map, 'updatedAt'),
    );
  }

  @override
  String toString() {
    return 'PurchaseModel(invoice: $invoiceNumber, supplier: $supplierName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is PurchaseModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
