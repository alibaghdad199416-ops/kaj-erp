import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_tenant_context.dart';

enum ErpModuleReadiness { ready, missing, blocked }

class ErpOperationalReadiness {
  const ErpOperationalReadiness({
    required this.ok,
    required this.companyId,
    required this.modules,
    required this.checkedAt,
  });

  final bool ok;
  final String companyId;
  final Map<String, ErpModuleReadiness> modules;
  final DateTime checkedAt;

  List<String> get unavailableModules => modules.entries
      .where((entry) => entry.value != ErpModuleReadiness.ready)
      .map((entry) => entry.key)
      .toList(growable: false);

  factory ErpOperationalReadiness.fromRpc(Map<String, dynamic> json) {
    final rawModules = Map<String, dynamic>.from(
      (json['modules'] as Map?) ?? const <String, dynamic>{},
    );
    return ErpOperationalReadiness(
      ok: json['ok'] == true,
      companyId: json['company_id']?.toString() ?? '',
      modules: rawModules.map(
        (key, value) => MapEntry(
          key,
          value == true ? ErpModuleReadiness.ready : ErpModuleReadiness.missing,
        ),
      ),
      checkedAt:
          DateTime.tryParse(json['checked_at']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }
}

/// Verifies that the authenticated tenant can reach the operational ERP tables.
///
/// This is intentionally read-only. It can be called after login before opening
/// transactional pages, and produces a precise module list instead of a generic
/// connection failure.
class ErpOperationalReadinessService {
  ErpOperationalReadinessService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ErpOperationalReadiness> check() async {
    final companyId = CloudTenantContext.instance.companyUuid;
    if (companyId == null || companyId.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }

    try {
      final result = await _client.rpc(
        'erp_operational_readiness',
        params: {'p_company_id': companyId},
      );
      return ErpOperationalReadiness.fromRpc(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw StateError(
          'الحساب مسجل الدخول لكنه لا يملك عضوية فعالة في الشركة.',
        );
      }
      throw StateError('تعذر فحص جاهزية وحدات ERP: ${error.message}');
    }
  }
}
