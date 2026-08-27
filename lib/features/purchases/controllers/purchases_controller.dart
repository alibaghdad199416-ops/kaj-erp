import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';

import 'package:quality_line_erp/features/purchases/models/purchase_item_model.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';
import 'package:quality_line_erp/features/purchases/repositories/purchase_repository.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class PurchasesController extends ChangeNotifier {
  PurchasesController({PurchaseRepository? repository})
    : _repository = repository ?? PurchaseRepository() {
    query.addListener(_notifyQueryChanged);
  }

  final PurchaseRepository _repository;
  final UnifiedQueryController query = UnifiedQueryController();

  List<PurchaseModel> _purchases = [];
  final Map<String, List<PurchaseItemModel>> _itemsByPurchaseId = {};
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasLoaded = false;
  int _purchasesCount = 0;
  Map<String, double> _totalPurchasesByCurrency = const {};
  Map<String, double> _totalPaidByCurrency = const {};
  Map<String, double> _totalRemainingByCurrency = const {};

  @override
  void dispose() {
    query.removeListener(_notifyQueryChanged);
    query.dispose();
    super.dispose();
  }

  void _notifyQueryChanged() => notifyListeners();

  List<PurchaseModel> get purchases => List.unmodifiable(_purchases);
  List<PurchaseModel> get filteredPurchases => UnifiedFilterEngine.apply<PurchaseModel>(
    _purchases,
    criteria: UnifiedFilterCriteria(
      searchText: query.state.search,
      statuses: _paymentStatusesFromQuery(),
      currencies: _currenciesFromQuery(),
    ),
    adapter: UnifiedFilterAdapter<PurchaseModel>(
      searchableText: (purchase) => <Object?>[
        purchase.invoiceNumber,
        purchase.supplierName,
        purchase.paymentMethod,
        purchase.notes,
        purchase.currencyCode,
      ],
      status: (purchase) => purchase.isPaid
          ? 'paid'
          : purchase.isPartial
              ? 'partial'
              : 'credit',
      currency: (purchase) => purchase.currencyCode,
      date: (purchase) => purchase.purchaseDate,
    ),
    sorts: _sortsFromQuery(),
  );

  Set<String> _paymentStatusesFromQuery() {
    final token = query.state.filters.where((item) => item.key == 'paymentStatus').firstOrNull;
    return token == null ? const <String>{} : {token.value.toString()};
  }

  Set<String> _currenciesFromQuery() {
    final token = query.state.filters.where((item) => item.key == 'currency').firstOrNull;
    return token == null ? const <String>{} : {token.value.toString()};
  }

  List<UnifiedSortCriterion<PurchaseModel>> _sortsFromQuery() {
    return query.state.sorts.map((rule) {
      final direction = rule.descending
          ? UnifiedSortDirection.descending
          : UnifiedSortDirection.ascending;
      Comparable<dynamic> value(PurchaseModel purchase) {
        switch (rule.field) {
          case 'invoiceNumber': return purchase.invoiceNumber.toLowerCase();
          case 'supplier': return purchase.supplierName.toLowerCase();
          case 'date': return purchase.purchaseDate;
          case 'total': return purchase.totalAmount;
          case 'remaining': return purchase.remainingAmount;
          default: return purchase.purchaseDate;
        }
      }
      return UnifiedSortCriterion<PurchaseModel>(
        key: rule.field,
        direction: direction,
        value: value,
      );
    }).toList(growable: false);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasLoaded => _hasLoaded;
  int get purchasesCount => _purchasesCount;
  Map<String, double> get totalPurchasesByCurrency => Map.unmodifiable(_totalPurchasesByCurrency);
  Map<String, double> get totalPaidByCurrency => Map.unmodifiable(_totalPaidByCurrency);
  Map<String, double> get totalRemainingByCurrency => Map.unmodifiable(_totalRemainingByCurrency);

  List<PurchaseItemModel> getItemsForPurchase(String purchaseId) =>
      List.unmodifiable(_itemsByPurchaseId[purchaseId] ?? const []);

  PurchaseModel? getPurchaseById(String purchaseId) {
    for (final purchase in _purchases) {
      if (purchase.id == purchaseId) return purchase;
    }
    return null;
  }

  Future<void> loadPurchases() async {
    _setLoading(true);
    _clearError();
    try {
      _purchases = await _repository.getPurchases();
      _recalculateSummaries();
      _itemsByPurchaseId.clear();
      _hasLoaded = true;
    } catch (error) {
      AppLogger.debug('PurchasesController.loadPurchases failed: $error');
      _setError(userFacingError(error, isArabic: AppTranslation.isArabic, arabicFallback: 'تعذر تحميل بيانات المشتريات.'));
    } finally {
      _setLoading(false);
    }
  }

  Future<List<PurchaseItemModel>> loadPurchaseItems(String purchaseId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _itemsByPurchaseId.containsKey(purchaseId)) return getItemsForPurchase(purchaseId);
    _clearError();
    try {
      final items = await _repository.getPurchaseItems(purchaseId);
      _itemsByPurchaseId[purchaseId] = items;
      notifyListeners();
      return List.unmodifiable(items);
    } catch (error) {
      AppLogger.debug('PurchasesController.loadPurchaseItems failed: $error');
      _setError(userFacingError(error, isArabic: AppTranslation.isArabic, arabicFallback: 'تعذر تحميل بنود فاتورة الشراء.'));
      rethrow;
    }
  }

  Future<void> addPurchase({required PurchaseModel purchase, required List<PurchaseItemModel> items}) async {
    _setLoading(true); _clearError();
    try {
      if (await _repository.invoiceNumberExists(purchase.invoiceNumber)) throw StateError('رقم فاتورة الشراء مستخدم مسبقًا.');
      await _repository.addPurchase(purchase: purchase, items: items);
      AppDataChangeBus.instance.publish('purchases', operation: 'insert');
      await _refreshAfterMutation(purchaseId: purchase.id);
    } catch (error) {
      AppLogger.debug('PurchasesController.addPurchase failed: $error');
      _setError(userFacingError(error, isArabic: AppTranslation.isArabic, arabicFallback: 'تعذر حفظ فاتورة الشراء.')); rethrow;
    } finally { _setLoading(false); }
  }

  Future<void> updatePurchase({required PurchaseModel purchase, required List<PurchaseItemModel> items}) async {
    _setLoading(true); _clearError();
    try {
      if (await _repository.invoiceNumberExists(purchase.invoiceNumber, excludePurchaseId: purchase.id)) throw StateError('رقم فاتورة الشراء مستخدم في فاتورة أخرى.');
      await _repository.updatePurchase(purchase: purchase, items: items);
      AppDataChangeBus.instance.publish('purchases', operation: 'update');
      await _refreshAfterMutation(purchaseId: purchase.id);
    } catch (error) {
      AppLogger.debug('PurchasesController.updatePurchase failed: $error');
      _setError(userFacingError(error, isArabic: AppTranslation.isArabic, arabicFallback: 'تعذر تحديث فاتورة الشراء.')); rethrow;
    } finally { _setLoading(false); }
  }

  Future<void> deletePurchase(String purchaseId) async {
    _setLoading(true); _clearError();
    try {
      await _repository.deletePurchase(purchaseId);
      AppDataChangeBus.instance.publish('purchases', operation: 'delete');
      _itemsByPurchaseId.remove(purchaseId);
      await _refreshAfterMutation();
    } catch (error) {
      AppLogger.debug('PurchasesController.deletePurchase failed: $error');
      _setError(userFacingError(error, isArabic: AppTranslation.isArabic, arabicFallback: 'تعذر حذف فاتورة الشراء.')); rethrow;
    } finally { _setLoading(false); }
  }

  @Deprecated('Use query.setSearch() and filteredPurchases')
  Future<void> searchPurchases(String value) async => query.setSearch(value);

  Future<void> clearSearch() async { query.clear(); }

  Future<bool> invoiceNumberExists(String invoiceNumber, {String? excludePurchaseId}) =>
      _repository.invoiceNumberExists(invoiceNumber, excludePurchaseId: excludePurchaseId);

  Future<void> _refreshAfterMutation({String? purchaseId}) async {
    _purchases = await _repository.getPurchases();
    _recalculateSummaries();
    if (purchaseId != null) _itemsByPurchaseId[purchaseId] = await _repository.getPurchaseItems(purchaseId);
    notifyListeners();
  }

  void _recalculateSummaries() {
    _purchasesCount = _purchases.length;
    _totalPurchasesByCurrency = _sumByCurrency((p) => p.totalAmount);
    _totalPaidByCurrency = _sumByCurrency((p) => p.paidAmount);
    _totalRemainingByCurrency = _sumByCurrency((p) => p.remainingAmount);
  }

  Map<String, double> _sumByCurrency(double Function(PurchaseModel) valueOf) {
    final totals = <String, double>{};
    for (final purchase in _purchases) {
      final currency = purchase.currencyCode.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(currency, (value) => value + valueOf(purchase), ifAbsent: () => valueOf(purchase));
    }
    return Map.unmodifiable(totals);
  }

  void _setLoading(bool value) { _isLoading = value; notifyListeners(); }
  void _setError(String message) { _errorMessage = message; notifyListeners(); }
  void _clearError() { _errorMessage = null; }
}
