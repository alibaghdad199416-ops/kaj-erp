import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';

/// Supabase-only cashbox repository.
///
/// PostgreSQL is authoritative. Cash movements and their balanced journal
/// entries are created, changed and deleted atomically through RPC functions.
class CashboxRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<CashAccountModel>> getCashAccounts() async {
    final raw = await _client.rpc(
      'erp_r90_list_cash_accounts',
      params: {'p_company_id': _companyId},
    );
    final rows = (raw as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: true);
    rows.sort((a, b) {
      final active = _boolRank(
        b['isActive'],
      ).compareTo(_boolRank(a['isActive']));
      if (active != 0) return active;
      return (a['name']?.toString() ?? '').compareTo(
        b['name']?.toString() ?? '',
      );
    });
    return rows.map(CashAccountModel.fromCloudMap).toList(growable: false);
  }

  Future<List<AccountModel>> getLedgerAccounts() async {
    final rows = await _client.rpc(
      'erp_r22_list_cloud_ledger_accounts',
      params: {'p_company_id': _companyId},
    );
    return (rows as List)
        .map(
          (raw) => AccountModel.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList(growable: false);
  }

  Future<void> saveCashAccount(CashAccountModel account) async {
    account.validate();
    await _client.rpc(
      'erp_r90_save_cash_account',
      params: {'p_company_id': _companyId, 'p_account': account.toCloudMap()},
    );
  }

  Future<void> deleteCashAccount(String id) async {
    await _client.rpc(
      'erp_r90_delete_cash_account',
      params: {'p_company_id': _companyId, 'p_cash_account_id': id},
    );
  }

  Future<Map<String, double>> getCashAccountBalances() async {
    final result = await _client.rpc(
      'erp_r90_cash_account_balances',
      params: {'p_company_id': _companyId},
    );
    final rows = List<Map<String, dynamic>>.from(
      (result as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
    return {
      for (final row in rows)
        row['cash_account_id'].toString(): _toDouble(row['balance']),
    };
  }

  Future<Map<String, Map<String, double>>> getCashLedgerReconciliation() async {
    final result = await _client.rpc(
      'erp_r90_cash_ledger_reconciliation',
      params: {'p_company_id': _companyId},
    );
    final rows = List<Map<String, dynamic>>.from(
      (result as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
    return {
      for (final row in rows)
        row['cash_account_id'].toString(): {
          'subledger': _toDouble(row['subledger_balance']),
          'ledger': _toDouble(row['ledger_balance']),
          'difference': _toDouble(row['difference']),
        },
    };
  }

  Future<List<CashTransactionModel>> getTransactions() async {
    final raw = await _client.rpc(
      'erp_r28_list_cash_transactions',
      params: {'p_company_id': _companyId},
    );
    final rows = (raw as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    return rows.map(CashTransactionModel.fromMap).toList(growable: false);
  }

  Future<void> transferBetweenCashAccounts({
    required String fromAccountId,
    required String toAccountId,
    required double sourceAmount,
    required double targetAmount,
    required double exchangeRate,
    required DateTime transferDate,
    String? notes,
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError('يجب اختيار صندوقين مختلفين.');
    }
    if (sourceAmount <= 0 || targetAmount <= 0 || exchangeRate <= 0) {
      throw ArgumentError('المبالغ وسعر التحويل يجب أن تكون أكبر من صفر.');
    }
    final expectedTarget = sourceAmount * exchangeRate;
    final tolerance = expectedTarget.abs() * 0.000001 < 0.01
        ? 0.01
        : expectedTarget.abs() * 0.000001;
    if ((targetAmount - expectedTarget).abs() > tolerance) {
      throw ArgumentError(
        'المبلغ الداخل لا يطابق المبلغ الخارج مضروبًا في سعر التحويل.',
      );
    }
    await _client.rpc(
      'erp_r90_transfer_cloud_cash',
      params: {
        'p_company_id': _companyId,
        'p_from_cash_account_id': fromAccountId,
        'p_to_cash_account_id': toAccountId,
        'p_source_amount': sourceAmount,
        'p_target_amount': targetAmount,
        'p_exchange_rate': exchangeRate,
        'p_transfer_date': transferDate.toUtc().toIso8601String(),
        'p_notes': notes,
      },
    );
  }

  Future<void> deleteCashTransfer(String transferId) async {
    if (transferId.trim().isEmpty) {
      throw ArgumentError('مرجع التحويل مطلوب.');
    }
    await _client.rpc(
      'erp_r90_delete_cash_transfer',
      params: {'p_company_id': _companyId, 'p_transfer_id': transferId.trim()},
    );
  }

  Future<void> addTransaction(CashTransactionModel transaction) async {
    _validate(transaction);
    await _client.rpc(
      'erp_r90_post_cash_transaction',
      params: {
        'p_company_id': _companyId,
        'p_transaction': transaction.toCloudMap(),
        'p_replace': false,
      },
    );
  }

  Future<void> updateTransaction(CashTransactionModel transaction) async {
    _validate(transaction);
    await _client.rpc(
      'erp_r90_post_cash_transaction',
      params: {
        'p_company_id': _companyId,
        'p_transaction': transaction.toCloudMap(),
        'p_replace': true,
      },
    );
  }

  Future<void> deleteTransaction(String id) async {
    await _client.rpc(
      'erp_r90_delete_cash_transaction',
      params: {'p_company_id': _companyId, 'p_transaction_id': id},
    );
  }

  Future<bool> voucherNumberExists(
    String voucherNumber, {
    String? excludeId,
  }) async {
    final normalized = voucherNumber.trim();
    final rows = await getTransactions();
    return rows.any((row) {
      if (excludeId != null && excludeId.isNotEmpty && row.id == excludeId) {
        return false;
      }
      return row.voucherNumber.trim() == normalized;
    });
  }

  Future<List<CashTransactionModel>> searchTransactions(String query) async {
    final value = query.trim().toLowerCase();
    final transactions = await getTransactions();
    if (value.isEmpty) return transactions;
    return transactions
        .where((item) {
          return item.voucherNumber.toLowerCase().contains(value) ||
              item.category.toLowerCase().contains(value) ||
              (item.partyName ?? '').toLowerCase().contains(value) ||
              (item.notes ?? '').toLowerCase().contains(value);
        })
        .toList(growable: false);
  }

  Future<Map<String, double>> getCurrencySummary(String currency) async {
    final result = await _client.rpc(
      'erp_r22_cloud_cash_currency_summary',
      params: {'p_company_id': _companyId, 'p_currency': currency},
    );
    final row = Map<String, dynamic>.from(result as Map);
    final openingBalance = _toDouble(row['openingBalance']);
    final receipts = _toDouble(row['receipts']);
    final payments = _toDouble(row['payments']);
    return {
      'openingBalance': openingBalance,
      'receipts': receipts,
      'payments': payments,
      'balance': _toDouble(row['balance']),
    };
  }

  void _validate(CashTransactionModel transaction) {
    if (transaction.id.trim().isEmpty ||
        transaction.voucherNumber.trim().isEmpty) {
      throw ArgumentError('رقم السند مطلوب.');
    }
    if (transaction.type != 'receipt' && transaction.type != 'payment') {
      throw ArgumentError('نوع الحركة غير صحيح.');
    }
    if (transaction.amount <= 0) {
      throw ArgumentError('يجب أن يكون المبلغ أكبر من صفر.');
    }
    if (transaction.cashAccountId == null ||
        transaction.cashAccountId!.isEmpty) {
      throw ArgumentError('يجب اختيار الصندوق النقدي.');
    }
    if (transaction.counterAccountId == null ||
        transaction.counterAccountId!.isEmpty) {
      throw ArgumentError('يجب اختيار الحساب المحاسبي المقابل.');
    }
  }

  static bool _bool(Object? value) =>
      value == true || value == 1 || value?.toString() == '1';

  static int _boolRank(Object? value) => _bool(value) ? 1 : 0;

  static double _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}
