import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_line_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_result.dart';
import 'package:quality_line_erp/features/accounting/models/journal_entry_model.dart';
import 'package:quality_line_erp/features/accounting/models/journal_line_model.dart';

/// Supabase-only general-ledger repository.
///
/// PostgreSQL is authoritative. Journal headers and lines are posted or
/// deleted atomically through PostgreSQL RPC functions.
class AccountingRepository {
  final CloudMasterDataService _cloud = CloudMasterDataService.instance;
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<AccountModel>> getAccounts() async {
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

  Future<void> addAccount(AccountModel account) => _saveAccount(account, false);
  Future<void> updateAccount(AccountModel account) =>
      _saveAccount(account, true);

  Future<void> _saveAccount(AccountModel account, bool requireExisting) async {
    if (account.id.trim().isEmpty ||
        account.name.trim().isEmpty ||
        (requireExisting && account.code.trim().isEmpty)) {
      throw ArgumentError(
        requireExisting
            ? 'مرجع الحساب ورمزه واسمه مطلوبة.'
            : 'مرجع الحساب واسمه مطلوبان، ويولد الرمز تلقائياً.',
      );
    }
    await _client.rpc(
      'erp_r49_save_cloud_ledger_account',
      params: {
        'p_company_id': _companyId,
        'p_account': account.toMap(),
        'p_require_existing': requireExisting,
      },
    );
  }

  Future<void> deleteAccount(String accountId) async {
    await _client.rpc(
      'erp_r49_delete_cloud_ledger_account',
      params: {'p_company_id': _companyId, 'p_account_id': accountId},
    );
  }

  Future<List<JournalEntryModel>> getEntries() async {
    final rows = await _cloud.list('erp_journal_entries');
    rows.sort((a, b) {
      final byDate = (b['entryDate']?.toString() ?? '').compareTo(
        a['entryDate']?.toString() ?? '',
      );
      return byDate != 0
          ? byDate
          : (b['createdAt']?.toString() ?? '').compareTo(
              a['createdAt']?.toString() ?? '',
            );
    });
    return rows.map(JournalEntryModel.fromMap).toList(growable: false);
  }

  Future<List<JournalLineModel>> getEntryLines(String entryId) async {
    final rows = await _client.rpc(
      'erp_r22_list_journal_lines',
      params: {'p_company_id': _companyId, 'p_entry_id': entryId},
    );
    return (rows as List)
        .map(
          (raw) =>
              JournalLineModel.fromMap(Map<String, dynamic>.from(raw as Map)),
        )
        .toList(growable: false);
  }

  Future<void> addEntry({
    required JournalEntryModel entry,
    required List<JournalLineModel> lines,
  }) async {
    _validateEntry(entry, lines);
    await _client.rpc(
      'erp_r49_post_cloud_manual_journal',
      params: {
        'p_company_id': _companyId,
        'p_entry': entry.toMap(),
        'p_lines': lines.map((line) => line.toMap()).toList(growable: false),
      },
    );
  }

  Future<void> updateEntry({
    required JournalEntryModel entry,
    required List<JournalLineModel> lines,
  }) async {
    _validateEntry(entry, lines);
    await _client.rpc(
      'erp_r49_update_cloud_manual_journal',
      params: {
        'p_company_id': _companyId,
        'p_entry': entry.toMap(),
        'p_lines': lines.map((line) => line.toMap()).toList(growable: false),
      },
    );
  }

  Future<void> deleteEntry(String entryId) async {
    await _client.rpc(
      'erp_delete_cloud_accounting_entry',
      params: {'p_company_id': _companyId, 'p_entry_id': entryId},
    );
  }

  Future<bool> entryNumberExists(String entryNumber) async {
    final normalized = entryNumber.trim();
    final rows = await _cloud.list('erp_journal_entries');
    return rows.any(
      (row) => row['entryNumber']?.toString().trim() == normalized,
    );
  }

  Future<AccountStatementResult> getAccountStatement({
    required AccountModel account,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final result = await _client.rpc(
      'erp_r22_cloud_account_statement',
      params: {
        'p_company_id': _companyId,
        'p_account_id': account.id,
        'p_from_date': DateTime(
          fromDate.year,
          fromDate.month,
          fromDate.day,
        ).toUtc().toIso8601String(),
        'p_to_date': DateTime(
          toDate.year,
          toDate.month,
          toDate.day,
          23,
          59,
          59,
          999,
        ).toUtc().toIso8601String(),
      },
    );
    final rows = List<Map<String, dynamic>>.from(
      (result as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
    final openingResult = await _client.rpc(
      'erp_r22_cloud_account_balance_before',
      params: {
        'p_company_id': _companyId,
        'p_account_id': account.id,
        'p_before_date': DateTime(
          fromDate.year,
          fromDate.month,
          fromDate.day,
        ).toUtc().toIso8601String(),
      },
    );
    var balance = _toDouble(openingResult);
    final creditNature = const {
      'liability',
      'payable',
      'equity',
      'revenue',
      'income',
    }.contains(account.type.toLowerCase());
    final lines = rows
        .map((row) {
          final line = AccountStatementLineModel.fromMap(row);
          balance += creditNature
              ? line.credit - line.debit
              : line.debit - line.credit;
          return line.copyWith(runningBalance: balance);
        })
        .toList(growable: false);
    return AccountStatementResult(
      openingBalance: _toDouble(openingResult),
      lines: lines,
    );
  }

  Future<Map<String, Map<String, double>>> getReceivablesPayables() async {
    final result = await _client.rpc(
      'erp_r22_cloud_receivables_payables',
      params: {'p_company_id': _companyId},
    );
    final row = Map<String, dynamic>.from(result as Map);
    Map<String, double> readCurrencyMap(Object? raw) {
      if (raw is! Map) return const <String, double>{};
      return {
        for (final entry in raw.entries)
          entry.key.toString().toUpperCase(): _toDouble(entry.value),
      };
    }

    return {
      'receivables': readCurrencyMap(row['receivablesByCurrency']),
      'payables': readCurrencyMap(row['payablesByCurrency']),
    };
  }

  Future<List<Map<String, dynamic>>> getPartnerSubledgerDetails({
    required bool receivables,
  }) async {
    final result = await _client.rpc(
      'erp_r22_cloud_partner_subledger_details_v2',
      params: {
        'p_company_id': _companyId,
        'p_kind': receivables ? 'receivables' : 'payables',
      },
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  Future<List<Map<String, dynamic>>> getPartnerSubledgerDocuments({
    required bool receivables,
    required String partyId,
    required String currency,
  }) async {
    final result = await _client.rpc(
      'erp_r22_cloud_partner_subledger_documents',
      params: {
        'p_company_id': _companyId,
        'p_kind': receivables ? 'receivables' : 'payables',
        'p_party_id': partyId,
        'p_currency': currency,
      },
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  Future<List<Map<String, dynamic>>> getPartnerUnappliedPayments({
    required String partyType,
    required String partyId,
    required String currency,
  }) async {
    final result = await _client.rpc(
      'erp_r49_list_partner_unapplied_payments',
      params: {
        'p_company_id': _companyId,
        'p_party_type': partyType,
        'p_party_id': partyId,
        'p_currency': currency,
      },
    );
    return List<Map<String, dynamic>>.from(
      (result as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  Future<void> updatePartnerUnappliedPayment({
    required String transactionId,
    required double amount,
    required DateTime transactionDate,
    required String notes,
  }) async {
    if (amount <= 0)
      throw ArgumentError('يجب أن يكون مبلغ الدفعة أكبر من صفر.');
    final result = await _client.rpc(
      'erp_update_partner_unapplied_payment',
      params: {
        'p_company_id': _companyId,
        'p_transaction_id': transactionId,
        'p_amount': amount,
        'p_transaction_date': transactionDate.toUtc().toIso8601String(),
        'p_notes': notes.trim(),
      },
    );
    if (result is! Map || result['updated'] != true) {
      throw StateError('تعذر تعديل الدفعة غير المخصصة.');
    }
  }

  Future<void> deletePartnerUnappliedPayment(String transactionId) async {
    await _client.rpc(
      'erp_delete_cloud_cash_transaction',
      params: {'p_company_id': _companyId, 'p_transaction_id': transactionId},
    );
  }

  Future<Map<String, double>> getTrialBalance(String currency) async {
    final result = await _client.rpc(
      'erp_r22_cloud_trial_balance',
      params: {'p_company_id': _companyId, 'p_currency': currency},
    );
    final row = Map<String, dynamic>.from(result as Map);
    return {
      'debit': _toDouble(row['debit']),
      'credit': _toDouble(row['credit']),
      'movementDebit': _toDouble(row['movementDebit']),
      'movementCredit': _toDouble(row['movementCredit']),
      'difference': _toDouble(row['difference']),
    };
  }

  void _validateEntry(JournalEntryModel entry, List<JournalLineModel> lines) {
    if (entry.entryNumber.trim().isEmpty || entry.description.trim().isEmpty) {
      throw ArgumentError('رقم القيد ووصفه مطلوبان.');
    }
    if (lines.length < 2)
      throw ArgumentError('يجب أن يحتوي القيد على سطرين على الأقل.');
    for (final line in lines) {
      if (line.entryId != entry.id)
        throw ArgumentError('يوجد سطر غير مرتبط بالقيد الحالي.');
      if (line.debit < 0 ||
          line.credit < 0 ||
          (line.debit > 0 && line.credit > 0) ||
          (line.debit == 0 && line.credit == 0)) {
        throw ArgumentError('قيم سطر القيد غير صحيحة.');
      }
    }
    final debit = lines.fold<double>(0, (sum, line) => sum + line.debit);
    final credit = lines.fold<double>(0, (sum, line) => sum + line.credit);
    if ((debit - credit).abs() > 0.01 ||
        (entry.totalDebit - debit).abs() > 0.01 ||
        (entry.totalCredit - credit).abs() > 0.01) {
      throw ArgumentError('القيد غير متوازن أو إجمالياته غير صحيحة.');
    }
  }

  static double _toDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
}
