import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';

class MaintenanceController extends ChangeNotifier {
  MaintenanceController({MaintenanceRepository? repository})
    : _repository = repository ?? MaintenanceRepository();

  final MaintenanceRepository _repository;
  List<MaintenanceOrderModel> _orders = [];
  bool _isLoading = false;
  Future<void>? _ordersLoadInFlight;
  bool _ordersReloadRequested = false;
  DateTime? _ordersLoadedAt;
  static const Duration _ordersTtl = Duration(seconds: 20);
  List<MaintenanceVehicleOption> _eligibleVehicles = [];
  Future<void>? _eligibleLoadInFlight;
  DateTime? _eligibleLoadedAt;
  String? _eligibleVehiclesError;
  static const Duration _eligibleTtl = Duration(seconds: 45);

  List<MaintenanceOrderModel> get orders => List.unmodifiable(_orders);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _ordersLoadedAt != null;
  List<MaintenanceVehicleOption> get eligibleVehicles =>
      List.unmodifiable(_eligibleVehicles);
  String? get eligibleVehiclesError => _eligibleVehiclesError;

  Future<void> loadEligibleVehicles({bool force = false}) async {
    final loadedAt = _eligibleLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _eligibleTtl) {
      return;
    }
    final inFlight = _eligibleLoadInFlight;
    if (inFlight != null) return inFlight;

    final request = _loadEligibleVehiclesNow();
    _eligibleLoadInFlight = request;
    try {
      await request;
    } finally {
      if (identical(_eligibleLoadInFlight, request)) {
        _eligibleLoadInFlight = null;
      }
    }
  }

  Future<void> _loadEligibleVehiclesNow() async {
    try {
      final vehicles = await _repository.getEligibleVehicles();
      _eligibleVehicles = vehicles;
      _eligibleLoadedAt = DateTime.now();
      _eligibleVehiclesError = null;
    } catch (error) {
      _eligibleVehiclesError = error.toString();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  void invalidateEligibleVehicles() {
    _eligibleLoadedAt = null;
  }

  Future<void> loadOrders({bool force = false}) {
    final loadedAt = _ordersLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _ordersTtl) {
      return Future<void>.value();
    }
    final active = _ordersLoadInFlight;
    if (active != null) {
      if (force) _ordersReloadRequested = true;
      return active;
    }

    final request = _loadOrdersLoop();
    _ordersLoadInFlight = request;
    return request.whenComplete(() {
      if (identical(_ordersLoadInFlight, request)) {
        _ordersLoadInFlight = null;
      }
    });
  }

  Future<void> _loadOrdersLoop() async {
    do {
      _ordersReloadRequested = false;
      await _loadOrdersNow();
    } while (_ordersReloadRequested);
  }

  Future<void> _loadOrdersNow() async {
    _isLoading = true;
    notifyListeners();
    try {
      _orders = await _repository.getOrders();
      _ordersLoadedAt = DateTime.now();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createDraftOrder({
    required String carId,
    required String warehouseId,
    required String pricingType,
    required double laborCost,
    required double salePrice,
    required List<MaintenancePartRequest> parts,
    required String currencyCode,
    String? maintenanceExpenseAccountId,
    String? opportunityId,
    String? notes,
    DateTime? effectiveAt,
  }) async {
    await _repository.createDraftOrder(
      carId: carId,
      warehouseId: warehouseId,
      pricingType: pricingType,
      laborCost: laborCost,
      salePrice: salePrice,
      parts: parts,
      currencyCode: currencyCode,
      maintenanceExpenseAccountId: maintenanceExpenseAccountId,
      opportunityId: opportunityId,
      notes: notes,
      effectiveAt: effectiveAt,
    );
    await loadOrders(force: true);
    _publishChange('insert');
  }

  Future<void> updateDraft({
    required String orderId,
    required String warehouseId,
    required String pricingType,
    required double laborCost,
    required double salePrice,
    required List<MaintenancePartRequest> parts,
    required String currencyCode,
    String? maintenanceExpenseAccountId,
    String? notes,
    DateTime? effectiveAt,
    required DateTime expectedUpdatedAt,
  }) async {
    await _repository.updateDraft(
      orderId: orderId,
      warehouseId: warehouseId,
      pricingType: pricingType,
      laborCost: laborCost,
      salePrice: salePrice,
      parts: parts,
      currencyCode: currencyCode,
      maintenanceExpenseAccountId: maintenanceExpenseAccountId,
      notes: notes,
      effectiveAt: effectiveAt,
      expectedUpdatedAt: expectedUpdatedAt,
    );
    await loadOrders(force: true);
    _publishChange('update', entityId: orderId);
  }

  Future<List<MaintenanceLineModel>> getOrderLines(String orderId) =>
      _repository.getOrderLines(orderId);

  Future<MaintenanceCostReconciliation> getCostReconciliation(String orderId) =>
      _repository.getCostReconciliation(orderId);

  Future<MaintenanceOrderModel?> findByOpportunity(String opportunityId) =>
      _repository.findByOpportunity(opportunityId);

  Future<void> deleteOrder(String orderId, {String? reason}) async {
    await _repository.deleteOrder(orderId, reason: reason);
    await loadOrders(force: true);
    _publishChange('delete', entityId: orderId);
  }

  Future<void> advanceWorkflow(String orderId) async {
    await _repository.advanceWorkflow(orderId);
    await loadOrders(force: true);
    _publishChange('workflow', entityId: orderId);
  }

  Future<List<Map<String, Object?>>> listCashAccounts() =>
      _repository.listCashAccounts();

  Future<List<Map<String, Object?>>> listSettlementAccounts() =>
      _repository.listSettlementAccounts();

  Future<void> recordPaymentsBatch(
    String orderId,
    List<Map<String, Object?>> payments,
  ) async {
    await _repository.recordPaymentsBatch(orderId, payments);
    await loadOrders(force: true);
    _publishChange('payment', entityId: orderId);
  }

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _repository.cancelOrder(orderId, reason: reason);
    await loadOrders(force: true);
    _publishChange('cancel', entityId: orderId);
  }

  void _publishChange(String operation, {String? entityId}) {
    invalidateEligibleVehicles();
    AppDataChangeBus.instance.publish(
      'maintenance',
      operation: operation,
      entityId: entityId,
    );

    if (<String>{
      'workflow',
      'cancel',
      'delete',
      'update',
    }.contains(operation)) {
      AppDataChangeBus.instance.publish(
        'inventory',
        operation: operation,
        entityId: entityId,
      );
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: operation,
        entityId: entityId,
      );
      AppDataChangeBus.instance.publish(
        'cars',
        operation: operation,
        entityId: entityId,
      );
    }
    if (operation == 'payment') {
      AppDataChangeBus.instance.publish(
        'cashbox',
        operation: operation,
        entityId: entityId,
      );
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: operation,
        entityId: entityId,
      );
    }
  }

  Map<String, double> get paidRevenueByCurrency => _sumByCurrency(
    _orders.where((order) => order.pricingType == 'paid'),
    (order) => order.salePrice,
  );

  Map<String, double> get totalCostByCurrency {
    final totals = <String, double>{};
    for (final order in _orders) {
      for (final entry in order.operationalCostTotalsByCurrency.entries) {
        totals.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    return Map<String, double>.unmodifiable(totals);
  }

  Map<String, double> get inventoryCarCostAddedByCurrency =>
      _sumByCurrency(_orders, (order) => order.carCostAdded);

  Map<String, double> _sumByCurrency(
    Iterable<MaintenanceOrderModel> orders,
    double Function(MaintenanceOrderModel order) valueOf,
  ) {
    final totals = <String, double>{};
    for (final order in orders) {
      final currency = order.currencyCode.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + valueOf(order),
        ifAbsent: () => valueOf(order),
      );
    }
    return Map.unmodifiable(totals);
  }

  int get freeServices =>
      _orders.where((order) => order.pricingType == 'free').length;
}
