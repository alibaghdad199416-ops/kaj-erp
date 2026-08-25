import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_tenant_context.dart';
import 'supabase_config.dart';

/// Typed boundary for the remaining cloud-only feature modules.
///
/// The server function performs company isolation and authorization. No caller
/// may fall back to local persistence when an RPC fails.
class CloudFeatureCommand {
  CloudFeatureCommand._();
  static final instance = CloudFeatureCommand._();

  SupabaseClient get _client {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase is not configured for this build.');
    }
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      throw StateError('An authenticated Supabase session is required.');
    }
    final companyId = CloudTenantContext.instance.companyUuid?.trim() ?? '';
    if (companyId.isEmpty) {
      throw StateError('A resolved Supabase company tenant is required.');
    }
    return client;
  }

  Future<Object?> call(
    String area,
    String action, {
    Map<String, Object?> payload = const {},
  }) async {
    try {
      return await _client.rpc(
        'erp_r37_cloud_command',
        params: {'p_area': area, 'p_action': action, 'p_payload': payload},
      );
    } on PostgrestException catch (error) {
      final details = error.details?.toString().trim() ?? '';
      final hint = error.hint?.toString().trim() ?? '';
      throw StateError(
        <String>[
          'cloud_feature_command_failed',
          'area=$area',
          'action=$action',
          if ((error.code ?? '').isNotEmpty) 'code=${error.code}',
          'message=${error.message}',
          if (details.isNotEmpty) 'details=$details',
          if (hint.isNotEmpty) 'hint=$hint',
        ].join(' | '),
      );
    }
  }

  Future<Map<String, dynamic>> reconcileCanonicalState() async {
    try {
      final value = await _client.rpc(
        'erp_r22_reconcile_company_state',
        params: {'p_company_id': CloudTenantContext.instance.companyUuid},
      );
      if (value is! Map) {
        throw StateError(
          'canonical_state_reconcile_invalid_response type=${value.runtimeType}',
        );
      }
      return Map<String, dynamic>.from(value);
    } on PostgrestException catch (error) {
      throw StateError(
        'canonical_state_r22_reconcile_failed | code=${error.code} | message=${error.message} | details=${error.details} | hint=${error.hint}',
      );
    }
  }

  Future<Map<String, dynamic>> runtimeContractProbe() async {
    try {
      final value = await _client.rpc(
        'erp_r22_runtime_contract_probe',
        params: {'p_company_id': CloudTenantContext.instance.companyUuid},
      );
      if (value is! Map) {
        throw StateError(
          'runtime_contract_probe_invalid_response type=${value.runtimeType}',
        );
      }
      return Map<String, dynamic>.from(value);
    } on PostgrestException catch (error) {
      throw StateError(
        'runtime_contract_r22_probe_failed | code=${error.code} | message=${error.message} | details=${error.details} | hint=${error.hint}',
      );
    }
  }

  Future<Map<String, dynamic>> map(
    String area,
    String action, {
    Map<String, Object?> payload = const {},
  }) async {
    final value = await call(area, action, payload: payload);
    if (value == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(value as Map);
  }

  Future<List<Map<String, dynamic>>> list(
    String area,
    String action, {
    Map<String, Object?> payload = const {},
  }) async {
    final value = await call(area, action, payload: payload);
    if (value == null) return <Map<String, dynamic>>[];
    return List<Map<String, dynamic>>.from(
      (value as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }
}
