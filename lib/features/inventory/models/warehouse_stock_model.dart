class WarehouseStockModel {
  const WarehouseStockModel({
    required this.warehouseId,
    required this.productId,
    required this.quantity,
    required this.reservedQuantity,
    required this.expectedIncoming,
    required this.expectedOutgoing,
    required this.averageUnitCost,
  });

  final String warehouseId;
  final String productId;
  final int quantity;
  final int reservedQuantity;
  final int expectedIncoming;
  final int expectedOutgoing;
  final double averageUnitCost;

  int get availableQuantity => quantity - reservedQuantity;
  int get projectedQuantity => quantity + expectedIncoming - expectedOutgoing;

  factory WarehouseStockModel.fromMap(Map<String, dynamic> map) =>
      WarehouseStockModel(
        warehouseId: map['warehouseId']?.toString() ?? '',
        productId: map['productId']?.toString() ?? '',
        quantity: (map['quantity'] as num?)?.toInt() ?? 0,
        reservedQuantity: (map['reservedQuantity'] as num?)?.toInt() ?? 0,
        expectedIncoming: (map['expectedIncoming'] as num?)?.toInt() ?? 0,
        expectedOutgoing: (map['expectedOutgoing'] as num?)?.toInt() ?? 0,
        averageUnitCost: (map['averageUnitCost'] as num?)?.toDouble() ?? 0,
      );
}
