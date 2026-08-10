import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../cloud/cloud_tenant_context.dart';

/// Supabase Storage-only binary document repository.
class DocumentStorageRepository {
  DocumentStorageRepository();

  static const String bucketName = 'enterprise-documents';
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final id = CloudTenantContext.instance.companyUuid;
    if (id == null || id.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return id;
  }

  String _path(String documentId, String versionId) =>
      '$_companyId/$documentId/$versionId.bin';

  Future<void> store({
    required String documentId,
    required String versionId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('Document content cannot be empty.');
    final path = _path(documentId, versionId);
    await _client.storage
        .from(bucketName)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    await _client.rpc(
      'erp_register_cloud_document_blob',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_version_id': versionId,
        'p_storage_path': path,
        'p_size_bytes': bytes.length,
      },
    );
  }

  Future<Uint8List?> readCurrent(String documentId) async {
    final result = await _client.rpc(
      'erp_get_cloud_current_document_blob',
      params: {'p_company_id': _companyId, 'p_document_id': documentId},
    );
    if (result == null) return null;
    final row = Map<String, dynamic>.from(result as Map);
    final path = row['storagePath']?.toString();
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(bucketName).download(path);
  }
}
