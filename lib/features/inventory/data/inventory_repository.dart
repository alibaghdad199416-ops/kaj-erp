import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/data/query_page.dart';
import 'package:quality_line_erp/core/data/ttl_cache.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_group_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_movement_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_stock_model.dart';

/// Supabase-only inventory repository.
///
/// PostgreSQL is authoritative. Failures are surfaced to the caller instead of
/// being hidden behind a secondary data store.
class InventoryRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;
  final TtlCache<String, Object> _lookupCache = TtlCache<String, Object>(
    ttl: const Duration(minutes: 2),
  );

  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  String get _userName {
    final user = Supabase.instance.client.auth.currentUser;
    final fullName = user?.userMetadata?['full_name']?.toString().trim();
    return fullName?.isNotEmpty == true
        ? fullName!
        : (user?.email ?? 'ERP user');
  }

  Future<List<InventoryModel>> getInventory({
    String? warehouseId,
    QueryPage page = const QueryPage(),
  }) async {
    final products = await _cloud.list('erp_inventory');
    // Warehouse stock records exist in both historical camelCase and current
    // snake_case shapes. Loading once and filtering locally keeps the filter
    // correct for both schemas instead of silently returning master quantities.
    final allStockRows = await _cloud.list('erp_warehouse_stock');
    final normalizedWarehouseId = warehouseId?.trim();
    final stockRows = normalizedWarehouseId == null
        ? allStockRows
        : allStockRows
              .where((row) {
                final rowWarehouseId = _textValue(row, const [
                  'warehouseId',
                  'warehouse_id',
                ]);
                return rowWarehouseId == normalizedWarehouseId;
              })
              .toList(growable: false);
    final totals = <String, Map<String, num>>{};
    for (final row in stockRows) {
      final productId = _textValue(row, const [
        'productId',
        'product_id',
        'inventoryId',
        'inventory_id',
      ]);
      if (productId.isEmpty) continue;
      final total = totals.putIfAbsent(
        productId,
        () => <String, num>{
          'quantity': 0,
          'expectedIncoming': 0,
          'expectedOutgoing': 0,
          'value': 0.0,
        },
      );
      final quantity = _numberValue(row, const ['quantity']);
      final average = _numberValue(row, const [
        'averageUnitCost',
        'average_unit_cost',
        'unitCost',
        'unit_cost',
      ]);
      total['quantity'] = (total['quantity'] ?? 0) + quantity;
      total['expectedIncoming'] =
          (total['expectedIncoming'] ?? 0) +
          _numberValue(row, const ['expectedIncoming', 'expected_incoming']);
      total['expectedOutgoing'] =
          (total['expectedOutgoing'] ?? 0) +
          _numberValue(row, const ['expectedOutgoing', 'expected_outgoing']);
      total['value'] = (total['value'] ?? 0) + (quantity * average);
    }

    final visibleProducts = normalizedWarehouseId == null
        ? products
        : products
              .where((row) {
                final id = row['id']?.toString().trim() ?? '';
                return id.isNotEmpty && totals.containsKey(id);
              })
              .toList(growable: false);
    final mapped =
        visibleProducts.map((row) {
          final id = row['id']?.toString().trim() ?? '';
          final total = totals[id];
          final quantity = normalizedWarehouseId == null
              ? (total?['quantity'] ?? _numberValue(row, const ['quantity']))
                    .toInt()
              : (total?['quantity'] ?? 0).toInt();
          final value = (total?['value'] ?? 0).toDouble();
          return InventoryModel.fromMap(<String, dynamic>{
            ...row,
            'quantity': quantity,
            'expectedIncoming':
                (total?['expectedIncoming'] ??
                        (normalizedWarehouseId == null
                            ? _numberValue(row, const [
                                'expectedIncoming',
                                'expected_incoming',
                              ])
                            : 0))
                    .toInt(),
            'expectedOutgoing':
                (total?['expectedOutgoing'] ??
                        (normalizedWarehouseId == null
                            ? _numberValue(row, const [
                                'expectedOutgoing',
                                'expected_outgoing',
                              ])
                            : 0))
                    .toInt(),
            'warehouseId': ?normalizedWarehouseId,
            if (quantity > 0) 'unitCost': value / quantity,
          });
        }).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return mapped.skip(page.offset).take(page.limit).toList(growable: false);
  }

  static String _textValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static num _numberValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value is num) return value;
      final parsed = num.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  Future<List<InventoryMovementModel>> getMovementHistory({
    QueryPage page = const QueryPage(),
    String? productId,
  }) async {
    final results = await Future.wait<Object?>([
      Supabase.instance.client.rpc(
        'erp_r28_inventory_movement_log',
        params: <String, Object?>{
          'p_company_id': CloudTenantContext.instance.companyUuid,
          'p_product_id': productId,
        },
      ),
      _cloud.list('erp_inventory'),
    ]);
    final raw = results[0];
    final products = (results[1] as List<Map<String, dynamic>>);
    final productCurrencyById = <String, String>{
      for (final product in products)
        if ((product['id']?.toString().trim() ?? '').isNotEmpty)
          product['id'].toString(): _textValue(product, const [
            'costCurrency',
            'cost_currency',
            'currency',
          ]).toUpperCase(),
    };
    final rows = (raw as List)
        .whereType<Map>()
        .map((row) {
          final mapped = Map<String, dynamic>.from(row);
          final movementCurrency = _textValue(mapped, const [
            'currency',
            'costCurrency',
            'cost_currency',
          ]);
          if (movementCurrency.isEmpty) {
            final movementProductId = _textValue(mapped, const [
              'productId',
              'product_id',
            ]);
            mapped['currency'] = productCurrencyById[movementProductId] ?? '';
          }
          return mapped;
        })
        .toList(growable: false);
    return rows
        .skip(page.offset)
        .take(page.limit)
        .map(InventoryMovementModel.fromMap)
        .toList(growable: false);
  }

  Future<Map<String, Object?>> getProductMaintenanceCard(
    String productId,
  ) async {
    final result = await _client.rpc(
      'erp_r57_product_maintenance_card',
      params: <String, Object?>{
        'p_company_id': _companyId,
        'p_product_id': productId,
      },
    );
    return result is Map
        ? Map<String, Object?>.from(result)
        : const <String, Object?>{};
  }

  Future<List<WarehouseModel>> getWarehouses({
    bool includeInactive = false,
  }) async {
    final rows = await _cloud.list('erp_warehouses');
    final result =
        rows
            .map(WarehouseModel.fromMap)
            .where((warehouse) => includeInactive || warehouse.isActive)
            .toList(growable: false)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return result;
  }

  Future<List<InventoryGroupModel>> getGroups() async {
    final cached = _lookupCache.get('groups');
    if (cached is List<InventoryGroupModel>) return cached;
    final rows = await _cloud.list('erp_inventory_groups');
    final result = rows.map(InventoryGroupModel.fromMap).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _lookupCache.put('groups', result);
    return result;
  }

  Future<List<WarehouseStockModel>> getProductStocks(String productId) async {
    final rows = await _cloud.listWhere(
      'erp_warehouse_stock',
      field: 'productId',
      value: productId,
    );
    final stocks = rows
        .map(WarehouseStockModel.fromMap)
        .where((stock) => stock.warehouseId.isNotEmpty)
        .toList(growable: false);
    stocks.sort((a, b) => b.availableQuantity.compareTo(a.availableQuantity));
    return stocks;
  }

  /// Returns only source warehouses that can actually satisfy a transfer.
  /// PostgreSQL remains authoritative and rechecks the quantity atomically.
  Future<List<WarehouseStockModel>> getTransferableProductStocks(
    String productId,
  ) async => (await getProductStocks(
    productId,
  )).where((stock) => stock.availableQuantity > 0).toList(growable: false);

  Future<List<String>> getProductImages(String productId) async {
    final rows = await _cloud.listWhere(
      'erp_product_images',
      field: 'productId',
      value: productId,
    );
    rows.sort(
      (a, b) => ((a['sortOrder'] as num?)?.toInt() ?? 0).compareTo(
        (b['sortOrder'] as num?)?.toInt() ?? 0,
      ),
    );
    return rows
        .map((row) => row['imageBase64']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> addInventory(
    InventoryModel item, {
    String? warehouseId,
    required int openingQuantity,
    List<String> imagesBase64 = const [],
  }) async {
    item.validate();
    if (openingQuantity < 0) throw ArgumentError('الرصيد الافتتاحي غير صحيح');
    await _client.rpc(
      'erp_r49_create_inventory_product',
      params: {
        'p_company_id': _companyId,
        'p_product_id': item.id,
        'p_product': item.toMap(),
        'p_warehouse_id': warehouseId,
        'p_opening_quantity': openingQuantity,
        'p_images': imagesBase64,
        'p_user_name': _userName,
      },
    );
  }

  Future<bool> inventoryProductExists(String id) async =>
      await _cloud.getById('erp_inventory', id) != null;

  Future<void> updateInventory(
    InventoryModel item, {
    List<String> imagesBase64 = const [],
    String? warehouseId,
    int? openingQuantity,
  }) async {
    item.validate();
    await _client.rpc(
      'erp_r49_update_inventory_product',
      params: {
        'p_company_id': _companyId,
        'p_product_id': item.id,
        'p_product': item.toMap()..remove('createdAt'),
        'p_images': imagesBase64,
      },
    );
    if (warehouseId != null && openingQuantity != null) {
      await _client.rpc(
        'erp_r49_adjust_product_opening_balance',
        params: {
          'p_company_id': _companyId,
          'p_product_id': item.id,
          'p_warehouse_id': warehouseId,
          'p_new_opening_quantity': openingQuantity,
          'p_user_name': _userName,
        },
      );
    }
  }

  Future<Map<String, dynamic>> inventoryDeleteImpact(String id) async {
    final response = await _client.rpc(
      'erp_inventory_product_delete_impact',
      params: {'p_company_id': _companyId, 'p_product_id': id},
    );
    return response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{};
  }

  Future<void> deleteInventory(String id) async {
    await _client.rpc(
      'erp_delete_inventory_product',
      params: {'p_company_id': _companyId, 'p_product_id': id},
    );
  }

  Future<void> createWarehouse(WarehouseModel warehouse) async {
    await _cloud.upsert('erp_warehouses', warehouse.id, warehouse.toMap());
    await _verifyWarehousePersistence(warehouse);
  }

  Future<void> createGroup(InventoryGroupModel group) async {
    await _cloud.upsert('erp_inventory_groups', group.id, group.toMap());
    _lookupCache.invalidate();
  }

  Future<void> updateWarehouse(WarehouseModel warehouse) async {
    final existing = await _cloud.getById('erp_warehouses', warehouse.id);
    if (existing == null) throw StateError('المخزن غير موجود أو تعذر تحديثه');
    await _cloud.upsert(
      'erp_warehouses',
      warehouse.id,
      warehouse.toMap()..remove('createdAt'),
    );
    await _verifyWarehousePersistence(warehouse);
  }

  Future<void> _verifyWarehousePersistence(WarehouseModel expected) async {
    final raw = await _cloud.getById('erp_warehouses', expected.id);
    if (raw == null) throw StateError('warehouse_persistence_readback_failed');
    final actual = WarehouseModel.fromMap(raw);
    String? normalized(String? value) {
      final text = value?.trim() ?? '';
      return text.isEmpty ? null : text;
    }

    if (actual.id != expected.id ||
        actual.code.trim() != expected.code.trim() ||
        actual.name.trim() != expected.name.trim() ||
        normalized(actual.branchId) != normalized(expected.branchId) ||
        actual.address.trim() != expected.address.trim() ||
        normalized(actual.notes) != normalized(expected.notes) ||
        actual.isActive != expected.isActive ||
        actual.warehouseType != expected.warehouseType ||
        normalized(actual.inventoryAccountId) !=
            normalized(expected.inventoryAccountId) ||
        normalized(actual.scrapExpenseAccountId) !=
            normalized(expected.scrapExpenseAccountId) ||
        normalized(actual.scrapExpenseIqdAccountId) !=
            normalized(expected.scrapExpenseIqdAccountId) ||
        normalized(actual.scrapExpenseUsdAccountId) !=
            normalized(expected.scrapExpenseUsdAccountId)) {
      throw StateError('warehouse_persistence_readback_mismatch');
    }
  }

  Future<void> deleteWarehouse(String id) async {
    final cars = await _cloud.listWhere(
      'erp_cars',
      field: 'warehouseId',
      value: id,
    );
    final stocks = await _cloud.listWhere(
      'erp_warehouse_stock',
      field: 'warehouseId',
      value: id,
    );
    if (cars.isNotEmpty ||
        stocks.any((row) => ((row['quantity'] as num?) ?? 0) != 0)) {
      throw StateError('لا يمكن حذف مخزن مرتبط بسيارات أو أرصدة');
    }
    await _cloud.delete('erp_warehouses', id);
  }

  Future<void> updateGroup(InventoryGroupModel group) async {
    final existing = await _cloud.getById('erp_inventory_groups', group.id);
    if (existing == null)
      throw StateError('المجموعة غير موجودة أو تعذر تحديثها');
    await _cloud.upsert(
      'erp_inventory_groups',
      group.id,
      group.toMap()..remove('createdAt'),
    );
    _lookupCache.invalidate();
  }

  Future<void> deleteGroup(String id) async {
    final products = await _cloud.listWhere(
      'erp_inventory',
      field: 'groupId',
      value: id,
    );
    if (products.isNotEmpty)
      throw StateError('لا يمكن حذف مجموعة مرتبطة بمنتجات');
    await _cloud.delete('erp_inventory_groups', id);
    _lookupCache.invalidate();
  }

  Future<Map<String, Object?>> transferCar({
    required String carId,
    required String fromWarehouseId,
    required String toWarehouseId,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    if (fromWarehouseId == toWarehouseId)
      throw ArgumentError('يجب اختيار مخزنين مختلفين');
    final result = await _client.rpc(
      'erp_r49_create_car_warehouse_transfer',
      params: {
        'p_company_id': _companyId,
        'p_car_id': carId,
        'p_to_warehouse_id': toWarehouseId,
        'p_user_name': _userName,
        'p_notes': notes,
        'p_effective_at': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
    );
    final row = result is Map
        ? Map<String, Object?>.from(result)
        : <String, Object?>{};
    final transferId = row['id']?.toString() ?? '';
    if (transferId.isEmpty) {
      throw StateError('لم تُرجع خدمة نقل السيارة رقم سند صالحاً');
    }
    return <String, Object?>{
      ...row,
      'id': transferId,
      'fromWarehouseId': fromWarehouseId,
      'toWarehouseId': toWarehouseId,
    };
  }

  Future<Map<String, Object?>> transferStockBatch({
    required List<Map<String, Object?>> transferLines,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    if (transferLines.isEmpty) {
      throw ArgumentError('يجب إضافة مادة واحدة على الأقل');
    }
    final result = await _client.rpc(
      'erp_r49_transfer_inventory_stock_batch',
      params: {
        'p_company_id': _companyId,
        'p_lines': transferLines,
        'p_notes': notes,
        'p_effective_at': (effectiveAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
      },
    );
    if (result is Map) return Map<String, Object?>.from(result);
    throw StateError('لم تُرجع خدمة النقل رقم سند صالحاً');
  }

  Future<List<Map<String, Object?>>> getProductWarehouseTransfers() async {
    final result = await _client.rpc(
      'erp_r49_list_inventory_warehouse_transfers',
      params: {'p_company_id': _companyId},
    );
    if (result is! List) return const <Map<String, Object?>>[];
    return result
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, Object?>> updateProductWarehouseTransfer({
    required String transferId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<Map<String, Object?>> items,
    String? notes,
    String status = 'completed',
  }) async {
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('يجب اختيار مخزنين مختلفين');
    }
    if (items.isEmpty) {
      throw ArgumentError('يجب إضافة مادة واحدة على الأقل');
    }
    final result = await _client.rpc(
      'erp_update_inventory_warehouse_transfer',
      params: {
        'p_company_id': _companyId,
        'p_transfer_id': transferId,
        'p_from_warehouse_id': fromWarehouseId,
        'p_to_warehouse_id': toWarehouseId,
        'p_items': items,
        'p_notes': notes,
        'p_status': status,
      },
    );
    if (result is Map) return Map<String, Object?>.from(result);
    return <String, Object?>{'transferId': transferId};
  }

  Future<void> deleteProductWarehouseTransfer(
    String transferId, {
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError('سبب الحذف مطلوب');
    }
    final result = await _client.rpc(
      'erp_delete_inventory_warehouse_transfer_v2',
      params: {
        'p_company_id': _companyId,
        'p_transfer_id': transferId,
        'p_reason': normalizedReason,
      },
    );
    if (result is! Map || result['deleted'] != true) {
      throw StateError('تعذر حذف سند النقل وعكس ارتباطاته بالكامل.');
    }
  }

  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  }) async {
    if (fromWarehouseId == toWarehouseId)
      throw ArgumentError('يجب اختيار مخزنين مختلفين');
    if (quantity <= 0) throw ArgumentError('يجب أن تكون الكمية أكبر من صفر');
    await _client.rpc(
      'erp_r49_transfer_inventory_stock',
      params: {
        'p_company_id': _companyId,
        'p_product_id': productId,
        'p_from_warehouse_id': fromWarehouseId,
        'p_to_warehouse_id': toWarehouseId,
        'p_quantity': quantity,
        'p_notes': notes,
      },
    );
  }

  Future<void> planExpectedMovement({
    required String productId,
    required String warehouseId,
    required bool incoming,
    required int quantity,
    String? notes,
  }) async {
    if (quantity <= 0)
      throw ArgumentError('يجب أن تكون الكمية المتوقعة أكبر من صفر');
    await _client.rpc(
      'erp_r49_plan_inventory_movement',
      params: {
        'p_company_id': _companyId,
        'p_product_id': productId,
        'p_warehouse_id': warehouseId,
        'p_incoming': incoming,
        'p_quantity': quantity,
        'p_notes': notes,
      },
    );
  }
}
