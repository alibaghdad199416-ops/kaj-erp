import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import '../models/recycle_bin_item.dart';

class RecycleBinRepository {
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid?.trim() ?? '';
    if (value.isEmpty) throw StateError('Cloud company is not selected.');
    return value;
  }

  Future<List<RecycleBinItem>> load({
    String query = '',
    String entityType = '',
  }) async {
    final response = await _client.rpc(
      'erp_recycle_bin_list',
      params: {
        'p_company_id': _companyId,
        'p_query': query.trim(),
        'p_entity_type': entityType.trim(),
      },
    );
    return (response as List)
        .map(
          (row) =>
              RecycleBinItem.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<void> restore(RecycleBinItem item) async {
    await _client.rpc(
      'erp_recycle_bin_restore',
      params: {
        'p_company_id': _companyId,
        'p_entity_type': item.entityType,
        'p_record_id': item.recordId,
      },
    );
  }

  Future<void> permanentlyDelete(RecycleBinItem item) async {
    final response = item.archiveId == null
        ? await _client.rpc(
            'erp_recycle_bin_purge',
            params: {
              'p_company_id': _companyId,
              'p_entity_type': item.entityType,
              'p_record_id': item.recordId,
            },
          )
        : await _client.rpc(
            'erp_recycle_bin_purge_by_archive',
            params: {
              'p_company_id': _companyId,
              'p_archive_id': item.archiveId,
            },
          );
    final result = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
    if (result['purged'] != true) {
      throw StateError('تعذر تنفيذ الحذف النهائي للسجل المحدد.');
    }
  }
}
