import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/cloud/cloud_bootstrap.dart';
import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/cloud/cloud_realtime_bridge.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_membership_service.dart';
import 'package:quality_line_erp/core/cloud/supabase_user_administration_service.dart';

import 'package:quality_line_erp/core/audit/execution_context.dart';
import 'package:quality_line_erp/core/security/security.dart';

import 'package:quality_line_erp/features/settings/access/models/audit_log_model.dart';
import 'package:quality_line_erp/features/settings/access/models/field_permission_catalog.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_model.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_catalog.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_codes.dart';
import 'package:quality_line_erp/features/settings/access/models/role_model.dart';
import 'package:quality_line_erp/features/settings/access/models/user_model.dart';
import 'package:quality_line_erp/features/settings/access/repositories/access_repository.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class AccessController extends ChangeNotifier {
  AccessController({AccessRepository? repository})
    : _repository = repository ?? AccessRepository();

  final AccessRepository _repository;
  final AccessPolicyEngine _policyEngine = AccessPolicyEngine();

  List<UserModel> _users = [];
  List<RoleModel> _roles = [];
  List<PermissionModel> _permissions = [];
  List<AuditLogModel> _logs = [];
  Set<String> _currentPermissions = {};
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isAuthenticating = false;
  bool _isTemporaryPreview = false;
  String? _errorMessage;

  List<UserModel> get users => List.unmodifiable(_users);
  List<RoleModel> get roles => List.unmodifiable(_roles);
  List<PermissionModel> get permissions {
    final byCode = <String, PermissionModel>{
      for (final permission in PermissionCatalog.all)
        permission.code: permission,
      for (final permission in _permissions) permission.code: permission,
    };
    final values = byCode.values.toList()
      ..sort((a, b) {
        final module = a.module.compareTo(b.module);
        return module != 0 ? module : a.name.compareTo(b.name);
      });
    return List.unmodifiable(values);
  }

  List<AuditLogModel> get auditLogs => List.unmodifiable(_logs);
  Set<String> get currentPermissions => Set.unmodifiable(_currentPermissions);
  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isAuthenticating => _isAuthenticating;
  bool get isTemporaryPreview => _isTemporaryPreview;
  String? get errorMessage => _errorMessage;
  int get activeUsers => _users.where((user) => user.isActive).length;
  bool get isSystemAdmin =>
      CloudTenantContext.instance.isSystemAdmin ||
      CloudTenantContext.instance.roleCode == 'owner' ||
      _currentUser?.roleId == 'role-admin';
  bool get canAssignSystemAdmin =>
      CloudTenantContext.instance.roleCode == 'owner';
  AccessPolicyEngine get policyEngine => _policyEngine;

  AccessSubject? get currentAccessSubject {
    final user = _currentUser;
    if (user == null) return null;
    return AccessSubject(
      userId: user.id,
      roleIds: {user.roleId},
      permissionCodes: _currentPermissions,
      isSystemAdmin: isSystemAdmin,
    );
  }

  void replaceAccessPolicies(Iterable<AccessPolicy> policies) {
    _policyEngine.replacePolicies(policies);
    notifyListeners();
  }

  AccessDecision evaluateAccess({
    required AccessResource resource,
    required AccessOperation operation,
    Set<String> requestedFields = const {},
  }) {
    final subject = currentAccessSubject;
    if (subject == null) return AccessDecision.deniedByDefault;
    return _policyEngine.evaluate(
      AccessRequest(
        subject: subject,
        resource: resource,
        operation: operation,
        requestedFields: requestedFields,
      ),
    );
  }

  Future<void> requireAccess({
    required AccessResource resource,
    required AccessOperation operation,
    Set<String> requestedFields = const {},
  }) async {
    final decision = evaluateAccess(
      resource: resource,
      operation: operation,
      requestedFields: requestedFields,
    );
    if (decision.allowed) return;
    await recordDeniedAccess('policy:${resource.type}:${operation.name}');
    throw StateError('ليس لديك صلاحية للوصول إلى هذا السجل.');
  }

  bool hasPermission(String code) {
    return isSystemAdmin || _currentPermissions.contains(code);
  }

  /// Returns true when granular field restrictions are enabled for [resource].
  /// Legacy roles remain compatible until the explicit restrict permission is
  /// granted. System administrators always bypass field restrictions.
  bool hasRestrictedFields(String resource) {
    if (isSystemAdmin) return false;
    return _currentPermissions.contains(
      FieldPermissionCatalog.restrictCode(resource),
    );
  }

  bool canViewField(String resource, String field, {String? viewPermission}) {
    if (isSystemAdmin) return true;
    if (viewPermission != null && !hasPermission(viewPermission)) return false;
    if (!hasRestrictedFields(resource)) return true;
    if (!FieldPermissionCatalog.isKnownField(resource, field)) return false;
    return hasPermission(FieldPermissionCatalog.viewCode(resource, field)) ||
        hasPermission(FieldPermissionCatalog.editCode(resource, field));
  }

  bool canEditField(
    String resource,
    String field, {
    String? writePermission,
    String? viewPermission,
  }) {
    if (isSystemAdmin) return true;
    if (viewPermission != null && !hasPermission(viewPermission)) return false;
    if (writePermission != null && !hasPermission(writePermission))
      return false;
    if (!hasRestrictedFields(resource)) {
      // Historical settings RPCs were administrator-only. Keep that secure
      // default until granular settings restrictions are explicitly enabled.
      if (resource == 'settings') return false;
      return true;
    }
    if (!FieldPermissionCatalog.isKnownField(resource, field)) return false;
    return hasPermission(FieldPermissionCatalog.editCode(resource, field));
  }

  Set<String> filterReadableFieldNames(
    String resource,
    Iterable<String> fields, {
    String? viewPermission,
  }) {
    return fields
        .where(
          (field) =>
              canViewField(resource, field, viewPermission: viewPermission),
        )
        .toSet();
  }

  Set<String> filterWritableFieldNames(
    String resource,
    Iterable<String> fields, {
    String? writePermission,
    String? viewPermission,
  }) {
    return fields
        .where(
          (field) => canEditField(
            resource,
            field,
            writePermission: writePermission,
            viewPermission: viewPermission,
          ),
        )
        .toSet();
  }

  Future<void> requirePermission(String code) async {
    if (hasPermission(code)) return;
    await recordDeniedAccess(code);
    throw StateError('ليس لديك صلاحية لتنفيذ هذه العملية.');
  }

  Future<void> loadAccess({bool force = false}) async {
    _setLoading(true);
    _errorMessage = null;
    try {
      final results = await Future.wait<dynamic>([
        _repository.getUsers(force: force),
        _repository.getRoles(force: force),
        _repository.getPermissions(force: force),
        _repository.getAuditLogs('', 'all', force),
      ]);
      _users = results[0] as List<UserModel>;
      final current = _currentUser;
      if (current != null && !_users.any((user) => user.id == current.id)) {
        _users = [current, ..._users];
      }
      _roles = results[1] as List<RoleModel>;
      _permissions = results[2] as List<PermissionModel>;
      _logs = results[3] as List<AuditLogModel>;
    } catch (error) {
      AppLogger.debug('AccessController.load failed: $error');
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل بيانات الوصول.',
      );
    } finally {
      _setLoading(false);
    }
  }

  /// Restores the persisted Supabase browser session and rebuilds the ERP
  /// authorization context without asking the user to enter credentials again.
  /// Explicit logout still clears the persisted Supabase session.
  Future<bool> restorePersistedSession() async {
    _errorMessage = null;
    try {
      final bootstrap = await CloudBootstrap.initialize().timeout(
        const Duration(seconds: 25),
      );
      if (!bootstrap.supabaseReady) return false;

      final cloudUser = Supabase.instance.client.auth.currentUser;
      final session = Supabase.instance.client.auth.currentSession;
      final cloudEmail = cloudUser?.email;
      if (cloudUser == null || session == null || cloudEmail == null) {
        return false;
      }

      await CloudTenantMembershipService.instance
          .activateForCurrentUser()
          .timeout(const Duration(seconds: 15));
      final user = await _repository.bootstrapCurrentCloudAccess(
        uid: cloudUser.id,
        email: cloudEmail,
        emailVerified: cloudUser.emailConfirmedAt != null,
      );
      if (user == null) return false;

      await _activateUser(user);
      return true;
    } catch (error, stackTrace) {
      AppLogger.debug('Persisted Supabase session restore skipped: $error');
      AppLogger.stack(stackTrace);
      return false;
    }
  }

  /// Prepares the interactive login surface without destroying a valid
  /// persisted session. This keeps runtime Supabase/Firebase configuration
  /// untouched and avoids an unnecessary credentials round-trip.
  Future<void> prepareInteractiveLogin() async {
    if (Supabase.instance.client.auth.currentSession != null) return;
    _currentUser = null;
    _currentPermissions = <String>{};
    _isTemporaryPreview = false;
    _errorMessage = null;
    notifyListeners();
    await AppExecutionContext.clear();
    await CloudTenantContext.instance.clearCloudSelection();
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    _isAuthenticating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final email = username.trim().toLowerCase();
      if (!email.contains('@')) {
        _errorMessage = 'استخدم البريد الإلكتروني المسجل في Supabase.';
        return false;
      }

      final bootstrap = await CloudBootstrap.initialize().timeout(
        const Duration(seconds: 25),
      );
      if (!bootstrap.supabaseReady) {
        _errorMessage = 'يتطلب تسجيل الدخول تهيئة Supabase.';
        return false;
      }

      final response = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 25));
      final cloudUser = response.user;
      final cloudEmail = cloudUser?.email;
      if (cloudUser == null || cloudEmail == null) {
        _errorMessage = 'لم تُرجع Supabase هوية مستخدم صالحة.';
        return false;
      }

      try {
        await CloudTenantMembershipService.instance
            .activateForCurrentUser()
            .timeout(const Duration(seconds: 15));

        final user = await _repository.bootstrapCurrentCloudAccess(
          uid: cloudUser.id,
          email: cloudEmail,
          emailVerified: cloudUser.emailConfirmedAt != null,
        );
        if (user == null) {
          await _discardFailedCloudLoginSession();
          _errorMessage =
              'الحساب صحيح لكنه غير مرتبط بمستخدم ERP فعال داخل الشركة.';
          return false;
        }

        await _activateUser(user);
        return true;
      } catch (_) {
        await _discardFailedCloudLoginSession();
        rethrow;
      }
    } on AuthException catch (error) {
      _errorMessage = _supabaseAuthMessage(error.message);
      return false;
    } on PostgrestException catch (error) {
      _errorMessage = _accessBootstrapMessage(error.message);
      return false;
    } on TimeoutException {
      _errorMessage =
          'انتهت مهلة تسجيل الدخول. تحقق من الإنترنت وأعد المحاولة.';
      return false;
    } catch (error, stackTrace) {
      AppLogger.debug('Hybrid ERP login failed: $error');
      AppLogger.stack(stackTrace);
      _errorMessage =
          'تعذر إكمال تسجيل الدخول عبر Supabase. تحقق من إعدادات Auth وقاعدة البيانات.';
      return false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  Future<void> _activateUser(UserModel user) async {
    // The bootstrap RPC already returns the permissions that belong to the
    // authenticated role. Prefer that atomic result so login does not depend
    // on a second snapshot RPC. The fallback supports older database schemas.
    final bootstrapPermissions = _repository.takeBootstrapPermissionCodes();
    final permissionOverride = await _repository
        .getUserPermissionOverride(user.id)
        .timeout(const Duration(seconds: 12));
    final permissions = permissionOverride.enabled
        ? permissionOverride.codes
        : (bootstrapPermissions ??
              await _repository
                  .getRolePermissions(user.roleId)
                  .timeout(const Duration(seconds: 12)));
    await AppExecutionContext.setUser(
      id: user.id,
      name: user.fullName,
    ).timeout(const Duration(seconds: 5));
    _currentUser = user;
    _currentPermissions = permissions;

    // Canonical-state repair runs before authenticated module data starts
    // loading. Administrators therefore never begin a new session from a
    // resurrected/stale master snapshot. The database operation is repeat-safe;
    // normal users simply skip it.
    if (isSystemAdmin) {
      await _reconcileCanonicalStateAfterLogin();
    }
    notifyListeners();

    // Realtime and the audit refresh are enhancements, not authentication
    // prerequisites. Starting them in the background removes a long tail from
    // the first login click while preserving automatic refresh afterwards.
    unawaited(_startRealtimeAfterLogin());
    unawaited(_recordSuccessfulLogin(user));
  }

  Future<void> _reconcileCanonicalStateAfterLogin() async {
    try {
      final result = await CloudFeatureCommand.instance
          .reconcileCanonicalState()
          .timeout(const Duration(seconds: 45));
      final health = result['health'];
      AppLogger.debug('R22 canonical-state reconciliation completed: $health');
    } catch (error, stackTrace) {
      // Authentication remains available for emergency administration, but the
      // failure is explicit in logs/System Monitor instead of silently falling
      // back to stale local state.
      AppLogger.debug('R22 canonical-state reconciliation failed: $error');
      AppLogger.stack(stackTrace);
    }
  }

  Future<void> _startRealtimeAfterLogin() async {
    try {
      await CloudRealtimeBridge.instance.start().timeout(
        const Duration(seconds: 12),
      );
    } catch (error, stackTrace) {
      AppLogger.debug('Cloud realtime bridge could not start: $error');
      AppLogger.stack(stackTrace);
    }
  }

  Future<void> _discardFailedCloudLoginSession() async {
    await CloudRealtimeBridge.instance.stop();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      AppLogger.debug(
        'Failed to discard incomplete Supabase login session: $error',
      );
    }
  }

  String _accessBootstrapMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('membership_not_found')) {
      return 'الحساب صحيح لكنه غير مربوط بشركة فعالة.';
    }
    if (normalized.contains('erp_user_not_found_or_inactive')) {
      return 'الحساب صحيح لكنه غير مربوط بمستخدم ERP فعال.';
    }
    if (normalized.contains('erp_role_not_found_or_inactive')) {
      return 'دور المستخدم غير موجود أو غير فعال في بيانات الشركة.';
    }
    return 'تعذر تحميل ملف المستخدم وصلاحياته من السحابة.';
  }

  String _supabaseAuthMessage(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid login credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    }
    if (normalized.contains('email not confirmed')) {
      return 'يجب تأكيد البريد الإلكتروني قبل تسجيل الدخول.';
    }
    if (normalized.contains('too many')) {
      return 'محاولات كثيرة. انتظر قليلًا ثم أعد المحاولة.';
    }
    return 'فشل تسجيل الدخول عبر Supabase.';
  }

  Future<void> _recordSuccessfulLogin(UserModel user) async {
    try {
      await _repository
          .addAudit(
            action: 'login',
            module: 'auth',
            description: 'تم تسجيل الدخول بنجاح',
            user: user,
            entityType: 'user',
            entityId: user.id,
          )
          .timeout(const Duration(seconds: 8));
      _logs = await _repository.getAuditLogs().timeout(
        const Duration(seconds: 8),
      );
      notifyListeners();
    } catch (error) {
      AppLogger.debug('Login audit refresh skipped: $error');
    }
  }

  Future<void> logout() async {
    final user = _currentUser;

    // Clear the in-memory authorization state before any network operation so
    // routing reacts immediately even when audit or Supabase sign-out is slow.
    _currentUser = null;
    _currentPermissions = {};
    _isTemporaryPreview = false;
    notifyListeners();

    try {
      await CloudRealtimeBridge.instance.stop().timeout(
        const Duration(seconds: 3),
      );
    } catch (error) {
      AppLogger.debug('Realtime stop during logout skipped: $error');
    }
    if (user != null) {
      try {
        await _repository
            .addAudit(
              action: 'logout',
              module: 'auth',
              description: 'تم تسجيل الخروج',
              user: user,
              entityType: 'user',
              entityId: user.id,
            )
            .timeout(const Duration(seconds: 4));
      } catch (error) {
        AppLogger.debug('Logout audit skipped: $error');
      }
    }
    try {
      await Supabase.instance.client.auth.signOut().timeout(
        const Duration(seconds: 10),
      );
    } catch (error) {
      AppLogger.debug('Supabase sign-out skipped: $error');
    }
    await AppExecutionContext.clear();
    await CloudTenantContext.instance.clearCloudSelection();
    try {
      _logs = await _repository.getAuditLogs().timeout(
        const Duration(seconds: 4),
      );
    } catch (error) {
      AppLogger.debug('Audit refresh after logout skipped: $error');
      _logs = const [];
    }
    notifyListeners();
  }

  Future<void> recordAuditEvent({
    required String action,
    required String module,
    required String description,
    String? entityType,
    String? entityId,
    String severity = 'info',
    String outcome = 'success',
    String source = 'application',
    Map<String, Object?>? metadata,
  }) async {
    final user = _currentUser;
    if (user == null) return;
    await _repository.addAudit(
      action: action,
      module: module,
      description: description,
      user: user,
      entityType: entityType,
      entityId: entityId,
      severity: severity,
      outcome: outcome,
      source: source,
      metadata: metadata,
    );
  }

  Future<void> recordDeniedAccess(String permissionCode) async {
    final user = _currentUser;
    if (user == null) {
      return;
    }
    await _repository.addAudit(
      action: 'denied',
      module: 'permissions',
      description: 'تم رفض الوصول إلى الصلاحية $permissionCode',
      user: user,
      entityType: 'permission',
      entityId: permissionCode,
      severity: 'warning',
      outcome: 'denied',
      metadata: {'permissionCode': permissionCode},
    );
  }

  Future<void> updateMyProfile({
    required String fullName,
    required String phone,
    required String? avatarBase64,
  }) async {
    final current = _currentUser;
    if (current == null) throw StateError('لا توجد جلسة مستخدم فعالة.');
    final updated = await _repository.updateCurrentUserProfile(
      currentUser: current,
      fullName: fullName,
      phone: phone,
      avatarBase64: avatarBase64,
    );
    _currentUser = updated;
    final index = _users.indexWhere((user) => user.id == updated.id);
    if (index >= 0) {
      _users[index] = updated;
    } else {
      _users = [updated, ..._users];
    }
    AppDataChangeBus.instance.publish(
      'users',
      operation: 'profile-update',
      entityId: updated.id,
    );
    notifyListeners();
  }

  Future<void> addUser(UserModel user, {required String password}) async {
    await requirePermission(PermissionCodes.usersCreate);
    if (!isSystemAdmin) {
      await recordDeniedAccess(PermissionCodes.usersCreate);
      throw StateError('إنشاء المستخدمين متاح لمدير النظام فقط.');
    }
    if (await _repository.usernameExists(user.username)) {
      throw StateError('اسم المستخدم مستخدم مسبقًا.');
    }
    await SupabaseUserAdministrationService.instance.createUser(
      email: user.email,
      password: password,
      fullName: user.fullName,
      localUserId: user.id,
      roleCode: user.roleId == 'role-admin' ? 'admin' : 'user',
      erpUserPayload: user.toMap(),
    );
    // The trusted Edge Function creates Auth, profile, membership and ERP
    // records atomically. A second client-side upsert could fail after the
    // cloud account was already created, which made the UI report a false
    // failure and kept the cached user list stale.
    _repository.invalidateSnapshot();
    await _refresh(force: true);
    AppDataChangeBus.instance.publish(
      'users',
      operation: 'insert',
      entityId: user.id,
    );
  }

  Future<void> updateUser(UserModel user) async {
    await requirePermission(PermissionCodes.usersUpdate);
    if (await _repository.usernameExists(user.username, excludeId: user.id)) {
      throw StateError('اسم المستخدم مستخدم مسبقًا.');
    }
    final cloudUserId = user.cloudAuthUid?.trim();
    if (cloudUserId != null && cloudUserId.isNotEmpty) {
      await SupabaseUserAdministrationService.instance.updateUser(
        cloudUserId: cloudUserId,
        localUserId: user.id,
        email: user.email,
        fullName: user.fullName,
        roleCode: _cloudRoleCode(user),
        isActive: user.isActive,
        erpUserPayload: user.toMap(),
      );
      _repository.invalidateSnapshot();
    } else {
      await _repository.updateUser(user, performedBy: _currentUser);
    }
    await _refresh(force: true);
    AppDataChangeBus.instance.publish(
      'users',
      operation: 'update',
      entityId: user.id,
    );
    if (_currentUser?.id == user.id) {
      var resolved = user;
      for (final item in _users) {
        if (item.id == user.id) {
          resolved = item;
          break;
        }
      }
      _currentUser = resolved;
      notifyListeners();
    }
  }

  Future<void> deleteUser(UserModel user) async {
    await requirePermission(PermissionCodes.usersDelete);
    if (user.id == _currentUser?.id) {
      throw StateError('لا يمكن حذف المستخدم المسجل حاليًا.');
    }
    final cloudUserId = user.cloudAuthUid?.trim();
    if (cloudUserId != null && cloudUserId.isNotEmpty) {
      await SupabaseUserAdministrationService.instance.deleteUser(
        cloudUserId: cloudUserId,
        localUserId: user.id,
      );
      _repository.invalidateSnapshot();
    } else {
      await _repository.deleteUser(user, performedBy: _currentUser);
    }
    await _refresh(force: true);
    AppDataChangeBus.instance.publish(
      'users',
      operation: 'delete',
      entityId: user.id,
    );
  }

  String _cloudRoleCode(UserModel user) {
    final currentCloudUserId = Supabase.instance.client.auth.currentUser?.id;
    if (user.cloudAuthUid == currentCloudUserId) {
      return CloudTenantContext.instance.roleCode;
    }
    return user.roleId == 'role-admin' ? 'admin' : 'user';
  }

  Future<Set<String>> getRolePermissions(String roleId) {
    return _repository.getRolePermissions(roleId);
  }

  Future<Set<String>> getUserPermissions(String userId) {
    return _repository.getUserPermissions(userId);
  }

  Future<UserPermissionOverrideState> getUserPermissionOverride(String userId) {
    return _repository.getUserPermissionOverride(userId);
  }

  Future<void> clearUserPermissionOverride(String userId) async {
    await requirePermission(PermissionCodes.usersUpdate);
    await _repository.clearUserPermissionOverride(
      userId,
      performedBy: _currentUser,
    );
    final currentUser = _currentUser;
    if (currentUser != null && currentUser.id == userId) {
      _currentPermissions = await _repository.getRolePermissions(
        currentUser.roleId,
      );
    }
    _logs = await _repository.getAuditLogs();
    AppDataChangeBus.instance.publish(
      'access',
      operation: 'user-permission-clear',
      entityId: userId,
    );
    notifyListeners();
  }

  Future<void> saveUserPermissions(String userId, Set<String> codes) async {
    await requirePermission(PermissionCodes.usersUpdate);
    await _repository.saveUserPermissions(
      userId,
      codes,
      performedBy: _currentUser,
    );
    if (_currentUser?.id == userId) {
      _currentPermissions = await _repository.getUserPermissions(userId);
    }
    _logs = await _repository.getAuditLogs();
    AppDataChangeBus.instance.publish(
      'access',
      operation: 'user-permission-save',
      entityId: userId,
    );
    notifyListeners();
  }

  Future<void> saveRolePermissions(String roleId, Set<String> codes) async {
    await requirePermission(PermissionCodes.usersUpdate);
    await _repository.saveRolePermissions(
      roleId,
      codes,
      performedBy: _currentUser,
    );
    if (_currentUser?.roleId == roleId) {
      _currentPermissions = await _repository.getRolePermissions(roleId);
    }
    _logs = await _repository.getAuditLogs();
    AppDataChangeBus.instance.publish(
      'access',
      operation: 'role-permission-save',
      entityId: roleId,
    );
    notifyListeners();
  }

  Future<void> searchAuditLogs(String query, {String outcome = 'all'}) async {
    _logs = await _repository.getAuditLogs(query, outcome);
    notifyListeners();
  }

  Future<void> _refresh({bool force = false}) async {
    if (force) _repository.invalidateSnapshot();
    final results = await Future.wait<dynamic>([
      _repository.getUsers(force: force),
      _repository.getAuditLogs('', 'all', force),
    ]);
    _users = results[0] as List<UserModel>;
    _logs = results[1] as List<AuditLogModel>;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
