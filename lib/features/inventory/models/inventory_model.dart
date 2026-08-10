import 'package:quality_line_erp/core/models/model_value_reader.dart';

class InventoryModel {
  const InventoryModel({
    required this.id,
    required this.name,
    required this.code,
    required this.serialNumber,
    required this.category,
    required this.groupId,
    required this.unit,
    required this.quantity,
    required this.purchasePrice,
    required this.landedCost,
    required this.unitCost,
    required this.salePrice,
    required this.minQuantity,
    required this.expectedIncoming,
    required this.expectedOutgoing,
    required this.date,
    this.nameEn = '',
    this.description = '',
    this.sku = '',
    this.barcode = '',
    this.currency = 'IQD',
    this.costCurrency,
    this.saleCurrency,
    this.taxRate = 0,
    this.imageBase64,
    this.notes,
    this.isActive = true,
    this.itemType = 'stock',
    this.inventoryAssetAccountId,
    this.salesCostExpenseAccountId,
    this.salesRevenueIqdAccountId,
    this.salesRevenueUsdAccountId,
  });

  final String id;
  final String name;
  final String nameEn;
  final String description;
  final String code;
  final String sku;
  final String barcode;
  final String serialNumber;
  final String category;
  final String groupId;
  final String unit;
  final int quantity;
  final double purchasePrice;
  final double landedCost;
  final double unitCost;
  final double salePrice;
  final String currency;
  final String? costCurrency;
  final String? saleCurrency;
  final double taxRate;
  final int minQuantity;
  final int expectedIncoming;
  final int expectedOutgoing;
  final String date;
  final String? imageBase64;
  final String? notes;
  final bool isActive;

  /// stock = quantity tracked; service = non-stock, sale/maintenance only.
  final String itemType;
  final String? inventoryAssetAccountId;
  final String? salesCostExpenseAccountId;
  final String? salesRevenueIqdAccountId;
  final String? salesRevenueUsdAccountId;

  bool get isService => itemType == 'service';
  bool get isStockItem => !isService;

  int get expectedQuantity => quantity + expectedIncoming - expectedOutgoing;
  int get availableQuantity => quantity - expectedOutgoing;
  bool get isLowStock => quantity <= minQuantity;
  double get stockValue => quantity * unitCost;
  double get expectedGrossProfitPerUnit => salePrice - unitCost;

  void validate() {
    if (id.trim().isEmpty) throw ArgumentError('مرجع المنتج غير صالح');
    if (name.trim().isEmpty) throw ArgumentError('اسم المادة مطلوب');
    if (itemType != 'stock' && itemType != 'service') {
      throw ArgumentError('نوع المادة يجب أن يكون مخزنيًا أو خدمة');
    }
    if (isService && quantity != 0) {
      throw ArgumentError('الخدمة لا تملك كمية مخزنية');
    }
    if (quantity < 0 || minQuantity < 0) {
      throw ArgumentError('الكميات لا يمكن أن تكون سالبة');
    }
    if (purchasePrice < 0 || landedCost < 0 || unitCost < 0 || salePrice < 0) {
      throw ArgumentError('الأسعار والتكاليف لا يمكن أن تكون سالبة');
    }
    if (taxRate < 0 || taxRate > 100) {
      throw ArgumentError('نسبة الضريبة يجب أن تكون بين 0 و100');
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency != 'IQD' && normalizedCurrency != 'USD') {
      throw ArgumentError('عملة المنتج يجب أن تكون IQD أو USD');
    }
  }

  InventoryModel copyWith({
    String? id,
    String? name,
    String? nameEn,
    String? description,
    String? code,
    String? sku,
    String? barcode,
    String? serialNumber,
    String? category,
    String? groupId,
    String? unit,
    int? quantity,
    double? purchasePrice,
    double? landedCost,
    double? unitCost,
    double? salePrice,
    String? currency,
    String? costCurrency,
    String? saleCurrency,
    double? taxRate,
    int? minQuantity,
    int? expectedIncoming,
    int? expectedOutgoing,
    String? date,
    String? imageBase64,
    String? notes,
    bool? isActive,
    String? itemType,
    String? inventoryAssetAccountId,
    String? salesCostExpenseAccountId,
    String? salesRevenueIqdAccountId,
    String? salesRevenueUsdAccountId,
  }) {
    return InventoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      description: description ?? this.description,
      code: code ?? this.code,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      serialNumber: serialNumber ?? this.serialNumber,
      category: category ?? this.category,
      groupId: groupId ?? this.groupId,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      landedCost: landedCost ?? this.landedCost,
      unitCost: unitCost ?? this.unitCost,
      salePrice: salePrice ?? this.salePrice,
      currency: currency ?? this.currency,
      costCurrency: costCurrency ?? this.costCurrency,
      saleCurrency: saleCurrency ?? this.saleCurrency,
      taxRate: taxRate ?? this.taxRate,
      minQuantity: minQuantity ?? this.minQuantity,
      expectedIncoming: expectedIncoming ?? this.expectedIncoming,
      expectedOutgoing: expectedOutgoing ?? this.expectedOutgoing,
      date: date ?? this.date,
      imageBase64: imageBase64 ?? this.imageBase64,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      itemType: itemType ?? this.itemType,
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

  factory InventoryModel.fromMap(Map<String, dynamic> map) {
    final purchasePrice = ModelValueReader.decimal(
      map,
      'purchasePrice',
      aliases: const ['purchase_price'],
    );
    final landedCost = ModelValueReader.decimal(
      map,
      'landedCost',
      aliases: const ['landed_cost'],
    );
    final storedUnitCost = ModelValueReader.decimal(
      map,
      'unitCost',
      aliases: const ['unit_cost'],
    );
    return InventoryModel(
      id: ModelValueReader.string(map, 'id'),
      name: ModelValueReader.string(
        map,
        'name',
        aliases: const ['nameAr', 'name_ar'],
      ),
      nameEn: ModelValueReader.string(
        map,
        'nameEn',
        aliases: const ['name_en'],
      ),
      description: ModelValueReader.string(
        map,
        'description',
        aliases: const ['descriptionAr', 'description_ar'],
      ),
      code: ModelValueReader.string(map, 'code'),
      sku: ModelValueReader.string(map, 'sku'),
      barcode: ModelValueReader.string(map, 'barcode'),
      serialNumber: ModelValueReader.string(
        map,
        'serialNumber',
        aliases: const ['serial_number'],
      ),
      category: ModelValueReader.string(map, 'category', fallback: 'عام'),
      groupId: ModelValueReader.string(
        map,
        'groupId',
        aliases: const ['group_id'],
        fallback: 'inventory-group-general',
      ),
      unit: ModelValueReader.string(map, 'unit', fallback: 'قطعة'),
      quantity: ModelValueReader.integer(map, 'quantity'),
      purchasePrice: purchasePrice,
      landedCost: landedCost,
      unitCost: storedUnitCost == 0
          ? purchasePrice + landedCost
          : storedUnitCost,
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
      taxRate: ModelValueReader.decimal(
        map,
        'taxRate',
        aliases: const ['tax_rate', 'taxPercent'],
      ),
      minQuantity: ModelValueReader.integer(
        map,
        'minQuantity',
        aliases: const ['min_quantity', 'minimumQuantity'],
      ),
      expectedIncoming: ModelValueReader.integer(
        map,
        'expectedIncoming',
        aliases: const ['expected_incoming'],
      ),
      expectedOutgoing: ModelValueReader.integer(
        map,
        'expectedOutgoing',
        aliases: const ['expected_outgoing'],
      ),
      date: ModelValueReader.string(
        map,
        'date',
        aliases: const ['createdAt', 'created_at'],
        fallback: '',
      ),
      imageBase64: ModelValueReader.nullableString(
        map,
        'imageBase64',
        aliases: const ['image_base64'],
      ),
      notes: ModelValueReader.nullableString(map, 'notes'),
      itemType: ModelValueReader.string(
        map,
        'itemType',
        aliases: const ['item_type', 'productType', 'product_type'],
        fallback: 'stock',
      ).toLowerCase(),
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
      isActive: ModelValueReader.boolean(
        map,
        'isActive',
        aliases: const ['is_active'],
        fallback: false,
      ),
    );
  }

  factory InventoryModel.fromCloudMap(Map<String, dynamic> map) =>
      InventoryModel.fromMap(map);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'nameAr': name,
    'nameEn': nameEn,
    'description': description,
    'code': code,
    'sku': sku,
    'barcode': barcode,
    'serialNumber': serialNumber,
    'category': category,
    'groupId': groupId,
    'unit': unit,
    'quantity': quantity,
    'purchasePrice': purchasePrice,
    'landedCost': landedCost,
    'unitCost': unitCost,
    'salePrice': salePrice,
    'currency': currency.trim().toUpperCase(),
    'costCurrency': (costCurrency ?? currency).trim().toUpperCase(),
    'saleCurrency': (saleCurrency ?? currency).trim().toUpperCase(),
    'taxRate': taxRate,
    'minQuantity': minQuantity,
    'minimumQuantity': minQuantity,
    'expectedIncoming': expectedIncoming,
    'expectedOutgoing': expectedOutgoing,
    'date': date,
    'createdAt': date,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'imageBase64': imageBase64,
    'notes': notes,
    'isActive': isActive,
    'itemType': itemType,
    'inventoryAssetAccountId': inventoryAssetAccountId,
    'salesCostExpenseAccountId': salesCostExpenseAccountId,
    'salesRevenueIqdAccountId': salesRevenueIqdAccountId,
    'salesRevenueUsdAccountId': salesRevenueUsdAccountId,
    'schemaVersion': 4,
  };

  Map<String, dynamic> toCloudMap() {
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return {
      ...toMap(),
      'name_ar': name,
      'name_en': nameEn,
      'serial_number': serialNumber,
      'group_id': groupId,
      'purchase_price': purchasePrice,
      'landed_cost': landedCost,
      'unit_cost': unitCost,
      'sale_price': salePrice,
      'cost_currency': (costCurrency ?? currency).trim().toUpperCase(),
      'sale_currency': (saleCurrency ?? currency).trim().toUpperCase(),
      'tax_rate': taxRate,
      'min_quantity': minQuantity,
      'expected_incoming': expectedIncoming,
      'expected_outgoing': expectedOutgoing,
      'created_at': date,
      'updated_at': updatedAt,
      'image_base64': imageBase64,
      'is_active': isActive,
      'item_type': itemType,
      'product_type': itemType,
      'inventory_asset_account_id': inventoryAssetAccountId,
      'sales_cost_expense_account_id': salesCostExpenseAccountId,
      'sales_revenue_iqd_account_id': salesRevenueIqdAccountId,
      'sales_revenue_usd_account_id': salesRevenueUsdAccountId,
      'schema_version': 4,
    };
  }

  @override
  bool operator ==(Object other) => other is InventoryModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
