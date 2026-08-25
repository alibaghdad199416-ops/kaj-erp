import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';

import 'package:quality_line_erp/features/settings/access/models/audit_log_model.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_model.dart';
import 'package:quality_line_erp/features/settings/access/models/role_model.dart';
import 'package:quality_line_erp/features/settings/access/models/user_model.dart';

class UserPermissionOverrideState {
  const UserPermissionOverrideState({
    required this.enabled,
    required this.codes,
  });

  final bool enabled;
  final Set<String> codes;
}

/// Cloud-only access repository. Supabase Authentication and PostgreSQL are the
/// persistence boundary; no access identity or permission cache is written to
/// any device-local business database.
class AccessRepository {
  AccessRepository();

  SupabaseClient get _client => Supabase.instance.client;

  Set<String>? _bootstrapPermissionCodes;
  Map<String, dynamic>? _snapshotCache;
  DateTime? _snapshotCachedAt;
  Future<Map<String, dynamic>>? _snapshotInFlight;
  static const Duration _snapshotTtl = Duration(seconds: 20);

  /// Permissions returned atomically by the login bootstrap RPC. Using these
  /// avoids a second startup RPC that could make an otherwise valid login fail.
  Set<String>? takeBootstrapPermissionCodes() {
    final value = _bootstrapPermissionCodes;
    _bootstrapPermissionCodes = null;
    return value == null ? null : Set<String>.unmodifiable(value);
  }

  Future<UserModel?> bootstrapCurrentCloudAccess({
    required String uid,
    required String email,
    required bool emailVerified,
  }) async {
    final response = await _client.rpc('erp_bootstrap_current_user_access');
    if (response == null) return null;
    final result = Map<String, dynamic>.from(response as Map);
    if (result['ok'] != true) return null;
    final user = Map<String, dynamic>.from(result['user'] as Map);
    final role = Map<String, dynamic>.from(result['role'] as Map);
    final permissionRows = (result['permissions'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row));
    _bootstrapPermissionCodes = permissionRows
        .map((row) => row['code']?.toString().trim())
        .whereType<String>()
        .where((code) => code.isNotEmpty)
        .toSet();
    user
      ..['cloudAuthUid'] = uid
      ..['email'] = email.trim().toLowerCase()
      ..['authProvider'] = 'supabase'
      ..['cloudEmailVerified'] = emailVerified ? 1 : 0
      ..['roleName'] = role['name'] ?? role['name_ar'] ?? ''
      ..['lastLoginAt'] = DateTime.now().toUtc().toIso8601String();
    return UserModel.fromMap(user);
  }

  Future<Map<String, dynamic>> _snapshot({bool force = false}) async {
    final cached = _snapshotCache;
    final cachedAt = _snapshotCachedAt;
    if (!force &&
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _snapshotTtl) {
      return cached;
    }
    final inFlight = _snapshotInFlight;
    if (!force && inFlight != null) return inFlight;

    final request = _client.rpc('erp_access_cloud_snapshot').then((value) {
      final snapshot = Map<String, dynamic>.from(value as Map);
      _snapshotCache = snapshot;
      _snapshotCachedAt = DateTime.now();
      return snapshot;
    });
    _snapshotInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_snapshotInFlight, request)) _snapshotInFlight = null;
    }
  }

  void _invalidateSnapshot() {
    _snapshotCache = null;
    _snapshotCachedAt = null;
  }

  /// Invalidates the access snapshot after trusted Edge Functions mutate users.
  /// Those functions write directly with the service role, so the repository
  /// cannot observe the mutation unless its short-lived snapshot is cleared.
  void invalidateSnapshot() => _invalidateSnapshot();

  Future<List<UserModel>> getUsers({bool force = false}) async {
    final snapshot = await _snapshot(force: force);
    final roles = <String, String>{
      for (final item in (snapshot['roles'] as List? ?? const []))
        Map<String, dynamic>.from(item as Map)['id'].toString():
            (Map<String, dynamic>.from(item)['name'] ?? '').toString(),
    };
    return (snapshot['users'] as List? ?? const []).map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      map['roleName'] = roles[map['roleId']?.toString()] ?? '';
      return UserModel.fromMap(map);
    }).toList();
  }

  Future<List<RoleModel>> getRoles({bool force = false}) async {
    final snapshot = await _snapshot(force: force);
    return (snapshot['roles'] as List? ?? const [])
        .map(
          (item) => RoleModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .where((role) => role.isActive)
        .toList();
  }

  Future<List<PermissionModel>> getPermissions({bool force = false}) async {
    final snapshot = await _snapshot(force: force);
    return (snapshot['permissions'] as List? ?? const [])
        .map(
          (item) =>
              PermissionModel.fromMap(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<Set<String>> getRolePermissions(String roleId) async {
    final snapshot = await _snapshot();
    final permissionCodes = <String, String>{
      for (final item in (snapshot['permissions'] as List? ?? const []))
        Map<String, dynamic>.from(item as Map)['id'].toString():
            Map<String, dynamic>.from(item)['code'].toString(),
    };
    return (snapshot['role_permissions'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => item['roleId'] == roleId)
        .map((item) => permissionCodes[item['permissionId']?.toString()])
        .whereType<String>()
        .toSet();
  }

  Future<void> saveRolePermissions(
    String roleId,
    Set<String> codes, {
    UserModel? performedBy,
  }) async {
    await _client.rpc(
      'erp_set_cloud_role_permissions',
      params: {'p_role_id': roleId, 'p_permission_codes': codes.toList()},
    );
    _invalidateSnapshot();
    await addAudit(
      action: 'update',
      module: 'permissions',
      description: 'Updated role permissions',
      user: performedBy,
      entityId: roleId,
    );
  }

  Future<UserPermissionOverrideState> getUserPermissionOverride(
    String userId,
  ) async {
    final result = await _client.rpc(
      'erp_get_cloud_user_permission_override',
      params: {'p_user_id': userId},
    );
    final data = Map<String, dynamic>.from(result as Map? ?? const {});
    final rawCodes = data['codes'] as List? ?? const [];
    return UserPermissionOverrideState(
      enabled: data['hasOverride'] == true,
      codes: rawCodes
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet(),
    );
  }

  Future<void> clearUserPermissionOverride(
    String userId, {
    UserModel? performedBy,
  }) async {
    await _client.rpc(
      'erp_clear_cloud_user_permissions',
      params: {'p_user_id': userId},
    );
    _invalidateSnapshot();
    await addAudit(
      action: 'update',
      module: 'permissions',
      description: 'Restored inherited role permissions',
      user: performedBy,
      entityType: 'user',
      entityId: userId,
    );
  }

  Future<Set<String>> getUserPermissions(String userId) async {
    final result = await _client.rpc(
      'erp_get_cloud_user_permissions',
      params: {'p_user_id': userId},
    );
    return (result as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<void> saveUserPermissions(
    String userId,
    Set<String> codes, {
    UserModel? performedBy,
  }) async {
    await _client.rpc(
      'erp_set_cloud_user_permissions',
      params: {'p_user_id': userId, 'p_permission_codes': codes.toList()},
    );
    _invalidateSnapshot();
    await addAudit(
      action: 'update',
      module: 'permissions',
      description: 'Updated user-specific permissions',
      user: performedBy,
      entityType: 'user',
      entityId: userId,
    );
  }

  Future<UserModel> updateCurrentUserProfile({
    required UserModel currentUser,
    required String fullName,
    required String phone,
    required String? avatarBase64,
  }) async {
    final result = await _client.rpc(
      'erp_update_current_user_profile',
      params: {
        'p_full_name': fullName.trim(),
        'p_phone': phone.trim(),
        'p_avatar_base64': avatarBase64,
      },
    );
    _invalidateSnapshot();
    final payload = Map<String, dynamic>.from(result as Map);
    payload['roleName'] = currentUser.roleName;
    return UserModel.fromMap(payload);
  }

  Future<bool> usernameExists(String username, {String? excludeId}) async {
    final users = await getUsers();
    final normalized = username.trim().toLowerCase();
    return users.any(
      (u) => u.id != excludeId && u.username.toLowerCase() == normalized,
    );
  }

  Future<void> addUser(UserModel user, {UserModel? performedBy}) async {
    await _writeRecord('users', user.id, user.toMap());
    await addAudit(
      action: 'create',
      module: 'users',
      description: 'Created user ${user.fullName}',
      user: performedBy,
      entityId: user.id,
    );
  }

  Future<void> updateUser(UserModel user, {UserModel? performedBy}) async {
    await _writeRecord('users', user.id, user.toMap());
    await addAudit(
      action: 'update',
      module: 'users',
      description: 'Updated user ${user.fullName}',
      user: performedBy,
      entityId: user.id,
    );
  }

  Future<void> deleteUser(UserModel user, {UserModel? performedBy}) async {
    await _client.rpc(
      'erp_delete_cloud_access_record',
      params: {'p_entity_type': 'users', 'p_record_id': user.id},
    );
    _invalidateSnapshot();
    await addAudit(
      action: 'delete',
      module: 'users',
      description: 'Deleted user ${user.fullName}',
      user: performedBy,
      entityId: user.id,
    );
  }

  Future<List<AuditLogModel>> getAuditLogs([
    String query = '',
    String outcome = 'all',
    bool force = false,
  ]) async {
    final companyId = CloudTenantContext.instance.companyUuid;
    if (companyId == null || companyId.trim().isEmpty) {
      return const <AuditLogModel>[];
    }
    final response = await _client.rpc(
      'erp_v2300_audit_feed',
      params: {
        'p_company_id': companyId,
        'p_limit': 1000,
        'p_query': query.trim(),
        'p_outcome': outcome,
      },
    );
    final rows = response is List ? response : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((item) => AuditLogModel.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> addAudit({
    required String action,
    required String module,
    required String description,
    UserModel? user,
    String? entityType,
    String? entityId,
    String severity = 'info',
    String outcome = 'success',
    String source = 'application',
    Map<String, Object?>? metadata,
    String? correlationId,
  }) async {
    final companyId = CloudTenantContext.instance.companyUuid;
    if (companyId == null || companyId.trim().isEmpty) return;
    await _client.rpc(
      'erp_v2300_record_app_audit',
      params: {
        'p_company_id': companyId,
        'p_action': action,
        'p_module': module,
        'p_description': description,
        'p_entity_type': entityType ?? module,
        'p_entity_id': entityId,
        'p_outcome': outcome,
        'p_severity': severity,
        'p_source': source,
        'p_user_name': user?.fullName,
        'p_metadata': metadata ?? const <String, Object?>{},
        'p_correlation_id': correlationId,
      },
    );
  }

  Future<void> _writeRecord(
    String entity,
    String id,
    Map<String, Object?> payload,
  ) async {
    await _client.rpc(
      'erp_upsert_cloud_access_record',
      params: {
        'p_entity_type': entity,
        'p_record_id': id,
        'p_payload': payload,
      },
    );
    _invalidateSnapshot();
  }
}
