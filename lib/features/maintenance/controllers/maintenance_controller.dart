import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

class MaintenanceController extends ChangeNotifier {
  final MaintenanceRepository _repository = MaintenanceRepository();
  final UnifiedQueryController query = UnifiedQueryController();
  List<MaintenanceOrderModel> _orders = [];
  bool _isLoading = false;
  Future<void>? _ordersLoadInFlight;
  DateTime? _ordersLoadedAt;
  static const Duration _ordersTtl = Duration(seconds: 20);
  List<MaintenanceVehicleOption> _eligibleVehicles = [];
  Future<void>? _eligibleLoadInFlight;
  DateTime? _eligibleLoadedAt;
  String? _eligibleVehiclesError;
  static const Duration _eligibleTtl = Duration(seconds: 45);

  MaintenanceController() {
    query.addListener(_notifyQueryChanged);
  }

  @override
  void dispose() {
    query.removeListener(_notifyQueryChanged);
    query.dispose();
    super.dispose();
  }

  void _notifyQueryChanged() => notifyListeners();

  DateTime _dateOf(MaintenanceOrderModel order) =>
      DateTime.tryParse(order.maintenanceDate) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  List<MaintenanceOrderModel> get orders => filteredOrders;

  List<MaintenanceOrderModel> get filteredOrders =>
      UnifiedFilterEngine.apply<MaintenanceOrderModel>(
        _orders,
        criteria: UnifiedFilterCriteria(
          searchText: query.state.search,
          statuses: _stageFilter,
          currencies: _currencyFilter,
        ),
        adapter: UnifiedFilterAdapter<MaintenanceOrderModel>(
          searchableText: (order) => <Object?>[
            order.orderNumber,
            order.carName,
            order.customerName,
            order.invoiceNumber,
          ],
          status: (order) => order.workflowStage,
          currency: (order) => order.currencyCode,
          date: _dateOf,
        ),
        sorts: _sortsFromQuery(),
      );

  Set<String> get _stageFilter {
    final token = query.state.filters
        .where((item) => item.key == 'workflowStage')
        .firstOrNull;
    return token == null ? const <String>{} : {token.value.toString()};
  }

  Set<String> get _currencyFilter {
    final token = query.state.filters
        .where((item) => item.key == 'currency')
        .firstOrNull;
    return token == null ? const <String>{} : {token.value.toString()};
  }

  List<UnifiedSortCriterion<MaintenanceOrderModel>> _sortsFromQuery() => query
      .state
      .sorts
      .map((rule) {
        final direction = rule.descending
            ? UnifiedSortDirection.descending
            : UnifiedSortDirection.ascending;
        Comparable<dynamic> value(MaintenanceOrderModel order) {
          switch (rule.field) {
            case 'orderNumber':
              return order.orderNumber.toLowerCase();
            case 'vehicle':
              return order.carName.toLowerCase();
            case 'customer':
              return (order.customerName ?? '').toLowerCase();
            case 'cost':
              return order.totalCost;
            case 'price':
              return order.salePrice;
            case 'date':
              return _dateOf(order);
            default:
              return _dateOf(order);
          }
        }

        return UnifiedSortCriterion<MaintenanceOrderModel>(
          key: rule.field,
          direction: direction,
          value: value,
        );
      })
      .toList(growable: false);

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
    if (active != null) return active;

    final request = _loadOrdersNow();
    _ordersLoadInFlight = request;
    return request.whenComplete(() {
      if (identical(_ordersLoadInFlight, request)) {
        _ordersLoadInFlight = null;
      }
    });
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

  Map<String, double> get totalCostByCurrency =>
      _sumByCurrency(_orders, (order) => order.totalCost);

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
