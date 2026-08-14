import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/data/query_page.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';

import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_group_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_stock_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

class InventoryController extends ChangeNotifier {
  InventoryController({InventoryRepository? repository})
    : _repository = repository ?? InventoryRepository();

  final InventoryRepository _repository;

  List<InventoryModel> _items = [];
  List<InventoryModel> _maintenanceItems = [];
  DateTime? _maintenanceItemsLoadedAt;
  Future<void>? _maintenanceCatalogLoad;
  Future<void>? _inventoryLoad;
  String? _inventoryLoadWarehouseId;
  bool _inventoryReloadRequested = false;
  final Map<String, DateTime> _inventoryLoadedAt = <String, DateTime>{};
  List<WarehouseModel> _warehouses = [];
  List<WarehouseModel> _allWarehouses = [];
  List<InventoryGroupModel> _groups = [];
  bool _isLoading = false;
  String? _selectedWarehouseId;
  String _searchQuery = '';
  String? _selectedGroupId;

  List<InventoryModel> get items => List.unmodifiable(_items);
  List<InventoryModel> get maintenanceItems =>
      List.unmodifiable(_maintenanceItems.isEmpty ? _items : _maintenanceItems);
  List<WarehouseModel> get warehouses => List.unmodifiable(_warehouses);
  List<WarehouseModel> get allWarehouses => List.unmodifiable(_allWarehouses);
  List<InventoryGroupModel> get groups => List.unmodifiable(_groups);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _inventoryLoadedAt.isNotEmpty;
  String? get selectedWarehouseId => _selectedWarehouseId;
  String get searchQuery => _searchQuery;
  String? get selectedGroupId => _selectedGroupId;

  List<InventoryModel> get filteredItems =>
      UnifiedFilterEngine.apply<InventoryModel>(
        _items,
        criteria: UnifiedFilterCriteria(
          searchText: _searchQuery,
          groupIds: _selectedGroupId == null
              ? const <String>{}
              : <String>{_selectedGroupId!},
        ),
        adapter: UnifiedFilterAdapter<InventoryModel>(
          searchableText: (item) => <Object?>[
            item.code,
            item.sku,
            item.barcode,
            item.name,
            item.nameEn,
            item.category,
            item.unit,
            item.serialNumber,
            item.description,
          ],
          groupId: (item) => item.groupId,
          type: (item) => item.itemType,
          currency: (item) => item.costCurrency ?? item.currency,
        ),
      );

  Future<void> loadInventory({bool force = false}) {
    final warehouseId = _selectedWarehouseId;
    final cacheKey = warehouseId ?? '__all__';
    final loadedAt = _inventoryLoadedAt[cacheKey];
    if (!force &&
        _items.isNotEmpty &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(seconds: 45)) {
      return Future<void>.value();
    }
    final active = _inventoryLoad;
    if (active != null && _inventoryLoadWarehouseId == warehouseId) {
      if (force) _inventoryReloadRequested = true;
      return active;
    }

    final future = _loadInventoryLoop(warehouseId, cacheKey);
    _inventoryLoad = future;
    _inventoryLoadWarehouseId = warehouseId;
    return future.whenComplete(() {
      if (identical(_inventoryLoad, future)) {
        _inventoryLoad = null;
        _inventoryLoadWarehouseId = null;
      }
    });
  }

  Future<void> _loadInventoryLoop(String? warehouseId, String cacheKey) async {
    do {
      _inventoryReloadRequested = false;
      await _loadInventoryNow(warehouseId, cacheKey);
    } while (_inventoryReloadRequested && _selectedWarehouseId == warehouseId);
  }

  Future<void> _loadInventoryNow(String? warehouseId, String cacheKey) async {
    _isLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _repository.getWarehouses(includeInactive: true),
        _repository.getGroups(),
        _repository.getInventory(
          warehouseId: warehouseId,
          page: const QueryPage(limit: 500),
        ),
      ]);
      if (_selectedWarehouseId != warehouseId) return;
      _allWarehouses = results[0] as List<WarehouseModel>;
      _warehouses = _allWarehouses
          .where((warehouse) => warehouse.isActive)
          .toList(growable: false);
      _groups = results[1] as List<InventoryGroupModel>;
      _items = results[2] as List<InventoryModel>;
      _inventoryLoadedAt[cacheKey] = DateTime.now();
    } finally {
      if (_selectedWarehouseId == warehouseId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMaintenanceCatalog({bool force = false}) {
    final loadedAt = _maintenanceItemsLoadedAt;
    if (!force &&
        _maintenanceItems.isNotEmpty &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(minutes: 3)) {
      return Future<void>.value();
    }
    final active = _maintenanceCatalogLoad;
    if (!force && active != null) return active;

    final future = _loadMaintenanceCatalogNow();
    _maintenanceCatalogLoad = future;
    return future.whenComplete(() {
      if (identical(_maintenanceCatalogLoad, future)) {
        _maintenanceCatalogLoad = null;
      }
    });
  }

  Future<void> _loadMaintenanceCatalogNow() async {
    final items = await _repository.getInventory(
      page: const QueryPage(limit: 500),
    );
    _maintenanceItems = items.where((item) => item.isActive).toList();
    _maintenanceItemsLoadedAt = DateTime.now();
    notifyListeners();
  }

  void invalidateMaintenanceCatalog() {
    _maintenanceItemsLoadedAt = null;
  }

  void invalidateInventoryCache() {
    _inventoryLoadedAt.clear();
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    notifyListeners();
  }

  void setGroupFilter(String? value) {
    _selectedGroupId = value;
    notifyListeners();
  }

  Future<void> setWarehouseFilter(String? value) async {
    if (_selectedWarehouseId == value) return;
    _selectedWarehouseId = value;
    await loadInventory(force: true);
  }

  Future<void> addInventory(
    InventoryModel item, {
    String? warehouseId,
    required int openingQuantity,
    List<String> imagesBase64 = const [],
  }) async {
    try {
      await _repository.addInventory(
        item,
        warehouseId: warehouseId,
        openingQuantity: openingQuantity,
        imagesBase64: imagesBase64,
      );
    } catch (error, stackTrace) {
      // A network response can fail after PostgreSQL committed. Reconcile the
      // new UUID against the canonical store before reporting a failed save;
      // otherwise the user sees an error and later finds a "ghost" selector
      // entry that was actually committed.
      var committed = false;
      try {
        committed = await _repository.inventoryProductExists(item.id);
      } catch (_) {
        committed = false;
      }
      if (!committed) Error.throwWithStackTrace(error, stackTrace);
    }
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'insert');
    await loadInventory(force: true);
  }

  Future<void> updateInventory(
    InventoryModel item, {
    List<String> imagesBase64 = const [],
    String? warehouseId,
    int? openingQuantity,
  }) async {
    await _repository.updateInventory(
      item,
      imagesBase64: imagesBase64,
      warehouseId: warehouseId,
      openingQuantity: openingQuantity,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'update');
    await loadInventory(force: true);
  }

  Future<Map<String, dynamic>> inventoryDeleteImpact(String id) {
    return _repository.inventoryDeleteImpact(id);
  }

  Future<void> deleteInventory(String id) async {
    await _repository.deleteInventory(id);
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'delete');
    await loadInventory(force: true);
  }

  Future<List<String>> getProductImages(String productId) {
    return _repository.getProductImages(productId);
  }

  Future<Map<String, Object?>> getProductMaintenanceCard(String productId) {
    return _repository.getProductMaintenanceCard(productId);
  }

  Future<List<WarehouseStockModel>> getProductStocks(String productId) {
    return _repository.getProductStocks(productId);
  }

  Future<List<InventoryModel>> getInventoryForWarehouse(String warehouseId) {
    return _repository.getInventory(warehouseId: warehouseId);
  }

  Future<void> createWarehouse(WarehouseModel warehouse) async {
    await _repository.createWarehouse(warehouse);
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish(
      'inventory',
      operation: 'warehouse-insert',
    );
    await loadInventory(force: true);
  }

  Future<void> createGroup(InventoryGroupModel group) async {
    await _repository.createGroup(group);
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'group-insert');
    await loadInventory(force: true);
  }

  Future<void> updateWarehouse(WarehouseModel warehouse) async {
    await _repository.updateWarehouse(warehouse);
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish(
      'inventory',
      operation: 'warehouse-update',
    );
    await loadInventory(force: true);
  }

  Future<void> deleteWarehouse(String id) async {
    await _repository.deleteWarehouse(id);
    invalidateInventoryCache();
    if (_selectedWarehouseId == id) _selectedWarehouseId = null;
    AppDataChangeBus.instance.publish(
      'inventory',
      operation: 'warehouse-delete',
    );
    await loadInventory(force: true);
  }

  Future<void> updateGroup(InventoryGroupModel group) async {
    await _repository.updateGroup(group);
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'group-update');
    await loadInventory(force: true);
  }

  Future<void> deleteGroup(String id) async {
    await _repository.deleteGroup(id);
    invalidateInventoryCache();
    if (_selectedGroupId == id) _selectedGroupId = null;
    AppDataChangeBus.instance.publish('inventory', operation: 'group-delete');
    await loadInventory(force: true);
  }

  Future<void> receiveStock({
    required String productId,
    required String warehouseId,
    required int quantity,
    required double unitPurchasePrice,
    required double freightCost,
    required double customsCost,
    required double insuranceCost,
    required double otherCost,
    String? supplierId,
    String? supplierName,
    String? notes,
  }) async {
    await _repository.receiveStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: quantity,
      unitPurchasePrice: unitPurchasePrice,
      freightCost: freightCost,
      customsCost: customsCost,
      insuranceCost: insuranceCost,
      otherCost: otherCost,
      supplierId: supplierId,
      supplierName: supplierName,
      notes: notes,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'receive');
    await loadInventory(force: true);
  }

  Future<Map<String, Object?>> transferCar({
    required String carId,
    required String fromWarehouseId,
    required String toWarehouseId,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    final result = await _repository.transferCar(
      carId: carId,
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      notes: notes,
      effectiveAt: effectiveAt,
    );
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('cars', operation: 'warehouse_transfer');
    AppDataChangeBus.instance.publish('inventory', operation: 'car_transfer');
    notifyListeners();
    return result;
  }

  Future<Map<String, Object?>> transferStockBatch({
    required List<Map<String, Object?>> transferLines,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    final result = await _repository.transferStockBatch(
      transferLines: transferLines,
      notes: notes,
      effectiveAt: effectiveAt,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'transfer_batch');
    await loadInventory(force: true);
    return result;
  }

  Future<List<Map<String, Object?>>> getProductWarehouseTransfers() {
    return _repository.getProductWarehouseTransfers();
  }

  Future<Map<String, Object?>> updateProductWarehouseTransfer({
    required String transferId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required List<Map<String, Object?>> items,
    String? notes,
    String status = 'completed',
  }) async {
    final result = await _repository.updateProductWarehouseTransfer(
      transferId: transferId,
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      items: items,
      notes: notes,
      status: status,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish(
      'inventory',
      operation: 'warehouse-transfer-update',
      entityId: transferId,
    );
    await loadInventory(force: true);
    return result;
  }

  Future<void> deleteProductWarehouseTransfer(
    String transferId, {
    required String reason,
  }) async {
    await _repository.deleteProductWarehouseTransfer(
      transferId,
      reason: reason,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish(
      'inventory',
      operation: 'warehouse-transfer-delete',
      entityId: transferId,
    );
    await loadInventory(force: true);
  }

  Future<void> transferStock({
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int quantity,
    String? notes,
  }) async {
    await _repository.transferStock(
      productId: productId,
      fromWarehouseId: fromWarehouseId,
      toWarehouseId: toWarehouseId,
      quantity: quantity,
      notes: notes,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'transfer');
    await loadInventory(force: true);
  }

  Future<void> planExpectedMovement({
    required String productId,
    required String warehouseId,
    required bool incoming,
    required int quantity,
    String? notes,
  }) async {
    await _repository.planExpectedMovement(
      productId: productId,
      warehouseId: warehouseId,
      incoming: incoming,
      quantity: quantity,
      notes: notes,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'plan');
    await loadInventory(force: true);
  }

  Future<void> sellStock({
    required String productId,
    required String warehouseId,
    required int quantity,
    required double unitSalePrice,
    String? customerName,
    String? notes,
  }) async {
    await _repository.sellStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: quantity,
      unitSalePrice: unitSalePrice,
      customerName: customerName,
      notes: notes,
    );
    invalidateMaintenanceCatalog();
    invalidateInventoryCache();
    AppDataChangeBus.instance.publish('inventory', operation: 'sale');
    await loadInventory(force: true);
  }

  int get totalItems => _items.length;

  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  int get expectedQuantity =>
      _items.fold(0, (sum, item) => sum + item.expectedQuantity);

  int get lowStockItems => _items.where((item) => item.isLowStock).length;

  Map<String, double> get totalValueByCurrency {
    final totals = <String, double>{};
    for (final item in _items.where((item) => item.isStockItem)) {
      final currency = (item.costCurrency ?? item.currency)
          .trim()
          .toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + item.stockValue,
        ifAbsent: () => item.stockValue,
      );
    }
    return Map.unmodifiable(totals);
  }
}
