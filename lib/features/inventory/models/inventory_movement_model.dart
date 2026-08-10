class InventoryMovementModel {
  const InventoryMovementModel({
    required this.id,
    required this.productId,
    required this.movementNumber,
    required this.productName,
    required this.productCode,
    required this.warehouseName,
    required this.movementType,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    required this.currency,
    required this.movementDate,
    this.referenceType,
    this.referenceId,
    this.notes,
    this.auditUpdatedAt,
    this.sourceName,
    this.destinationName,
    this.performedBy,
    this.referenceDocumentNumber,
  });

  final String id;
  final String productId;
  final String movementNumber;
  final String productName;
  final String productCode;
  final String warehouseName;
  final String movementType;
  final int quantity;
  final double unitCost;
  final double totalCost;
  final String currency;
  final String movementDate;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final DateTime? auditUpdatedAt;
  final String? sourceName;
  final String? destinationName;
  final String? performedBy;
  final String? referenceDocumentNumber;

  bool get isIncoming => quantity > 0;

  String get typeLabel {
    switch (movementType) {
      case 'opening':
        return 'رصيد افتتاحي';
      case 'purchase_in':
        return 'شراء / إدخال';
      case 'sale_out':
        return 'بيع منتج';
      case 'maintenance_out':
        return 'سحب للصيانة';
      case 'transfer_in':
        return 'نقل وارد';
      case 'transfer_out':
        return 'نقل صادر';
      case 'expected_in':
        return 'إدخال متوقع';
      case 'expected_out':
        return 'إخراج متوقع';
      default:
        return movementType;
    }
  }

  factory InventoryMovementModel.fromMap(Map<String, dynamic> map) =>
      InventoryMovementModel(
        id: map['id']?.toString() ?? '',
        productId: map['productId']?.toString() ?? '',
        movementNumber: map['movementNumber']?.toString() ?? '',
        productName: map['productName']?.toString() ?? '',
        productCode: map['productCode']?.toString() ?? '',
        warehouseName: map['warehouseName']?.toString() ?? '',
        movementType: map['movementType']?.toString() ?? '',
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        unitCost: (map['unitCost'] as num?)?.toDouble() ?? 0,
        totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0,
        currency: (map['currency'] ?? map['costCurrency'] ?? '')
            .toString()
            .trim()
            .toUpperCase(),
        movementDate: map['movementDate']?.toString() ?? '',
        referenceType: map['referenceType']?.toString(),
        referenceId: map['referenceId']?.toString(),
        notes: map['notes']?.toString(),
        auditUpdatedAt: DateTime.tryParse(
          map['_cloudUpdatedAt']?.toString() ??
              map['updatedAt']?.toString() ??
              '',
        ),
        sourceName: map['sourceName']?.toString(),
        destinationName: map['destinationName']?.toString(),
        performedBy: map['performedBy']?.toString(),
        referenceDocumentNumber: map['referenceDocumentNumber']?.toString(),
      );
}
