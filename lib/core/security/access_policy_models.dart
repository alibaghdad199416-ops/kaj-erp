enum AccessOperation {
  read,
  create,
  update,
  delete,
  export,
  approve,
  manage,
  save,
  edit,
  cancel,
  reverse,
  print,
  openDetails,
  assign,
  transfer,
  post,
  reopen,
}

enum PolicyEffect { allow, deny }

class AccessSubject {
  const AccessSubject({
    required this.userId,
    required this.roleIds,
    required this.permissionCodes,
    this.companyId,
    this.branchId,
    this.tenantId,
    this.attributes = const {},
    this.isSystemAdmin = false,
  });

  final String userId;
  final Set<String> roleIds;
  final Set<String> permissionCodes;
  final String? companyId;
  final String? branchId;
  final String? tenantId;
  final Map<String, Object?> attributes;
  final bool isSystemAdmin;
}

class AccessResource {
  const AccessResource({
    required this.type,
    this.id,
    this.ownerUserId,
    this.companyId,
    this.branchId,
    this.tenantId,
    this.fields = const {},
  });

  final String type;
  final String? id;
  final String? ownerUserId;
  final String? companyId;
  final String? branchId;
  final String? tenantId;
  final Map<String, Object?> fields;
}

class AccessRequest {
  const AccessRequest({
    required this.subject,
    required this.resource,
    required this.operation,
    this.requestedFields = const {},
  });

  final AccessSubject subject;
  final AccessResource resource;
  final AccessOperation operation;
  final Set<String> requestedFields;
}

class AccessDecision {
  const AccessDecision({
    required this.allowed,
    required this.reason,
    this.matchedPolicyIds = const [],
    this.hiddenFields = const {},
    this.readOnlyFields = const {},
  });

  final bool allowed;
  final String reason;
  final List<String> matchedPolicyIds;
  final Set<String> hiddenFields;
  final Set<String> readOnlyFields;

  static const deniedByDefault = AccessDecision(
    allowed: false,
    reason: 'default_deny',
  );
}
