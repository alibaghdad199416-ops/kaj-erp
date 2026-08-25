class AssetHistoryEvent {
  const AssetHistoryEvent({
    required this.title,
    required this.date,
    required this.details,
    this.reference,
    this.eventType,
    this.statusBefore,
    this.statusAfter,
    this.warehouseBefore,
    this.warehouseAfter,
    this.productName,
    this.quantity,
    this.unitCost,
    this.totalCost,
    this.sourceName,
    this.destinationName,
    this.performedBy,
    this.referenceDocumentNumber,
  });

  final String title;
  final DateTime? date;
  final String details;
  final String? reference;
  final String? eventType;
  final String? statusBefore;
  final String? statusAfter;
  final String? warehouseBefore;
  final String? warehouseAfter;
  final String? productName;
  final num? quantity;
  final num? unitCost;
  final num? totalCost;
  final String? sourceName;
  final String? destinationName;
  final String? performedBy;
  final String? referenceDocumentNumber;
}
