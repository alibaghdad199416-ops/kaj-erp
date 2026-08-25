import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/purchases/models/purchase_item_model.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';
import 'package:quality_line_erp/features/purchases/repositories/purchase_repository.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class PurchasesController extends ChangeNotifier {
  PurchasesController({PurchaseRepository? repository})
    : _repository = repository ?? PurchaseRepository();

  final PurchaseRepository _repository;

  List<PurchaseModel> _purchases = [];
  final Map<String, List<PurchaseItemModel>> _itemsByPurchaseId = {};

  bool _isLoading = false;
  String? _errorMessage;
  bool _hasLoaded = false;

  int _purchasesCount = 0;
  Map<String, double> _totalPurchasesByCurrency = const {};
  Map<String, double> _totalPaidByCurrency = const {};
  Map<String, double> _totalRemainingByCurrency = const {};

  List<PurchaseModel> get purchases => List.unmodifiable(_purchases);

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

  List<PurchaseItemModel> getItemsForPurchase(String purchaseId) {
    return List.unmodifiable(_itemsByPurchaseId[purchaseId] ?? const []);
  }

  PurchaseModel? getPurchaseById(String purchaseId) {
    for (final purchase in _purchases) {
      if (purchase.id == purchaseId) {
        return purchase;
      }
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
    String purchaseId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _itemsByPurchaseId.containsKey(purchaseId)) {
      return getItemsForPurchase(purchaseId);
    }

    _clearError();

    try {
      final items = await _repository.getPurchaseItems(purchaseId);

      _itemsByPurchaseId[purchaseId] = items;
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
      final exists = await _repository.invoiceNumberExists(
        purchase.invoiceNumber,
      );

      if (exists) {
        throw StateError('رقم فاتورة الشراء مستخدم مسبقًا.');
      }

      await _repository.addPurchase(purchase: purchase, items: items);
      AppDataChangeBus.instance.publish('purchases', operation: 'insert');

      await _refreshAfterMutation(purchaseId: purchase.id);
    } catch (error) {
      AppLogger.debug('PurchasesController.addPurchase failed: $error');
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
      final exists = await _repository.invoiceNumberExists(
        purchase.invoiceNumber,
        excludePurchaseId: purchase.id,
      );

      if (exists) {
        throw StateError('رقم فاتورة الشراء مستخدم في فاتورة أخرى.');
      }

      await _repository.updatePurchase(purchase: purchase, items: items);
      AppDataChangeBus.instance.publish('purchases', operation: 'update');

      await _refreshAfterMutation(purchaseId: purchase.id);
    } catch (error) {
      AppLogger.debug('PurchasesController.updatePurchase failed: $error');
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

  Future<void> deletePurchase(String purchaseId) async {
    _setLoading(true);
    _clearError();

    try {
      await _repository.deletePurchase(purchaseId);
      AppDataChangeBus.instance.publish('purchases', operation: 'delete');

      _itemsByPurchaseId.remove(purchaseId);

      await _refreshAfterMutation();
    } catch (error) {
      AppLogger.debug('PurchasesController.deletePurchase failed: $error');
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

  Future<void> searchPurchases(String query) async {
    _setLoading(true);
    _clearError();

    try {
      _purchases = await _repository.searchPurchases(query);

      _itemsByPurchaseId.clear();
    } catch (error) {
      AppLogger.debug('PurchasesController.searchPurchases failed: $error');
      _setError(
        userFacingError(
          error,
          isArabic: AppTranslation.isArabic,
          arabicFallback: 'تعذر البحث في فواتير الشراء.',
        ),
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> clearSearch() async {
    await loadPurchases();
  }

  Future<bool> invoiceNumberExists(
    String invoiceNumber, {
    String? excludePurchaseId,
  }) {
    return _repository.invoiceNumberExists(
      invoiceNumber,
      excludePurchaseId: excludePurchaseId,
    );
  }

  Future<void> _refreshAfterMutation({String? purchaseId}) async {
    _purchases = await _repository.getPurchases();
    _recalculateSummaries();

    if (purchaseId != null) {
      _itemsByPurchaseId[purchaseId] = await _repository.getPurchaseItems(
        purchaseId,
      );
    }

    notifyListeners();
  }

  void _recalculateSummaries() {
    _purchasesCount = _purchases.length;
    _totalPurchasesByCurrency = _sumByCurrency(
      (purchase) => purchase.totalAmount,
    );
    _totalPaidByCurrency = _sumByCurrency((purchase) => purchase.paidAmount);
    _totalRemainingByCurrency = _sumByCurrency(
      (purchase) => purchase.remainingAmount,
    );
  }

  Map<String, double> _sumByCurrency(
    double Function(PurchaseModel purchase) valueOf,
  ) {
    final totals = <String, double>{};
    for (final purchase in _purchases) {
      final currency = purchase.currencyCode.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + valueOf(purchase),
        ifAbsent: () => valueOf(purchase),
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
