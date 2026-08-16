import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Active tenant selection cached for user convenience. Business data remains in Supabase.
///
/// Browser keys are scoped by both the configured Supabase project and the
/// authenticated user that selected the tenant. Legacy project-only and fully
/// unscoped keys are discarded because they can resurrect another user's or an
/// older runtime's company UUID/role after a backend/session change.
class CloudTenantContext {
  CloudTenantContext._();

  static final CloudTenantContext instance = CloudTenantContext._();

  static const _companyKey = 'cloud.active_company_id';
  static const _companyUuidKey = 'cloud.active_company_uuid';
  static const _branchKey = 'cloud.active_branch_id';
  static const _roleKey = 'cloud.active_role_code';
  static const _adminKey = 'cloud.active_system_admin';
  static const _authUserKey = 'cloud.active_auth_user_id';
  static const _cacheEpochKey = 'cloud.tenant_cache_epoch';
  static const _cacheEpoch = 'r74-project-user-tenant-v1';

  String _companyId = 'quality-line';
  String? _companyUuid;
  String? _branchId;
  String _roleCode = 'signed_out';
  bool _isSystemAdmin = false;
  String? _authUserId;

  String get companyId => _companyId;
  String? get companyUuid => _companyUuid;
  String? get branchId => _branchId;
  String get roleCode => _roleCode;
  bool get isSystemAdmin => _isSystemAdmin;
  String? get authUserId => _authUserId;
  bool get isBootstrapReady =>
      _companyUuid != null && _roleCode != 'signed_out' && _authUserId != null;

  String _scopedKey(String baseKey) =>
      '$baseKey.${SupabaseConfig.browserStorageNamespace}';

  String? _currentAuthUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  void _resetMemory() {
    _companyId = 'quality-line';
    _companyUuid = null;
    _branchId = null;
    _roleCode = 'signed_out';
    _isSystemAdmin = false;
    _authUserId = null;
  }

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();

    // Pre-R71 keys were shared by every hosted backend. Never migrate them to
    // the current project because their provenance is unknowable.
    await _removeLegacyUnscopedKeys(preferences);

    final currentAuthUserId = _currentAuthUserId();
    final cachedAuthUserId = preferences.getString(_scopedKey(_authUserKey));
    final cachedEpoch = preferences.getString(_scopedKey(_cacheEpochKey));

    // R74 invalidates the earlier project-only tenant cache once. It also
    // refuses to restore a company selected by a different Auth user in the
    // same Supabase project.
    if (currentAuthUserId == null ||
        cachedAuthUserId != currentAuthUserId ||
        cachedEpoch != _cacheEpoch) {
      await _removeScopedKeys(preferences);
      _resetMemory();
      return;
    }

    _authUserId = cachedAuthUserId;
    _companyId =
        preferences.getString(_scopedKey(_companyKey)) ?? 'quality-line';
    _companyUuid = preferences.getString(_scopedKey(_companyUuidKey));
    _branchId = preferences.getString(_scopedKey(_branchKey));
    _roleCode = preferences.getString(_scopedKey(_roleKey)) ?? 'signed_out';
    _isSystemAdmin = preferences.getBool(_scopedKey(_adminKey)) ?? false;
  }

  Future<void> selectTenant({
    required String authUserId,
    required String companyId,
    String? companyUuid,
    String? branchId,
    String roleCode = 'user',
    bool isSystemAdmin = false,
  }) async {
    final normalizedAuthUserId = authUserId.trim();
    if (normalizedAuthUserId.isEmpty) {
      throw ArgumentError.value(authUserId, 'authUserId', 'Must not be empty');
    }
    final currentAuthUserId = _currentAuthUserId();
    if (currentAuthUserId != null &&
        currentAuthUserId != normalizedAuthUserId) {
      throw StateError(
        'Authenticated user changed while selecting the company tenant.',
      );
    }

    final normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'Must not be empty');
    }

    _authUserId = normalizedAuthUserId;
    _companyId = normalizedCompanyId;
    _companyUuid = companyUuid?.trim().isEmpty == true
        ? null
        : companyUuid?.trim();
    _branchId = branchId?.trim().isEmpty == true ? null : branchId?.trim();
    _roleCode = roleCode.trim().isEmpty ? 'user' : roleCode.trim();
    _isSystemAdmin = isSystemAdmin;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_scopedKey(_authUserKey), normalizedAuthUserId);
    await preferences.setString(_scopedKey(_cacheEpochKey), _cacheEpoch);
    await preferences.setString(_scopedKey(_companyKey), _companyId);
    await _writeNullable(
      preferences,
      _scopedKey(_companyUuidKey),
      _companyUuid,
    );
    await _writeNullable(preferences, _scopedKey(_branchKey), _branchId);
    await preferences.setString(_scopedKey(_roleKey), _roleCode);
    await preferences.setBool(_scopedKey(_adminKey), _isSystemAdmin);
  }

  Future<void> clearCloudSelection() async {
    _resetMemory();
    final preferences = await SharedPreferences.getInstance();
    await _removeScopedKeys(preferences);
    await _removeLegacyUnscopedKeys(preferences);
  }

  Future<void> _removeScopedKeys(SharedPreferences preferences) async {
    await preferences.remove(_scopedKey(_companyKey));
    await preferences.remove(_scopedKey(_companyUuidKey));
    await preferences.remove(_scopedKey(_branchKey));
    await preferences.remove(_scopedKey(_roleKey));
    await preferences.remove(_scopedKey(_adminKey));
    await preferences.remove(_scopedKey(_authUserKey));
    await preferences.remove(_scopedKey(_cacheEpochKey));
  }

  Future<void> _removeLegacyUnscopedKeys(SharedPreferences preferences) async {
    await preferences.remove(_companyKey);
    await preferences.remove(_companyUuidKey);
    await preferences.remove(_branchKey);
    await preferences.remove(_roleKey);
    await preferences.remove(_adminKey);
    await preferences.remove(_authUserKey);
    await preferences.remove(_cacheEpochKey);
  }

  Future<void> _writeNullable(
    SharedPreferences preferences,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await preferences.remove(key);
    } else {
      await preferences.setString(key, value);
    }
  }
}
