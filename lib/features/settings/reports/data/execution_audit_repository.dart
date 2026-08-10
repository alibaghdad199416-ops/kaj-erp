import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/features/settings/reports/models/execution_audit_row.dart';

class ExecutionAuditRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية.'));

  Future<List<ExecutionAuditRow>> load(
    String module, {
    DateTime? startDate,
    DateTime? endDate,
    int limit = 10000,
  }) async {
    final result = await _client.rpc(
      'erp_r9_cloud_report_audit',
      params: {
        'p_company_id': _companyId,
        'p_module': module,
        'p_start_date': startDate?.toIso8601String(),
        'p_end_date': endDate?.add(const Duration(days: 1)).toIso8601String(),
        'p_limit': limit,
      },
    );
    return (result as List)
        .map((entry) {
          final row = Map<String, Object?>.from(entry as Map);
          return ExecutionAuditRow(
            userName: _displayUser(row['userName']?.toString()),
            action: _displayAction(row['action']?.toString() ?? ''),
            entityType: _displayEntity(row['entityType']?.toString() ?? ''),
            entityId: row['entityId']?.toString(),
            createdAt:
                DateTime.tryParse(row['createdAt']?.toString() ?? '') ??
                DateTime.now(),
          );
        })
        .toList(growable: false);
  }

  String _displayUser(String? value) {
    final user = value?.trim() ?? '';
    return user.isEmpty || user.toLowerCase() == 'null' ? 'النظام' : user;
  }

  String _displayAction(String action) => switch (action.toLowerCase()) {
    'create' || 'insert' => 'إنشاء',
    'update' || 'edit' => 'تعديل',
    'delete' || 'remove' => 'حذف',
    'approve' || 'post' || 'confirm' => 'تصديق',
    'cancel' || 'void' => 'إلغاء',
    'restore' || 'return' || 'reverse' => 'إرجاع/عكس',
    _ => action,
  };

  String _displayEntity(String entity) => entity;
}
