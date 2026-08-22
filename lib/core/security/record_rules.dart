import 'access_policy_models.dart';
import 'permission_contract.dart';

abstract final class RecordRules {
  static bool sameTenant(AccessRequest request) {
    final resourceTenant = request.resource.tenantId;
    return resourceTenant == null || resourceTenant == request.subject.tenantId;
  }

  static bool sameCompany(AccessRequest request) {
    final resourceCompany = request.resource.companyId;
    return resourceCompany == null ||
        resourceCompany == request.subject.companyId;
  }

  static bool sameBranch(AccessRequest request) {
    final resourceBranch = request.resource.branchId;
    return resourceBranch == null || resourceBranch == request.subject.branchId;
  }

  static bool ownRecord(AccessRequest request) {
    final owner = request.resource.ownerUserId;
    return owner != null && owner == request.subject.userId;
  }

  static bool companyOrOwnRecord(AccessRequest request) {
    return sameCompany(request) || ownRecord(request);
  }

  /// Per-module record visibility. Existing installations remain compatible
  /// until an administrator assigns one of the new scope permissions. The
  /// precedence and fallback are centralized in [PermissionContract] so UI
  /// policy checks remain aligned with PostgreSQL R84 semantics.
  static bool permissionScoped(
    AccessRequest request, {
    required String module,
  }) {
    if (!sameTenant(request) || !sameCompany(request)) return false;
    if (request.subject.isSystemAdmin) return true;

    final scope = PermissionContract.resolveRecordScope(
      request.subject.permissionCodes,
      module,
    );
    if (scope == RecordScopeMode.own) return ownRecord(request);

    // Explicit all and the deliberate R84 legacy fallback are both visible.
    return true;
  }
}
