import 'package:quality_line_erp/core/models/model_value_reader.dart';

enum CarStatus { defined, purchasing, available, damaged, selling, sold }

extension CarStatusCodec on CarStatus {
  String get storageValue => switch (this) {
    CarStatus.defined => 'معرفة',
    CarStatus.purchasing => 'قيد الشراء',
    CarStatus.available => 'متوفرة',
    CarStatus.damaged => 'تالفة',
    CarStatus.selling => 'قيد البيع',
    CarStatus.sold => 'مباعة',
  };

  static CarStatus parse(Object? value) {
    switch (value?.toString().trim().toLowerCase()) {
      case 'defined':
      case 'registered':
      case 'معرفة':
        return CarStatus.defined;
      case 'selling':
      case 'pending_sale':
      case 'قيد بيع':
      case 'قيد البيع':
      case 'reserved':
      case 'محجوز':
      case 'محجوزة':
        return CarStatus.selling;
      case 'damaged':
      case 'scrap':
      case 'تالفة':
      case 'تالف':
        return CarStatus.damaged;
      case 'sold':
      case 'مباع':
      case 'مباعة':
        return CarStatus.sold;
      case 'purchasing':
      case 'pending_purchase':
      case 'قيد شراء':
      case 'قيد الشراء':
        return CarStatus.purchasing;
      case 'available':
      case 'متاحة':
      case 'متوفرة':
        return CarStatus.available;
      default:
        return CarStatus.defined;
    }
  }
}

class CarModel {
  const CarModel({
    required this.id,
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.chassis,
    this.engineNumber = '',
    required this.plateNumber,
    required this.purchasePrice,
    required this.salePrice,
    required this.status,
    required this.imagePath,
    this.vehicleType = '',
    this.carNumber = '',
    this.currency = 'USD',
    this.costCurrency,
    this.saleCurrency,
    this.maintenanceCost = 0,
    this.warehouseId,
    this.supplierId,
    this.supplierName,
    this.purchaseDate,
    this.notes,
    this.inventoryAssetAccountId,
    this.salesCostExpenseAccountId,
    this.salesRevenueIqdAccountId,
    this.salesRevenueUsdAccountId,
  });

  final String id;
  final String vehicleType;
  final String brand;
  final String model;
  final int year;
  final String color;
  final String chassis;
  final String engineNumber;
  final String plateNumber;
  final String carNumber;
  final double purchasePrice;
  final double salePrice;
  final String currency;
  final String? costCurrency;
  final String? saleCurrency;
  final String status;
  final String imagePath;
  final double maintenanceCost;
  final String? warehouseId;
  final String? supplierId;
  final String? supplierName;
  final String? purchaseDate;
  final String? notes;

  /// Asset account debited when the vehicle is purchased and credited on sale/scrap.
  final String? inventoryAssetAccountId;

  /// Expense/COGS account debited when the vehicle is sold.
  final String? salesCostExpenseAccountId;

  /// Revenue accounts are currency-specific because the sale invoice and the
  /// vehicle cost can legitimately be in different currencies.
  final String? salesRevenueIqdAccountId;
  final String? salesRevenueUsdAccountId;

  CarStatus get statusValue => CarStatusCodec.parse(status);
  double get totalCost => purchasePrice + maintenanceCost;
  double get expectedGrossProfit => salePrice - totalCost;
  bool get isIncludedInCurrentInventoryValue =>
      (statusValue == CarStatus.available ||
          statusValue == CarStatus.selling) &&
      warehouseId?.trim().isNotEmpty == true;

  void validate() {
    if (id.trim().isEmpty) throw ArgumentError('مرجع السيارة غير صالح');
    if (brand.trim().isEmpty || model.trim().isEmpty) {
      throw ArgumentError('ماركة وموديل السيارة مطلوبان');
    }
    if (year < 1900 || year > DateTime.now().year + 1) {
      throw ArgumentError('سنة صنع السيارة غير صحيحة');
    }
    if (chassis.trim().isEmpty) throw ArgumentError('رقم الشاصي مطلوب');
    if (purchasePrice < 0 || salePrice < 0 || maintenanceCost < 0) {
      throw ArgumentError('قيم السيارة المالية لا يمكن أن تكون سالبة');
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency != 'IQD' && normalizedCurrency != 'USD') {
      throw ArgumentError('عملة السيارة يجب أن تكون IQD أو USD');
    }
  }

  CarModel copyWith({
    String? id,
    String? vehicleType,
    String? brand,
    String? model,
    int? year,
    String? color,
    String? chassis,
    String? engineNumber,
    String? plateNumber,
    String? carNumber,
    double? purchasePrice,
    double? salePrice,
    String? currency,
    String? costCurrency,
    String? saleCurrency,
    String? status,
    CarStatus? statusValue,
    String? imagePath,
    double? maintenanceCost,
    String? warehouseId,
    String? supplierId,
    String? supplierName,
    String? purchaseDate,
    String? notes,
    String? inventoryAssetAccountId,
    String? salesCostExpenseAccountId,
    String? salesRevenueIqdAccountId,
    String? salesRevenueUsdAccountId,
    bool clearWarehouseId = false,
    bool clearSupplierId = false,
    bool clearSupplierName = false,
    bool clearPurchaseDate = false,
    bool clearNotes = false,
  }) {
    return CarModel(
      id: id ?? this.id,
      vehicleType: vehicleType ?? this.vehicleType,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      color: color ?? this.color,
      chassis: chassis ?? this.chassis,
      engineNumber: engineNumber ?? this.engineNumber,
      plateNumber: plateNumber ?? this.plateNumber,
      carNumber: carNumber ?? this.carNumber,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      currency: currency ?? this.currency,
      costCurrency: costCurrency ?? this.costCurrency,
      saleCurrency: saleCurrency ?? this.saleCurrency,
      status: statusValue?.storageValue ?? status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      maintenanceCost: maintenanceCost ?? this.maintenanceCost,
      warehouseId: clearWarehouseId ? null : warehouseId ?? this.warehouseId,
      supplierId: clearSupplierId ? null : supplierId ?? this.supplierId,
      supplierName: clearSupplierName
          ? null
          : supplierName ?? this.supplierName,
      purchaseDate: clearPurchaseDate
          ? null
          : purchaseDate ?? this.purchaseDate,
      notes: clearNotes ? null : notes ?? this.notes,
      inventoryAssetAccountId:
          inventoryAssetAccountId ?? this.inventoryAssetAccountId,
      salesCostExpenseAccountId:
          salesCostExpenseAccountId ?? this.salesCostExpenseAccountId,
      salesRevenueIqdAccountId:
          salesRevenueIqdAccountId ?? this.salesRevenueIqdAccountId,
      salesRevenueUsdAccountId:
          salesRevenueUsdAccountId ?? this.salesRevenueUsdAccountId,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'vehicleType': vehicleType,
    'brand': brand,
    'model': model,
    'year': year,
    'color': color,
    'chassis': chassis,
    'engineNumber': engineNumber,
    'plateNumber': plateNumber,
    'carNumber': carNumber,
    'purchasePrice': purchasePrice,
    'salePrice': salePrice,
    'currency': currency.trim().toUpperCase(),
    'costCurrency': (costCurrency ?? currency).trim().toUpperCase(),
    'saleCurrency': (saleCurrency ?? currency).trim().toUpperCase(),
    'status': statusValue.storageValue,
    'imagePath': imagePath,
    'maintenanceCost': maintenanceCost,
    'warehouseId': warehouseId,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'purchaseDate': purchaseDate,
    'notes': notes,
    'inventoryAssetAccountId': inventoryAssetAccountId,
    'salesCostExpenseAccountId': salesCostExpenseAccountId,
    'salesRevenueIqdAccountId': salesRevenueIqdAccountId,
    'salesRevenueUsdAccountId': salesRevenueUsdAccountId,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  /// Writes normalized snake_case keys and compatibility camelCase aliases.
  /// Several historical SQL functions still read camelCase JSON fields, while
  /// newer Flutter code uses snake_case for normalized master data. Keeping
  /// both aliases synchronized prevents search/catalog/report regressions.
  Map<String, dynamic> toCloudMap() {
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final normalizedCurrency = currency.trim().toUpperCase();
    return {
      'id': id,
      'vehicle_type': vehicleType,
      'vehicleType': vehicleType,
      'brand': brand,
      'make': brand,
      'model': model,
      'year': year,
      'color': color,
      'chassis': chassis,
      'vin': chassis,
      'engine_number': engineNumber,
      'engineNumber': engineNumber,
      'engine_no': engineNumber,
      'plate_number': plateNumber,
      'plateNumber': plateNumber,
      'plate': plateNumber,
      'car_number': carNumber,
      'carNumber': carNumber,
      'purchase_price': purchasePrice,
      'purchasePrice': purchasePrice,
      'costPrice': purchasePrice,
      'sale_price': salePrice,
      'salePrice': salePrice,
      'currency': normalizedCurrency,
      'cost_currency': (costCurrency ?? currency).trim().toUpperCase(),
      'costCurrency': (costCurrency ?? currency).trim().toUpperCase(),
      'sale_currency': (saleCurrency ?? currency).trim().toUpperCase(),
      'saleCurrency': (saleCurrency ?? currency).trim().toUpperCase(),
      'status': statusValue.name,
      'image_path': imagePath,
      'imagePath': imagePath,
      'image': imagePath,
      'maintenance_cost': maintenanceCost,
      'maintenanceCost': maintenanceCost,
      'warehouse_id': warehouseId,
      'warehouseId': warehouseId,
      'current_warehouse_id': warehouseId,
      'currentWarehouseId': warehouseId,
      'last_warehouse_id': warehouseId,
      'lastWarehouseId': warehouseId,
      'supplier_id': supplierId,
      'supplierId': supplierId,
      'supplier_name': supplierName,
      'supplierName': supplierName,
      'purchase_date': purchaseDate,
      'purchaseDate': purchaseDate,
      'notes': notes,
      'inventory_asset_account_id': inventoryAssetAccountId,
      'inventoryAssetAccountId': inventoryAssetAccountId,
      'sales_cost_expense_account_id': salesCostExpenseAccountId,
      'salesCostExpenseAccountId': salesCostExpenseAccountId,
      'sales_revenue_iqd_account_id': salesRevenueIqdAccountId,
      'salesRevenueIqdAccountId': salesRevenueIqdAccountId,
      'sales_revenue_usd_account_id': salesRevenueUsdAccountId,
      'salesRevenueUsdAccountId': salesRevenueUsdAccountId,
      'updated_at': updatedAt,
      'updatedAt': updatedAt,
      'schema_version': 4,
    };
  }

  factory CarModel.fromMap(Map<String, dynamic> map) => CarModel(
    id: ModelValueReader.string(map, 'id'),
    vehicleType: ModelValueReader.string(
      map,
      'vehicleType',
      aliases: const ['vehicle_type', 'type'],
    ),
    brand: ModelValueReader.string(map, 'brand', aliases: const ['make']),
    model: ModelValueReader.string(map, 'model'),
    year: ModelValueReader.integer(map, 'year'),
    color: ModelValueReader.string(map, 'color'),
    chassis: ModelValueReader.string(
      map,
      'chassis',
      aliases: const ['chassisNumber', 'chassis_number', 'vin'],
    ),
    engineNumber: ModelValueReader.string(
      map,
      'engineNumber',
      aliases: const ['engine_number', 'engine_no', 'motor_number'],
    ),
    plateNumber: ModelValueReader.string(
      map,
      'plateNumber',
      aliases: const ['plate_number', 'plate'],
    ),
    carNumber: ModelValueReader.string(
      map,
      'carNumber',
      aliases: const ['car_number'],
    ),
    purchasePrice: ModelValueReader.decimal(
      map,
      'purchasePrice',
      aliases: const ['purchase_price', 'costPrice'],
    ),
    salePrice: ModelValueReader.decimal(
      map,
      'salePrice',
      aliases: const ['sale_price'],
    ),
    currency: ModelValueReader.string(map, 'currency').toUpperCase(),
    costCurrency: ModelValueReader.nullableString(
      map,
      'costCurrency',
      aliases: const ['cost_currency'],
    )?.toUpperCase(),
    saleCurrency: ModelValueReader.nullableString(
      map,
      'saleCurrency',
      aliases: const ['sale_currency'],
    )?.toUpperCase(),
    status: CarStatusCodec.parse(map['status']).storageValue,
    imagePath: ModelValueReader.string(
      map,
      'imagePath',
      aliases: const ['image_path', 'image'],
    ),
    maintenanceCost: ModelValueReader.decimal(
      map,
      'maintenanceCost',
      aliases: const ['maintenance_cost'],
    ),
    warehouseId: ModelValueReader.nullableString(
      map,
      'warehouseId',
      aliases: const [
        'warehouse_id',
        'currentWarehouseId',
        'current_warehouse_id',
        'lastWarehouseId',
        'last_warehouse_id',
        'warehouseCode',
        'warehouseName',
      ],
    ),
    supplierId: ModelValueReader.nullableString(
      map,
      'supplierId',
      aliases: const ['supplier_id'],
    ),
    supplierName: ModelValueReader.nullableString(
      map,
      'supplierName',
      aliases: const ['supplier_name'],
    ),
    purchaseDate: ModelValueReader.nullableString(
      map,
      'purchaseDate',
      aliases: const ['purchase_date'],
    ),
    notes: ModelValueReader.nullableString(map, 'notes'),
    inventoryAssetAccountId: ModelValueReader.nullableString(
      map,
      'inventoryAssetAccountId',
      aliases: const ['inventory_asset_account_id'],
    ),
    salesCostExpenseAccountId: ModelValueReader.nullableString(
      map,
      'salesCostExpenseAccountId',
      aliases: const ['sales_cost_expense_account_id'],
    ),
    salesRevenueIqdAccountId: ModelValueReader.nullableString(
      map,
      'salesRevenueIqdAccountId',
      aliases: const ['sales_revenue_iqd_account_id'],
    ),
    salesRevenueUsdAccountId: ModelValueReader.nullableString(
      map,
      'salesRevenueUsdAccountId',
      aliases: const ['sales_revenue_usd_account_id'],
    ),
  );

  factory CarModel.fromCloudMap(Map<String, dynamic> map) =>
      CarModel.fromMap(map);

  @override
  bool operator ==(Object other) => other is CarModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
