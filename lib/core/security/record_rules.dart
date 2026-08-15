import 'access_policy_models.dart';

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
  /// until an administrator assigns one of the new scope permissions. Once
  /// `.records.own` or `.records.all` exists on the user it becomes explicit.
  static bool permissionScoped(
    AccessRequest request, {
    required String module,
  }) {
    if (!sameTenant(request) || !sameCompany(request)) return false;
    if (request.subject.isSystemAdmin) return true;

    final permissions = request.subject.permissionCodes;
    final allCode = '$module.records.all';
    final ownCode = '$module.records.own';
    if (permissions.contains(allCode)) return true;
    if (permissions.contains(ownCode)) return ownRecord(request);

    // Legacy-safe default until a scope is explicitly selected for this module.
    return true;
  }
}
