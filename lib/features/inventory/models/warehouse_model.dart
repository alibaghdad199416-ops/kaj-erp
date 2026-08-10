class WarehouseModel {
  const WarehouseModel({
    required this.id,
    required this.code,
    required this.name,
    required this.address,
    required this.isActive,
    this.branchId,
    this.notes,
    this.warehouseType = 'normal',
    this.inventoryAccountId,
    this.scrapExpenseAccountId,
    this.scrapExpenseIqdAccountId,
    this.scrapExpenseUsdAccountId,
  });

  final String id;
  final String code;
  final String name;
  final String? branchId;
  final String address;
  final String? notes;
  final bool isActive;
  final String warehouseType;
  final String? inventoryAccountId;
  final String? scrapExpenseAccountId;
  final String? scrapExpenseIqdAccountId;
  final String? scrapExpenseUsdAccountId;

  factory WarehouseModel.fromMap(Map<String, dynamic> map) => WarehouseModel(
    id:
        (map['id'] ?? map['warehouseId'] ?? map['warehouse_id'])?.toString() ??
        '',
    code:
        (map['code'] ?? map['warehouseCode'] ?? map['warehouse_code'])
            ?.toString() ??
        '',
    name:
        (map['name'] ?? map['warehouseName'] ?? map['warehouse_name'])
            ?.toString() ??
        '',
    branchId: (map['branchId'] ?? map['branch_id'])?.toString(),
    address: map['address']?.toString() ?? '',
    notes: map['notes']?.toString(),
    isActive: _asBool(map['isActive'] ?? map['is_active']),
    warehouseType:
        (map['warehouseType'] ?? map['warehouse_type'])?.toString() ?? 'normal',
    inventoryAccountId: map['inventoryAccountId']?.toString(),
    scrapExpenseAccountId: map['scrapExpenseAccountId']?.toString(),
    scrapExpenseIqdAccountId:
        (map['scrapExpenseIqdAccountId'] ?? map['scrap_expense_iqd_account_id'])
            ?.toString(),
    scrapExpenseUsdAccountId:
        (map['scrapExpenseUsdAccountId'] ?? map['scrap_expense_usd_account_id'])
            ?.toString(),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'code': code,
    'name': name,
    'branchId': branchId,
    'address': address,
    'notes': notes,
    'isActive': isActive,
    'warehouseType': warehouseType,
    'inventoryAccountId': inventoryAccountId,
    'scrapExpenseAccountId': scrapExpenseAccountId,
    'scrapExpenseIqdAccountId': scrapExpenseIqdAccountId,
    'scrapExpenseUsdAccountId': scrapExpenseUsdAccountId,
    'createdAt': DateTime.now().toIso8601String(),
  };

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {
      '1',
      'true',
      'yes',
      'on',
    }.contains(value?.toString().trim().toLowerCase());
  }
}
