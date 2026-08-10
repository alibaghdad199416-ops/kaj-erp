import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';

class ContextualReportsRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية.'));
  Future<List<ContextualReportSection>> load(
    String module, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    const modelModules = <String>{
      'products',
      'warehouses',
      'customers',
      'suppliers',
      'payments',
      'accounting',
    };
    final customerServiceModule =
        module == 'customer_service' || module == 'opportunities';
    final x = await _client.rpc(
      customerServiceModule
          ? 'erp_r9_cloud_customer_service_report'
          : modelModules.contains(module)
          ? 'erp_r9_cloud_model_report'
          : 'erp_r9_cloud_contextual_report',
      params: {
        'p_company_id': _companyId,
        'p_module': module,
        'p_start_date': startDate == null ? null : _day(startDate),
        'p_end_date': endDate == null ? null : _day(endDate),
      },
    );
    return (x as List)
        .map((e) {
          final m = Map<String, Object?>.from(e as Map);
          return ContextualReportSection(
            key: m['key'].toString(),
            title: m['title'].toString(),
            columns: (m['columns'] as List).map((v) => v.toString()).toList(),
            rows: (m['rows'] as List)
                .map((r) => (r as List).map((v) => v.toString()).toList())
                .toList(),
          );
        })
        .toList(growable: false);
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
