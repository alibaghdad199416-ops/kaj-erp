import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/repositories/cashbox_repository.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class CashboxController extends ChangeNotifier {
  CashboxController({CashboxRepository? repository})
    : _repository = repository ?? CashboxRepository();

  final CashboxRepository _repository;
  List<CashTransactionModel> _transactions = [];
  List<CashTransactionModel> _allTransactions = [];
  List<CashAccountModel> _cashAccounts = [];
  List<AccountModel> _ledgerAccounts = [];
  Map<String, double> _balances = {};
  Map<String, Map<String, double>> _reconciliation = {};
  bool _isLoading = false;
  Future<void>? _refreshInFlight;
  bool _refreshRequested = false;
  String _activeSearchQuery = '';
  String? _errorMessage;
  Map<String, double> _usdSummary = const {
    'receipts': 0,
    'payments': 0,
    'balance': 0,
  };
  Map<String, double> _iqdSummary = const {
    'receipts': 0,
    'payments': 0,
    'balance': 0,
  };

  List<CashTransactionModel> get transactions =>
      List.unmodifiable(_transactions);
  List<CashAccountModel> get cashAccounts => List.unmodifiable(_cashAccounts);
  List<AccountModel> get ledgerAccounts => List.unmodifiable(_ledgerAccounts);
  Map<String, double> get balances => Map.unmodifiable(_balances);
  Map<String, Map<String, double>> get reconciliation =>
      Map.unmodifiable(_reconciliation);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, double> get usdSummary => Map.unmodifiable(_usdSummary);
  Map<String, double> get iqdSummary => Map.unmodifiable(_iqdSummary);

  Future<void> loadTransactions() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _refresh();
    } catch (error) {
      AppLogger.debug('cashbox_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل الصناديق والحركات.',
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<void> saveCashAccount(CashAccountModel account) async {
    _setLoading(true);
    try {
      await _repository.saveCashAccount(account);
      AppDataChangeBus.instance.publish('cashbox', operation: 'account_save');
      await _refresh(force: true);
    } catch (error) {
      AppLogger.debug('cashbox_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حفظ الصندوق.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteCashAccount(String id) async {
    _setLoading(true);
    try {
      await _repository.deleteCashAccount(id);
      AppDataChangeBus.instance.publish(
        'cashbox',
        operation: 'account_delete',
        entityId: id,
      );
      await _refresh(force: true);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> transferBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required double sourceAmount,
    required double targetAmount,
    required double exchangeRate,
    required DateTime transferDate,
    String? notes,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.transferBetweenCashAccounts(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        sourceAmount: sourceAmount,
        targetAmount: targetAmount,
        exchangeRate: exchangeRate,
        transferDate: transferDate,
        notes: notes,
      );
      AppDataChangeBus.instance.publish('cashbox', operation: 'transfer');
      await _refresh(force: true);
    } catch (error) {
      AppLogger.debug('cashbox_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحويل الأموال بين الصناديق.',
      );
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteTransfer(String transferId) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.deleteCashTransfer(transferId);
      AppDataChangeBus.instance.publish(
        'cashbox',
        operation: 'transfer_delete',
      );
      await _refresh(force: true);
    } catch (error) {
      AppLogger.debug('cashbox_controller operation failed: $error');
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حذف تحويل الصناديق.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addTransaction(CashTransactionModel transaction) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      // PostgreSQL's active-voucher unique index is the race-safe authority.
      // A preflight getTransactions() duplicated a full cash read and could
      // still lose a race between the check and the atomic posting RPC.
      await _repository.addTransaction(transaction);
      AppDataChangeBus.instance.publish('cashbox', operation: 'insert');
      await _refresh(force: true);
    } catch (error) {
      AppLogger.debug('cashbox_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حفظ حركة الصندوق.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateTransaction(CashTransactionModel transaction) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.updateTransaction(transaction);
      AppDataChangeBus.instance.publish(
        'cashbox',
        operation: 'update',
        entityId: transaction.id,
      );
      await _refresh(force: true);
    } catch (error) {
      AppLogger.debug('cashbox_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحديث حركة الصندوق.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteTransaction(String id) async {
    _setLoading(true);
    try {
      await _repository.deleteTransaction(id);
      AppDataChangeBus.instance.publish(
        'cashbox',
        operation: 'delete',
        entityId: id,
      );
      await _refresh(force: true);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> searchTransactions(String query) {
    _activeSearchQuery = query.trim().toLowerCase();
    _applySearch();
    notifyListeners();
    return Future<void>.value();
  }

  Future<void> _refresh({bool force = false}) {
    if (force) _refreshRequested = true;
    final active = _refreshInFlight;
    if (active != null) return active;

    final request = _runRefreshLoop();
    _refreshInFlight = request;
    return request.whenComplete(() {
      if (identical(_refreshInFlight, request)) _refreshInFlight = null;
    });
  }

  Future<void> _runRefreshLoop() async {
    var refreshAgain = true;
    while (refreshAgain) {
      _refreshRequested = false;
      await _performRefresh();
      refreshAgain = _refreshRequested;
    }
  }

  Future<void> _performRefresh() async {
    final results = await Future.wait<dynamic>([
      _repository.getTransactions(),
      _repository.getCashAccounts(),
      _repository.getLedgerAccounts(),
      _repository.getCashAccountBalances(),
      _repository.getCurrencySummary('USD'),
      _repository.getCurrencySummary('IQD'),
      _repository.getCashLedgerReconciliation(),
    ]);
    _allTransactions = results[0] as List<CashTransactionModel>;
    _applySearch();
    _cashAccounts = results[1] as List<CashAccountModel>;
    _ledgerAccounts = results[2] as List<AccountModel>;
    _balances = results[3] as Map<String, double>;
    _usdSummary = results[4] as Map<String, double>;
    _iqdSummary = results[5] as Map<String, double>;
    _reconciliation = results[6] as Map<String, Map<String, double>>;
    notifyListeners();
  }

  void _applySearch() {
    final query = _activeSearchQuery;
    if (query.isEmpty) {
      _transactions = List<CashTransactionModel>.of(_allTransactions);
      return;
    }
    _transactions = _allTransactions
        .where((item) {
          return item.voucherNumber.toLowerCase().contains(query) ||
              item.category.toLowerCase().contains(query) ||
              item.currency.toLowerCase().contains(query) ||
              item.type.toLowerCase().contains(query) ||
              (item.partyName ?? '').toLowerCase().contains(query) ||
              (item.notes ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  void _setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }
}
