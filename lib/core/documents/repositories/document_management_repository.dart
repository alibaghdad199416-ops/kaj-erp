import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../cloud/cloud_tenant_context.dart';
import '../models/document_models.dart';

/// Supabase-only document metadata, versions, links and permissions.
class DocumentManagementRepository {
  DocumentManagementRepository();
  static const Uuid _uuid = Uuid();
  SupabaseClient get _client => Supabase.instance.client;

  String get _companyId {
    final id = CloudTenantContext.instance.companyUuid;
    if (id == null || id.isEmpty)
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    return id;
  }

  Future<String> createDocument(EnterpriseDocumentCreateInput input) async {
    if (input.documentNumber.trim().isEmpty ||
        input.titleAr.trim().isEmpty ||
        input.fileName.trim().isEmpty ||
        input.storagePath.trim().isEmpty ||
        input.checksumSha256.trim().isEmpty) {
      throw ArgumentError('Document identity, file and checksum are required.');
    }
    if (input.fileSize < 0) throw ArgumentError('Invalid file size.');
    final id = _uuid.v4();
    final result = await _client.rpc(
      'erp_create_cloud_document',
      params: {
        'p_company_id': _companyId,
        'p_document': {
          'id': id,
          'documentNumber': input.documentNumber.trim(),
          'titleAr': input.titleAr.trim(),
          'titleEn': input.titleEn.trim(),
          'categoryId': input.categoryId,
          'ownerUserId': input.ownerUserId,
          'branchId': input.branchId,
          'confidentiality': input.confidentiality,
          'expiryDate': input.expiryDate?.toUtc().toIso8601String(),
          'metadata': input.metadata,
          'createdBy': input.createdBy,
        },
        'p_version': {
          'id': _uuid.v4(),
          'fileName': input.fileName.trim(),
          'mimeType': input.mimeType.trim(),
          'storagePath': input.storagePath.trim(),
          'fileSize': input.fileSize,
          'checksumSha256': input.checksumSha256.trim().toLowerCase(),
          'extractedText': input.extractedText,
        },
      },
    );
    return result.toString();
  }

  Future<int> addVersion({
    required String documentId,
    required String fileName,
    required String mimeType,
    required String storagePath,
    required String checksumSha256,
    required String changeSummary,
    int fileSize = 0,
    String extractedText = '',
    String? createdBy,
  }) async {
    final result = await _client.rpc(
      'erp_add_cloud_document_version',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_version': {
          'id': _uuid.v4(),
          'fileName': fileName.trim(),
          'mimeType': mimeType.trim(),
          'storagePath': storagePath.trim(),
          'fileSize': fileSize,
          'checksumSha256': checksumSha256.trim().toLowerCase(),
          'extractedText': extractedText,
          'changeSummary': changeSummary.trim(),
          'createdBy': createdBy,
        },
      },
    );
    return (result as num).toInt();
  }

  Future<void> linkEntity({
    required String documentId,
    required String entityType,
    required String entityId,
    String relationshipType = 'attachment',
    Map<String, Object?> metadata = const {},
  }) async {
    await _client.rpc(
      'erp_link_cloud_document',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_link': {
          'id': _uuid.v4(),
          'entityType': entityType,
          'entityId': entityId,
          'relationshipType': relationshipType,
          'metadata': metadata,
        },
      },
    );
  }

  Future<void> grantPermission({
    required String documentId,
    required String principalType,
    required String principalId,
    required DocumentPermissionInput permission,
    String? grantedBy,
  }) async {
    await _client.rpc(
      'erp_grant_cloud_document_permission',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_permission': {
          'id': _uuid.v4(),
          'principalType': principalType,
          'principalId': principalId,
          'canView': permission.canView,
          'canDownload': permission.canDownload,
          'canEdit': permission.canEdit,
          'canDelete': permission.canDelete,
          'canShare': permission.canShare,
          'canPrint': permission.canPrint,
          'grantedBy': grantedBy,
        },
      },
    );
  }

  Future<void> transition({
    required String documentId,
    required String toStatus,
    required String actorId,
    String description = '',
  }) async {
    await _client.rpc(
      'erp_transition_cloud_document',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_to_status': toStatus,
        'p_actor_id': actorId,
        'p_description': description.trim(),
      },
    );
  }

  Future<List<Map<String, Object?>>> search({
    String query = '',
    String? categoryId,
    String? status,
    String? entityType,
    String? entityId,
    int limit = 100,
  }) async {
    final result = await _client.rpc(
      'erp_search_cloud_documents',
      params: {
        'p_company_id': _companyId,
        'p_query': query.trim(),
        'p_category_id': categoryId,
        'p_status': status,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_limit': limit,
      },
    );
    return _rows(result);
  }

  Future<Map<String, Object?>?> getDocument(String documentId) async {
    final result = await _client.rpc(
      'erp_get_cloud_document',
      params: {'p_company_id': _companyId, 'p_document_id': documentId},
    );
    return result == null ? null : Map<String, Object?>.from(result as Map);
  }

  Future<List<Map<String, Object?>>> versions(String documentId) async {
    final result = await _client.rpc(
      'erp_list_cloud_document_versions',
      params: {'p_company_id': _companyId, 'p_document_id': documentId},
    );
    return _rows(result);
  }

  Future<List<Map<String, Object?>>> permissions(String documentId) async {
    final result = await _client.rpc(
      'erp_list_cloud_document_permissions',
      params: {'p_company_id': _companyId, 'p_document_id': documentId},
    );
    return _rows(result);
  }

  Future<void> signCurrentVersion({
    required String documentId,
    required String signerType,
    required String signerId,
    required String signatureHash,
    Map<String, Object?> metadata = const {},
  }) async {
    await _client.rpc(
      'erp_sign_cloud_document_version',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_signature': {
          'id': _uuid.v4(),
          'signerType': signerType,
          'signerId': signerId,
          'signatureHash': signatureHash.trim(),
          'metadata': metadata,
        },
      },
    );
  }

  Future<void> setLegalHold(
    String documentId,
    bool enabled,
    String actorId,
  ) async {
    await _client.rpc(
      'erp_set_cloud_document_legal_hold',
      params: {
        'p_company_id': _companyId,
        'p_document_id': documentId,
        'p_enabled': enabled,
        'p_actor_id': actorId,
      },
    );
  }

  List<Map<String, Object?>> _rows(dynamic result) =>
      List<Map<String, Object?>>.from(
        (result as List).map((e) => Map<String, Object?>.from(e as Map)),
      );
}
