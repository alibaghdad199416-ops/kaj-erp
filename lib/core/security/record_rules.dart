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
}
