import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_master_data_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';

/// Supabase-only expense repository.
///
/// PostgreSQL is authoritative. Posted expenses, their cash movements and
/// balanced journal entries are created atomically by RPC functions.
class ExpenseRepository {
  ExpenseRepository();

  final CloudMasterDataService _cloud = CloudMasterDataService.instance;

  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<ExpenseModel>> getExpenses() async {
    final rows = await _cloud.list('erp_expenses');
    rows.sort(
      (a, b) =>
          (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''),
    );
    return rows.map(ExpenseModel.fromMap).toList(growable: false);
  }

  Future<void> addExpense(ExpenseModel expense) async {
    _validate(expense);
    await _client.rpc(
      'erp_r49_post_cloud_expense',
      params: {'p_company_id': _companyId, 'p_expense': expense.toMap()},
    );
  }

  Future<void> deleteExpense(String id) async {
    await _client.rpc(
      'erp_delete_cloud_expense',
      params: {'p_company_id': _companyId, 'p_expense_id': id},
    );
  }

  Future<double> totalExpenses() async {
    final result = await _client.rpc(
      'erp_r22_cloud_expense_total',
      params: {'p_company_id': _companyId},
    );
    return _toDouble(result);
  }

  Future<List<Map<String, Object?>>> activeAccounts() async {
    final rows = await _cloud.list('erp_cash_accounts');
    return rows
        .where((row) => _bool(row['isActive'] ?? row['is_active']))
        .map<Map<String, Object?>>((row) {
          final normalized = Map<String, Object?>.from(row);
          normalized['id'] ??= row['accountId'] ?? row['account_id'];
          normalized['name'] ??= row['accountName'] ?? row['account_name'];
          normalized['currency'] = (row['currency'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
          return normalized;
        })
        .where((row) => (row['id']?.toString().trim().isNotEmpty ?? false))
        .toList(growable: false)
      ..sort(
        (a, b) => (a['name']?.toString() ?? '').compareTo(
          b['name']?.toString() ?? '',
        ),
      );
  }

  Future<List<Map<String, Object?>>> activeExpenseAccounts() async {
    final rows = await _client.rpc(
      'erp_r22_list_cloud_ledger_accounts',
      params: {'p_company_id': _companyId},
    );
    final accounts = (rows as List)
        .map<Map<String, Object?>>(
          (raw) => Map<String, Object?>.from(raw as Map),
        )
        .toList(growable: false);
    final parentIds = accounts
        .map(
          (row) =>
              (row['parentId'] ?? row['parent_id'])?.toString().trim() ?? '',
        )
        .where((id) => id.isNotEmpty)
        .toSet();
    return accounts
        .where((row) => _bool(row['isActive'] ?? row['is_active']))
        .where((row) => row['type']?.toString().toLowerCase() == 'expense')
        .where((row) {
          final id = row['id']?.toString().trim() ?? '';
          return id.isNotEmpty && !parentIds.contains(id);
        })
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> activeCurrencies() async {
    final rows = await _client.rpc('erp_list_cloud_currencies');
    final result = (rows as List)
        .map<Map<String, Object?>>(
          (row) => Map<String, Object?>.from(row as Map),
        )
        .where((row) => _bool(row['isActive'] ?? row['is_active']))
        .toList(growable: false);
    result.sort((a, b) {
      final base = _boolRank(
        b['isBase'] ?? b['is_base'],
      ).compareTo(_boolRank(a['isBase'] ?? a['is_base']));
      if (base != 0) return base;
      return (a['code']?.toString() ?? '').compareTo(
        b['code']?.toString() ?? '',
      );
    });
    return result;
  }

  Future<List<Map<String, Object?>>> activeBranches() async {
    final rows = await _client.rpc('erp_list_cloud_branches');
    final result = (rows as List)
        .map<Map<String, Object?>>(
          (row) => Map<String, Object?>.from(row as Map),
        )
        .where((row) => _bool(row['isActive'] ?? row['is_active']))
        .toList(growable: false);
    result.sort((a, b) {
      final main = _boolRank(
        b['isMain'] ?? b['is_main'],
      ).compareTo(_boolRank(a['isMain'] ?? a['is_main']));
      if (main != 0) return main;
      return (a['name']?.toString() ?? '').compareTo(
        b['name']?.toString() ?? '',
      );
    });
    return result;
  }

  void _validate(ExpenseModel expense) {
    if (expense.id.trim().isEmpty ||
        expense.title.trim().isEmpty ||
        expense.category.trim().isEmpty) {
      throw ArgumentError('بيانات المصروف غير مكتملة.');
    }
    if (expense.amount <= 0) {
      throw ArgumentError('مبلغ المصروف يجب أن يكون أكبر من صفر.');
    }
    if (DateTime.tryParse(expense.date) == null) {
      throw ArgumentError('تاريخ المصروف غير صحيح.');
    }
  }

  static bool _bool(Object? value) {
    if (value == true || value == 1) return true;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return const {'1', 'true', 'yes', 'on', 'active'}.contains(text);
  }

  static int _boolRank(Object? value) => _bool(value) ? 1 : 0;

  static double _toDouble(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}
