import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';

/// Canonical data boundary for fixed assets.
///
/// UI widgets must not call Supabase directly. PostgreSQL/RPC remains the
/// source of truth and this repository owns the runtime contract, company
/// context and response normalization.
class FixedAssetsRepository {
  FixedAssetsRepository();

  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('No active cloud company is selected.');
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> listAssets() async {
    final rows = await _client.rpc(
      'erp_r22_list_fixed_assets',
      params: {'p_company_id': _companyId},
    );
    return List<Map<String, dynamic>>.from(
      (rows as List).map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  Future<void> deleteAsset({
    required String assetId,
    required String reason,
  }) async {
    await _client.rpc(
      'erp_delete_fixed_asset',
      params: {
        'p_company_id': _companyId,
        'p_asset_id': assetId,
        'p_reason': reason,
      },
    );
  }

  Future<void> postDepreciation({
    required String assetId,
    required DateTime effectiveAt,
  }) async {
    await _client.rpc(
      'erp_r49_post_fixed_asset_depreciation_at',
      params: {
        'p_company_id': _companyId,
        'p_asset_id': assetId,
        'p_effective_at': effectiveAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> saveAsset(Map<String, dynamic> asset) async {
    await _client.rpc(
      'erp_r49_save_fixed_asset',
      params: {'p_company_id': _companyId, 'p_asset': asset},
    );
  }
}
