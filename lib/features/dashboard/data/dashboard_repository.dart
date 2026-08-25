import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/dashboard/models/dashboard_model.dart';

class DashboardRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.'));

  Future<DashboardModel> getDashboardData() async {
    final result = await _client.rpc(
      'erp_r49_cloud_dashboard_snapshot',
      params: {
        'p_company_id': _companyId,
        'p_reference_day': _day(DateTime.now()),
      },
    );
    final row = _mapResult(result);
    final trend = <DashboardSalesPoint>[];
    for (final item in _rows(row['salesTrend'])) {
      final date = _date(item['date']);
      if (date == null) continue;
      trend.add(DashboardSalesPoint(date: date, amount: _d(item['amount'])));
    }

    final activities = <DashboardActivity>[];
    for (final item in _rows(row['recentActivities'])) {
      final createdAt = _date(item['createdAt']);
      if (createdAt == null) continue;
      activities.add(
        DashboardActivity(
          action: item['action']?.toString().trim().isNotEmpty == true
              ? item['action'].toString()
              : 'unknown',
          module: item['module']?.toString() ?? '',
          description: item['description']?.toString() ?? '',
          userName: item['userName']?.toString() ?? '',
          createdAt: createdAt,
        ),
      );
    }

    final installments = <DashboardInstallment>[];
    for (final item in _rows(row['upcomingInstallments'])) {
      final dueDate = _date(item['dueDate']);
      final currency = (item['currencyCode']?.toString() ?? '')
          .trim()
          .toUpperCase();
      if (dueDate == null || currency.isEmpty) continue;
      installments.add(
        DashboardInstallment(
          customerName: item['customerName']?.toString() ?? '',
          installmentNo: _i(item['installmentNo']),
          dueDate: dueDate,
          remainingAmount: _d(item['remainingAmount']),
          currencyCode: currency,
          isOverdue: item['isOverdue'] == true,
        ),
      );
    }
    return DashboardModel(
      totalCars: _i(row['totalCars']),
      availableCars: _i(row['availableCars']),
      reservedCars: _i(row['reservedCars']),
      soldCars: _i(row['soldCars']),
      totalCustomers: _i(row['totalCustomers']),
      totalSuppliers: _i(row['totalSuppliers']),
      totalSales: _d(row['totalSales']),
      todaySales: _d(row['todaySales']),
      totalPurchases: _d(row['totalPurchases']),
      totalExpenses: _d(row['totalExpenses']),
      netProfit: _d(row['netProfit']),
      cashBalanceUsd: _d(row['cashBalanceUsd']),
      cashBalanceIqd: _d(row['cashBalanceIqd']),
      inventoryValue: _d(row['inventoryValue']),
      totalReceivables: _d(row['totalReceivables']),
      totalPayables: _d(row['totalPayables']),
      totalSalesByCurrency: _moneyMap(row['totalSalesByCurrency']),
      todaySalesByCurrency: _moneyMap(row['todaySalesByCurrency']),
      totalPurchasesByCurrency: _moneyMap(row['totalPurchasesByCurrency']),
      totalExpensesByCurrency: _moneyMap(row['totalExpensesByCurrency']),
      netProfitByCurrency: _moneyMap(row['netProfitByCurrency']),
      inventoryValueByCurrency: _moneyMap(row['inventoryValueByCurrency']),
      totalReceivablesByCurrency: _moneyMap(row['totalReceivablesByCurrency']),
      totalPayablesByCurrency: _moneyMap(row['totalPayablesByCurrency']),
      pendingPurchaseCars: _i(row['pendingPurchaseCars']),
      lowStockItems: _i(row['lowStockItems']),
      carsWithoutWarehouse: _i(row['carsWithoutWarehouse']),
      activeReservations: _i(row['activeReservations']),
      overdueInstallments: _i(row['overdueInstallments']),
      dueSoonInstallments: _i(row['dueSoonInstallments']),
      outstandingInstallmentsByCurrency: _moneyMap(
        row['outstandingInstallmentsByCurrency'],
      ),
      pendingSyncOperations: _i(row['pendingSyncOperations']),
      salesTrend: trend,
      recentActivities: activities,
      upcomingInstallments: installments,
      generatedAt: _requiredDate(row['generatedAt'], 'dashboard.generatedAt'),
    );
  }

  static Map<String, Object?> _mapResult(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, Object?>.from(value.first as Map);
    }
    throw StateError('استجابة لوحة التحكم من Supabase غير صالحة.');
  }

  static List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  static Map<String, double> _moneyMap(Object? value) {
    if (value is! Map) return const <String, double>{};
    final result = <String, double>{};
    value.forEach((key, raw) {
      final currency = key.toString().trim().toUpperCase();
      if (currency.isNotEmpty) result[currency] = _d(raw);
    });
    return Map<String, double>.unmodifiable(result);
  }

  static DateTime? _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
  static DateTime _requiredDate(Object? value, String field) {
    final date = _date(value);
    if (date != null) return date;
    throw FormatException('Missing or invalid required timestamp: $field');
  }

  static int _i(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
  static double _d(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
