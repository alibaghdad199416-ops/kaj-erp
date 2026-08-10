import 'package:quality_line_erp/core/models/model_value_reader.dart';

class PurchaseItemModel {
  const PurchaseItemModel({
    required this.id,
    required this.purchaseId,
    required this.carId,
    required this.carName,
    required this.chassisNumber,
    required this.purchasePrice,
    required this.additionalCosts,
    required this.totalCost,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String purchaseId;

  final String carId;
  final String carName;
  final String chassisNumber;

  final double purchasePrice;
  final double additionalCosts;
  final double totalCost;

  final String? notes;

  final DateTime createdAt;
  final DateTime? updatedAt;

  PurchaseItemModel copyWith({
    String? id,
    String? purchaseId,
    String? carId,
    String? carName,
    String? chassisNumber,
    double? purchasePrice,
    double? additionalCosts,
    double? totalCost,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PurchaseItemModel(
      id: id ?? this.id,
      purchaseId: purchaseId ?? this.purchaseId,
      carId: carId ?? this.carId,
      carName: carName ?? this.carName,
      chassisNumber: chassisNumber ?? this.chassisNumber,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      additionalCosts: additionalCosts ?? this.additionalCosts,
      totalCost: totalCost ?? this.totalCost,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'purchaseId': purchaseId,
      'carId': carId,
      'carName': carName,
      'chassisNumber': chassisNumber,
      'purchasePrice': purchasePrice,
      'additionalCosts': additionalCosts,
      'totalCost': totalCost,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory PurchaseItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseItemModel(
      id: ModelValueReader.string(map, 'id'),
      purchaseId: ModelValueReader.string(map, 'purchaseId'),
      carId: ModelValueReader.string(map, 'carId'),
      carName: ModelValueReader.string(map, 'carName'),
      chassisNumber: ModelValueReader.string(map, 'chassisNumber'),
      purchasePrice: ModelValueReader.decimal(map, 'purchasePrice'),
      additionalCosts: ModelValueReader.decimal(map, 'additionalCosts'),
      totalCost: ModelValueReader.decimal(map, 'totalCost'),
      notes: ModelValueReader.nullableString(map, 'notes'),
      createdAt: ModelValueReader.requiredDateTime(
        map,
        'createdAt',
        aliases: const ['updatedAt', '_cloudUpdatedAt'],
      ),
      updatedAt: ModelValueReader.dateTime(map, 'updatedAt'),
    );
  }

  @override
  String toString() {
    return 'PurchaseItemModel(car: $carName, chassis: $chassisNumber, totalCost: $totalCost)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is PurchaseItemModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
