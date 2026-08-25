import 'access_policy_models.dart';

typedef AccessCondition = bool Function(AccessRequest request);

class AccessPolicy {
  const AccessPolicy({
    required this.id,
    required this.resourceType,
    required this.operations,
    required this.effect,
    this.requiredPermissions = const {},
    this.requiredRoles = const {},
    this.condition,
    this.hiddenFields = const {},
    this.readOnlyFields = const {},
    this.priority = 0,
    this.active = true,
    this.description = '',
  });

  final String id;
  final String resourceType;
  final Set<AccessOperation> operations;
  final PolicyEffect effect;
  final Set<String> requiredPermissions;
  final Set<String> requiredRoles;
  final AccessCondition? condition;
  final Set<String> hiddenFields;
  final Set<String> readOnlyFields;
  final int priority;
  final bool active;
  final String description;

  bool matches(AccessRequest request) {
    if (!active || resourceType != request.resource.type) return false;
    if (!operations.contains(request.operation)) return false;
    if (requiredPermissions.isNotEmpty &&
        !request.subject.permissionCodes.containsAll(requiredPermissions)) {
      return false;
    }
    if (requiredRoles.isNotEmpty &&
        request.subject.roleIds.intersection(requiredRoles).isEmpty) {
      return false;
    }
    return condition?.call(request) ?? true;
  }
}
