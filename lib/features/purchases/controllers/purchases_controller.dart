import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_item_model.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';
import 'package:quality_line_erp/features/purchases/repositories/purchase_repository.dart';

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

  List<PurchaseModel> get purchases => filteredPurchases;

  List<PurchaseModel> get filteredPurchases =>
      UnifiedFilterEngine.apply<PurchaseModel>(
        _purchases,
        criteria: UnifiedFilterCriteria(
          searchText: query.state.search,
          statuses: _statusFilter,
          currencies: _currencyFilter,
        ),
        adapter: UnifiedFilterAdapter<PurchaseModel>(
          searchableText: (p) => <Object?>[
            p.invoiceNumber,
            p.supplierName,
            p.paymentMethod,
            p.notes,
            p.currencyCode,
          ],
          status: (p) => p.isPaid
              ? 'paid'
              : p.isPartial
                  ? 'partial'
                  : 'credit',
          currency: (p) => p.currencyCode,
          date: (p) => p.purchaseDate,
        ),
        sorts: _sortsFromQuery(),
      );

  Set<String> get _statusFilter {
    final token = query.state.filters
        .where((item) => item.key == 'paymentStatus')
        .firstOrNull;
    return token == null ? const <String>{} : {token.value.toString()};
  }

  Set<String> get _currencyFilter {
    final token = query.state.filters
        .where((item) => item.key == 'currency')
        .firstOrNull;
    return token == null ? const <String>{} : {token.value.toString()};
  }

  List<UnifiedSortCriterion<PurchaseModel>> _sortsFromQuery() =>
      query.state.sorts.map((rule) {
        final direction = rule.descending
            ? UnifiedSortDirection.descending
            : UnifiedSortDirection.ascending;

        Comparable<dynamic> value(PurchaseModel p) {
          switch (rule.field) {
            case 'invoiceNumber':
              return p.invoiceNumber.toLowerCase();
            case 'supplier':
              return p.supplierName.toLowerCase();
            case 'date':
              return p.purchaseDate;
            case 'total':
              return p.totalAmount;
            case 'remaining':
              return p.remainingAmount;
            default:
              return p.purchaseDate;
          }
        }

        return UnifiedSortCriterion<PurchaseModel>(
          key: rule.field,
          direction: direction,
          value: value,
        );
      }).toList(growable: false);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasLoaded => _hasLoaded;
  int get purchasesCount => _purchasesCount;

  Map<String, double> get totalPurchasesByCurrency =>
      Map.unmodifiable(_totalPurchasesByCurrency);

  Map<String, double> get totalPaidByCurrency =>
      Map.unmodifiable(_totalPaidByCurrency);

  Map<String, double> get totalRemainingByCurrency =>
      Map.unmodifiable(_totalRemainingByCurrency);

  List<PurchaseItemModel> getItemsForPurchase(String id) =>
      List.unmodifiable(_itemsByPurchaseId[id] ?? const []);

  PurchaseModel? getPurchaseById(String id) {
    for (final purchase in _purchases) {
      if (purchase.id == id) return purchase;
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
      _setError(
        userFacingError(
          error,
          isArabic: AppTranslation.isArabic,
          arabicFallback: 'تعذر تحميل بيانات المشتريات.',
        ),
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<List<PurchaseItemModel>> loadPurchaseItems(
    String id, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _itemsByPurchaseId.containsKey(id)) {
      return getItemsForPurchase(id);
    }
    _clearError();
    try {
      final items = await _repository.getPurchaseItems(id);
      _itemsByPurchaseId[id] = items;
      notifyListeners();
      return List.unmodifiable(items);
    } catch (error) {
      AppLogger.debug('PurchasesController.loadPurchaseItems failed: $error');
      _setError(
        userFacingError(
          error,
          isArabic: AppTranslation.isArabic,
          arabicFallback: 'تعذر تحميل بنود فاتورة الشراء.',
        ),
      );
      rethrow;
    }
  }

  Future<void> addPurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      if (await _repository.invoiceNumberExists(purchase.invoiceNumber)) {
        throw StateError('رقم فاتورة الشراء مستخدم مسبقًا.');
      }
      await _repository.addPurchase(purchase: purchase, items: items);
      AppDataChangeBus.instance.publish('purchases', operation: 'insert');
      await _refreshAfterMutation(purchaseId: purchase.id);
    } catch (error) {
      _setError(
        userFacingError(
          error,
          isArabic: AppTranslation.isArabic,
          arabicFallback: 'تعذر حفظ فاتورة الشراء.',
        ),
      );
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updatePurchase({
    required PurchaseModel purchase,
    required List<PurchaseItemModel> items,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      if (await _repository.invoiceNumberExists(
        purchase.invoiceNumber,
        excludePurchaseId: purchase.id,
      )) {
        throw StateError('رقم فاتورة الشراء مستخدم في فاتورة أخرى.');
      }
      await _repository.updatePurchase(purchase: purchase, items: items);
      AppDataChangeBus.instance.publish('purchases', operation: 'update');
      await _refreshAfterMutation(purchaseId: purchase.id);
    } catch (error) {
      _setError(
        userFacingError(
          error,
          isArabic: AppTranslation.isArabic,
          arabicFallback: 'تعذر تحديث فاتورة الشراء.',
        ),
      );
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deletePurchase(String id) async {
    _setLoading(true);
    _clearError();
    try {
      await _repository.deletePurchase(id);
      AppDataChangeBus.instance.publish('purchases', operation: 'delete');
      _itemsByPurchaseId.remove(id);
      await _refreshAfterMutation();
    } catch (error) {
      _setError(
        userFacingError(
          error,
          isArabic: AppTranslation.isArabic,
          arabicFallback: 'تعذر حذف فاتورة الشراء.',
        ),
      );
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> invoiceNumberExists(
    String number, {
    String? excludePurchaseId,
  }) => _repository.invoiceNumberExists(
    number,
    excludePurchaseId: excludePurchaseId,
  );

  Future<void> _refreshAfterMutation({String? purchaseId}) async {
    _purchases = await _repository.getPurchases();
    _recalculateSummaries();
    if (purchaseId != null) {
      _itemsByPurchaseId[purchaseId] =
          await _repository.getPurchaseItems(purchaseId);
    }
    notifyListeners();
  }

  void _recalculateSummaries() {
    _purchasesCount = _purchases.length;
    _totalPurchasesByCurrency = _sumByCurrency((p) => p.totalAmount);
    _totalPaidByCurrency = _sumByCurrency((p) => p.paidAmount);
    _totalRemainingByCurrency = _sumByCurrency((p) => p.remainingAmount);
  }

  Map<String, double> _sumByCurrency(
    double Function(PurchaseModel) valueOf,
  ) {
    final totals = <String, double>{};
    for (final p in _purchases) {
      final currency = p.currencyCode.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (v) => v + valueOf(p),
        ifAbsent: () => valueOf(p),
      );
    }
    return Map.unmodifiable(totals);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }
}
