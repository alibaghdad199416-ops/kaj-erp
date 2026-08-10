import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import '../models/operational_period.dart';

class OperationalPeriodRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد الشركة السحابية.'));

  Future<List<OperationalPeriod>> list() async {
    final response = await _client.rpc(
      'erp_list_operational_periods',
      params: {'p_company_id': _companyId},
    );
    return (response as List)
        .map(
          (row) =>
              OperationalPeriod.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<String> save({
    String? id,
    required String module,
    required String name,
    required DateTime startsAt,
    required DateTime endsAt,
    required String status,
    String? notes,
  }) async {
    final response = await _client.rpc(
      'erp_save_operational_period',
      params: {
        'p_company_id': _companyId,
        'p_period_id': id,
        'p_module': module,
        'p_period_name': name.trim(),
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt.toUtc().toIso8601String(),
        'p_status': status,
        'p_notes': notes?.trim(),
      },
    );
    _publishChange(module, id == null ? 'insert' : 'update');
    return response.toString();
  }

  Future<void> delete(String id) async {
    await _client.rpc(
      'erp_delete_operational_period',
      params: {'p_company_id': _companyId, 'p_period_id': id},
    );
    _publishChange('settings', 'delete');
  }

  void _publishChange(String module, String operation) {
    final source = module.trim().toLowerCase();
    final sources = <String>{'settings', 'accounting'};
    if (source == 'all') {
      sources.add('all');
    } else if ({
      'sales',
      'purchases',
      'inventory',
      'maintenance',
      'accounting',
    }.contains(source)) {
      sources.add(source);
    }
    for (final eventSource in sources) {
      AppDataChangeBus.instance.publish(
        eventSource,
        operation: 'period-$operation',
      );
    }
  }
}
