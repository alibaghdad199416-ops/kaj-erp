import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_result.dart';
import 'package:quality_line_erp/features/accounting/models/journal_entry_model.dart';
import 'package:quality_line_erp/features/accounting/models/journal_line_model.dart';
import 'package:quality_line_erp/features/accounting/repositories/accounting_repository.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class AccountingController extends ChangeNotifier {
  AccountingController({AccountingRepository? repository})
    : _repository = repository ?? AccountingRepository() {
    query.addListener(_onQueryChanged);
  }

  final AccountingRepository _repository;
  final UnifiedQueryController query = UnifiedQueryController();
  List<AccountModel> _accounts = [];
  List<JournalEntryModel> _entries = [];
  final Map<String, List<JournalLineModel>> _lines = {};
  bool _isLoading = false;
  String? _errorMessage;
  Map<String, double> _usdTrial = const {'debit': 0, 'credit': 0};
  Map<String, double> _iqdTrial = const {'debit': 0, 'credit': 0};
  Map<String, double> _receivablesByCurrency = const {};
  Map<String, double> _payablesByCurrency = const {};
  Future<void>? _accountsLoadFuture;

  List<AccountModel> get accounts => List.unmodifiable(_accounts);
  List<JournalEntryModel> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Map<String, double> get usdTrial => Map.unmodifiable(_usdTrial);
  Map<String, double> get iqdTrial => Map.unmodifiable(_iqdTrial);
  Map<String, double> get receivablesByCurrency =>
      Map.unmodifiable(_receivablesByCurrency);
  Map<String, double> get payablesByCurrency =>
      Map.unmodifiable(_payablesByCurrency);

  List<JournalEntryModel> get visibleEntries => UnifiedFilterEngine.apply(
    _entries,
    criteria: UnifiedFilterCriteria(
      searchText: query.state.search,
      statuses: {
        for (final token in query.state.filters)
          if (token.key == 'status') token.value.toString(),
      },
      currencies: {
        for (final token in query.state.filters)
          if (token.key == 'currency') token.value.toString(),
      },
    ),
    adapter: UnifiedFilterAdapter<JournalEntryModel>(
      searchableText: (entry) => <Object?>[
        entry.entryNumber,
        entry.description,
        entry.currency,
        entry.status,
        entry.referenceType,
        entry.referenceId,
      ],
      status: (entry) => entry.status,
      currency: (entry) => entry.currency,
      date: (entry) => entry.entryDate,
    ),
    sorts: query.state.sorts
        .map((rule) {
          Comparable<dynamic> value(JournalEntryModel entry) {
            switch (rule.field) {
              case 'entryNumber':
                return entry.entryNumber;
              case 'description':
                return entry.description;
              case 'currency':
                return entry.currency;
              case 'status':
                return entry.status;
              case 'totalDebit':
                return entry.totalDebit;
              case 'totalCredit':
                return entry.totalCredit;
              case 'entryDate':
              default:
                return entry.entryDate;
            }
          }

          return UnifiedSortCriterion<JournalEntryModel>(
            key: rule.field,
            value: value,
            direction: rule.descending
                ? UnifiedSortDirection.descending
                : UnifiedSortDirection.ascending,
          );
        })
        .toList(growable: false),
  );

  void _onQueryChanged() => notifyListeners();

  Future<void> ensureAccountsLoaded({bool force = false}) {
    if (!force && _accounts.isNotEmpty) return Future<void>.value();
    final active = _accountsLoadFuture;
    if (active != null) return active;

    final future = _loadAccountsOnly();
    _accountsLoadFuture = future;
    return future.whenComplete(() {
      if (identical(_accountsLoadFuture, future)) _accountsLoadFuture = null;
    });
  }

  Future<void> _loadAccountsOnly() async {
    _errorMessage = null;
    try {
      _accounts = await _repository.getAccounts();
      notifyListeners();
    } catch (error) {
      AppLogger.debug('account-only loading failed: $error');
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل دليل الحسابات.',
        englishFallback: 'Unable to load the chart of accounts.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadAccounting() async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final results = await Future.wait<dynamic>([
        _repository.getAccounts(),
        _repository.getEntries(),
        _repository.getTrialBalance('USD'),
        _repository.getTrialBalance('IQD'),
        _repository.getReceivablesPayables(),
      ]);
      _accounts = results[0] as List<AccountModel>;
      _entries = results[1] as List<JournalEntryModel>;
      _usdTrial = results[2] as Map<String, double>;
      _iqdTrial = results[3] as Map<String, double>;
      final subledgers = results[4] as Map<String, Map<String, double>>;
      _receivablesByCurrency =
          subledgers['receivables'] ?? const <String, double>{};
      _payablesByCurrency = subledgers['payables'] ?? const <String, double>{};
      _lines.clear();
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل بيانات المحاسبة.',
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<List<Map<String, dynamic>>> loadPartnerSubledgerDetails({
    required bool receivables,
  }) async {
    _errorMessage = null;
    try {
      return await _repository.getPartnerSubledgerDetails(
        receivables: receivables,
      );
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل تفاصيل الذمم.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadPartnerSubledgerDocuments({
    required bool receivables,
    required String partyId,
    required String currency,
  }) async {
    _errorMessage = null;
    try {
      return await _repository.getPartnerSubledgerDocuments(
        receivables: receivables,
        partyId: partyId,
        currency: currency,
      );
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل مستندات الذمم.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> loadPartnerUnappliedPayments({
    required bool receivables,
    required String partyId,
    required String currency,
  }) {
    return _repository.getPartnerUnappliedPayments(
      partyType: receivables ? 'customer' : 'supplier',
      partyId: partyId,
      currency: currency,
    );
  }

  Future<void> updatePartnerUnappliedPayment({
    required String transactionId,
    required double amount,
    required DateTime transactionDate,
    required String notes,
  }) async {
    await _repository.updatePartnerUnappliedPayment(
      transactionId: transactionId,
      amount: amount,
      transactionDate: transactionDate,
      notes: notes,
    );
    AppDataChangeBus.instance.publish(
      'accounting',
      operation: 'partner-payment-update',
      entityId: transactionId,
    );
    await loadAccounting();
  }

  Future<void> deletePartnerUnappliedPayment(String transactionId) async {
    await _repository.deletePartnerUnappliedPayment(transactionId);
    AppDataChangeBus.instance.publish(
      'accounting',
      operation: 'partner-payment-delete',
      entityId: transactionId,
    );
    await loadAccounting();
  }

  Future<List<JournalLineModel>> loadEntryLines(String entryId) async {
    if (_lines.containsKey(entryId)) {
      return List.unmodifiable(_lines[entryId]!);
    }
    final lines = await _repository.getEntryLines(entryId);
    _lines[entryId] = lines;
    notifyListeners();
    return List.unmodifiable(lines);
  }

  Future<AccountStatementResult> loadAccountStatement({
    required AccountModel account,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    _errorMessage = null;
    try {
      return await _repository.getAccountStatement(
        account: account,
        fromDate: fromDate,
        toDate: toDate,
      );
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل كشف الحساب.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addAccount(AccountModel account) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.addAccount(account);
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: 'account-insert',
      );
      _accounts = await _repository.getAccounts();
      notifyListeners();
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حفظ الحساب.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateAccount(AccountModel account) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.updateAccount(account);
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: 'account-update',
        entityId: account.id,
      );
      _accounts = await _repository.getAccounts();
      notifyListeners();
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تعديل الحساب.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteAccount(String accountId) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.deleteAccount(accountId);
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: 'account-delete',
        entityId: accountId,
      );
      _accounts = await _repository.getAccounts();
      notifyListeners();
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حذف الحساب.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addEntry({
    required JournalEntryModel entry,
    required List<JournalLineModel> lines,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      if (await _repository.entryNumberExists(entry.entryNumber)) {
        throw StateError('رقم القيد مستخدم مسبقًا.');
      }
      await _repository.addEntry(entry: entry, lines: lines);
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: 'entry-insert',
      );
      await _refresh();
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حفظ القيد.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> updateEntry({
    required JournalEntryModel entry,
    required List<JournalLineModel> lines,
  }) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.updateEntry(entry: entry, lines: lines);
      AppDataChangeBus.instance.publish(
        'accounting',
        operation: 'entry-update',
        entityId: entry.id,
      );
      _lines[entry.id] = List<JournalLineModel>.unmodifiable(lines);
      await _refresh();
    } catch (error) {
      AppLogger.debug('accounting_controller update entry failed: $error');
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تعديل القيد.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteEntry(String entryId) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      await _repository.deleteEntry(entryId);
      AppDataChangeBus.instance.publish('accounting', operation: 'delete');
      _lines.remove(entryId);
      await _refresh();
    } catch (error) {
      AppLogger.debug('accounting_controller operation failed: $error');

      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حذف القيد.',
      );
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> searchEntries(String value) async {
    query.setSearch(value);
  }

  Future<void> _refresh() async {
    final results = await Future.wait<dynamic>([
      _repository.getEntries(),
      _repository.getTrialBalance('USD'),
      _repository.getTrialBalance('IQD'),
      _repository.getReceivablesPayables(),
    ]);
    _entries = results[0] as List<JournalEntryModel>;
    _usdTrial = results[1] as Map<String, double>;
    _iqdTrial = results[2] as Map<String, double>;
    final subledgers = results[3] as Map<String, Map<String, double>>;
    _receivablesByCurrency =
        subledgers['receivables'] ?? const <String, double>{};
    _payablesByCurrency = subledgers['payables'] ?? const <String, double>{};
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    query.removeListener(_onQueryChanged);
    query.dispose();
    super.dispose();
  }
}
