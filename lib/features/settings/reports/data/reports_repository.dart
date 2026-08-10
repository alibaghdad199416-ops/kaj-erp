import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_model.dart';

class ReportsRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية.'));
  Future<ReportModel> getReportsData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final result = await _client.rpc(
      'erp_r49_cloud_reports_summary',
      params: {
        'p_company_id': _companyId,
        'p_start_date': startDate == null ? null : _day(startDate),
        'p_end_date': endDate == null ? null : _day(endDate),
      },
    );
    final r = Map<String, Object?>.from(result as Map);
    final points = (r['monthlyPoints'] as List? ?? const [])
        .map((e) {
          final m = Map<String, Object?>.from(e as Map);
          return MonthlyReportPoint(
            label: m['label']?.toString() ?? '',
            sales: _d(m['sales']),
            expenses: _d(m['expenses']),
            purchases: _d(m['purchases']),
          );
        })
        .toList(growable: false);
    return ReportModel(
      totalCars: _i(r['totalCars']),
      availableCars: _i(r['availableCars']),
      reservedCars: _i(r['reservedCars']),
      soldCars: _i(r['soldCars']),
      totalCustomers: _i(r['totalCustomers']),
      totalSuppliers: _i(r['totalSuppliers']),
      totalInventoryItems: _i(r['totalInventoryItems']),
      totalSales: _d(r['totalSales']),
      totalPaidSales: _d(r['totalPaidSales']),
      totalReceivables: _d(r['totalReceivables']),
      totalPurchases: _d(r['totalPurchases']),
      totalPurchaseDebt: _d(r['totalPurchaseDebt']),
      totalExpenses: _d(r['totalExpenses']),
      inventoryValue: _d(r['inventoryValue']),
      cashBalanceUsd: _d(r['cashBalanceUsd']),
      cashBalanceIqd: _d(r['cashBalanceIqd']),
      activeReservations: _i(r['activeReservations']),
      overdueInstallments: _i(r['overdueInstallments']),
      netProfit: _d(r['netProfit']),
      totalSalesByCurrency: _moneyMap(r['totalSalesByCurrency']),
      totalPaidSalesByCurrency: _moneyMap(r['totalPaidSalesByCurrency']),
      totalReceivablesByCurrency: _moneyMap(r['totalReceivablesByCurrency']),
      totalPurchasesByCurrency: _moneyMap(r['totalPurchasesByCurrency']),
      totalPurchaseDebtByCurrency: _moneyMap(r['totalPurchaseDebtByCurrency']),
      totalExpensesByCurrency: _moneyMap(r['totalExpensesByCurrency']),
      inventoryValueByCurrency: _moneyMap(r['inventoryValueByCurrency']),
      netProfitByCurrency: _moneyMap(r['netProfitByCurrency']),
      monthlyPoints: points,
    );
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

  static int _i(Object? v) => (v as num?)?.toInt() ?? 0;
  static double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
