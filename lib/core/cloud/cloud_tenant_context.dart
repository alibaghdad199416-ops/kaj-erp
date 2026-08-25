import 'package:shared_preferences/shared_preferences.dart';

/// Active tenant selection cached for user convenience. Business data remains in Supabase.
class CloudTenantContext {
  CloudTenantContext._();

  static final CloudTenantContext instance = CloudTenantContext._();

  static const _companyKey = 'cloud.active_company_id';
  static const _companyUuidKey = 'cloud.active_company_uuid';
  static const _branchKey = 'cloud.active_branch_id';
  static const _roleKey = 'cloud.active_role_code';
  static const _adminKey = 'cloud.active_system_admin';

  String _companyId = 'quality-line';
  String? _companyUuid;
  String? _branchId;
  String _roleCode = 'signed_out';
  bool _isSystemAdmin = false;

  String get companyId => _companyId;
  String? get companyUuid => _companyUuid;
  String? get branchId => _branchId;
  String get roleCode => _roleCode;
  bool get isSystemAdmin => _isSystemAdmin;
  bool get isBootstrapReady =>
      _companyUuid != null && _roleCode != 'signed_out';

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _companyId = preferences.getString(_companyKey) ?? 'quality-line';
    _companyUuid = preferences.getString(_companyUuidKey);
    _branchId = preferences.getString(_branchKey);
    _roleCode = preferences.getString(_roleKey) ?? 'signed_out';
    _isSystemAdmin = preferences.getBool(_adminKey) ?? false;
  }

  Future<void> selectTenant({
    required String companyId,
    String? companyUuid,
    String? branchId,
    String roleCode = 'user',
    bool isSystemAdmin = false,
  }) async {
    final normalizedCompanyId = companyId.trim();
    if (normalizedCompanyId.isEmpty) {
      throw ArgumentError.value(companyId, 'companyId', 'Must not be empty');
    }

    _companyId = normalizedCompanyId;
    _companyUuid = companyUuid?.trim().isEmpty == true
        ? null
        : companyUuid?.trim();
    _branchId = branchId?.trim().isEmpty == true ? null : branchId?.trim();
    _roleCode = roleCode.trim().isEmpty ? 'user' : roleCode.trim();
    _isSystemAdmin = isSystemAdmin;

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_companyKey, _companyId);
    await _writeNullable(preferences, _companyUuidKey, _companyUuid);
    await _writeNullable(preferences, _branchKey, _branchId);
    await preferences.setString(_roleKey, _roleCode);
    await preferences.setBool(_adminKey, _isSystemAdmin);
  }

  Future<void> clearCloudSelection() async {
    _companyUuid = null;
    _branchId = null;
    _roleCode = 'signed_out';
    _isSystemAdmin = false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_companyUuidKey);
    await preferences.remove(_branchKey);
    await preferences.remove(_roleKey);
    await preferences.remove(_adminKey);
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
