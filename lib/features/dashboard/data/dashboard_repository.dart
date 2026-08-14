import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/dashboard/models/dashboard_model.dart';

class DashboardRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.'));

  Future<DashboardModel> getDashboardData({
    DateTime? fromDate,
    required DateTime toDate,
  }) async {
    final result = await _client.rpc(
      'erp_r65_get_authoritative_dashboard_snapshot',
      params: {
        'p_company_id': _companyId,
        'p_from_date': fromDate == null ? null : _day(fromDate),
        'p_to_date': _day(toDate),
      },
    );
    final row = _mapResult(result);
    final filter = _requiredMap(row['filter'], 'dashboard.filter');
    final parsedToDate = _requiredDate(
      filter['toDate'],
      'dashboard.filter.toDate',
    );
    final parsedFromDate = _date(filter['fromDate']);
    final sales = _requiredMoneyMap(row, 'totalSalesByCurrency');
    final todaySales = _requiredMoneyMap(row, 'todaySalesByCurrency');
    final purchases = _requiredMoneyMap(row, 'totalPurchasesByCurrency');
    final expenses = _requiredMoneyMap(row, 'totalExpensesByCurrency');
    final profit = _requiredMoneyMap(row, 'netProfitByCurrency');
    final inventory = _requiredMoneyMap(row, 'inventoryValueByCurrency');
    final receivables = _requiredMoneyMap(row, 'totalReceivablesByCurrency');
    final payables = _requiredMoneyMap(row, 'totalPayablesByCurrency');
    final cash = _requiredMoneyMap(row, 'cashBalanceByCurrency');
    final trend = <DashboardSalesPoint>[];
    for (final item in _rows(row['salesTrend'])) {
      final date = _date(item['date']);
      if (date == null) continue;
      trend.add(
        DashboardSalesPoint(date: date, amounts: _moneyMap(item['amounts'])),
      );
    }

    final documents = <DashboardDocument>[];
    for (final item in _rows(row['recentDocuments'])) {
      final occurredAt = _date(item['occurredAt']);
      final reference = item['reference']?.toString().trim() ?? '';
      final currency = item['currency']?.toString().trim().toUpperCase() ?? '';
      if (occurredAt == null || reference.isEmpty || currency.isEmpty) continue;
      documents.add(
        DashboardDocument(
          module: item['module']?.toString() ?? '',
          documentType: item['documentType']?.toString() ?? '',
          reference: reference,
          status: item['status']?.toString() ?? '',
          partner: item['partner']?.toString() ?? '',
          currencyCode: currency,
          amount: _d(item['amount']),
          occurredAt: occurredAt,
        ),
      );
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
      totalSales: sales['USD'] ?? 0,
      todaySales: todaySales['USD'] ?? 0,
      totalPurchases: purchases['USD'] ?? 0,
      totalExpenses: expenses['USD'] ?? 0,
      netProfit: profit['USD'] ?? 0,
      cashBalanceUsd: cash['USD'] ?? 0,
      cashBalanceIqd: cash['IQD'] ?? 0,
      inventoryValue: inventory['USD'] ?? 0,
      totalReceivables: receivables['USD'] ?? 0,
      totalPayables: payables['USD'] ?? 0,
      totalSalesByCurrency: sales,
      todaySalesByCurrency: todaySales,
      totalPurchasesByCurrency: purchases,
      totalExpensesByCurrency: expenses,
      netProfitByCurrency: profit,
      inventoryValueByCurrency: inventory,
      totalReceivablesByCurrency: receivables,
      totalPayablesByCurrency: payables,
      salesCollectionsByCurrency: _requiredMoneyMap(
        row,
        'salesCollectionsByCurrency',
      ),
      purchasePaymentsByCurrency: _requiredMoneyMap(
        row,
        'purchasePaymentsByCurrency',
      ),
      maintenanceRevenueByCurrency: _requiredMoneyMap(
        row,
        'maintenanceRevenueByCurrency',
      ),
      maintenancePaidByCurrency: _requiredMoneyMap(
        row,
        'maintenancePaidByCurrency',
      ),
      maintenanceOutstandingByCurrency: _requiredMoneyMap(
        row,
        'maintenanceOutstandingByCurrency',
      ),
      maintenanceActualCostByCurrency: _requiredMoneyMap(
        row,
        'maintenanceActualCostByCurrency',
      ),
      customerAdvancesByCurrency: _requiredMoneyMap(
        row,
        'customerAdvancesByCurrency',
      ),
      supplierAdvancesByCurrency: _requiredMoneyMap(
        row,
        'supplierAdvancesByCurrency',
      ),
      recognizedRevenueByCurrency: _requiredMoneyMap(
        row,
        'recognizedRevenueByCurrency',
      ),
      cashBalanceByCurrency: cash,
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
      recentDocuments: documents,
      upcomingInstallments: installments,
      generatedAt: _requiredDate(row['generatedAt'], 'dashboard.generatedAt'),
      filter: DashboardFilter(fromDate: parsedFromDate, toDate: parsedToDate),
      statusCounts: _statusCounts(row['statusCounts']),
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

  static Map<String, Object?> _requiredMap(Object? value, String field) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw FormatException('Missing or invalid required object: $field');
  }

  static Map<String, double> _requiredMoneyMap(
    Map<String, Object?> row,
    String field,
  ) {
    if (!row.containsKey(field) || row[field] is! Map) {
      throw FormatException('Missing or invalid required money map: $field');
    }
    return _moneyMap(row[field]);
  }

  static Map<String, Map<String, int>> _statusCounts(Object? value) {
    final root = _requiredMap(value, 'dashboard.statusCounts');
    return Map<String, Map<String, int>>.unmodifiable(
      root.map((module, raw) {
        final statuses = _requiredMap(raw, 'dashboard.statusCounts.$module');
        return MapEntry(
          module,
          Map<String, int>.unmodifiable(
            statuses.map((status, count) => MapEntry(status, _i(count))),
          ),
        );
      }),
    );
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
