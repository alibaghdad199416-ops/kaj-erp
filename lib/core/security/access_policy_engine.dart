import 'access_policy.dart';
import 'access_policy_models.dart';

class AccessPolicyEngine {
  AccessPolicyEngine({Iterable<AccessPolicy> policies = const []}) {
    replacePolicies(policies);
  }

  final List<AccessPolicy> _policies = [];

  List<AccessPolicy> get policies => List.unmodifiable(_policies);

  void replacePolicies(Iterable<AccessPolicy> policies) {
    _policies
      ..clear()
      ..addAll(policies);
    _policies.sort((a, b) => b.priority.compareTo(a.priority));
  }

  AccessDecision evaluate(AccessRequest request) {
    if (request.subject.isSystemAdmin) {
      return const AccessDecision(allowed: true, reason: 'system_admin');
    }

    final matches = _policies
        .where((policy) => policy.matches(request))
        .toList();
    if (matches.isEmpty) return AccessDecision.deniedByDefault;

    final deny = matches
        .where((policy) => policy.effect == PolicyEffect.deny)
        .toList();
    if (deny.isNotEmpty) {
      return AccessDecision(
        allowed: false,
        reason: 'explicit_deny',
        matchedPolicyIds: deny.map((policy) => policy.id).toList(),
      );
    }

    final allow = matches
        .where((policy) => policy.effect == PolicyEffect.allow)
        .toList();
    if (allow.isEmpty) return AccessDecision.deniedByDefault;

    return AccessDecision(
      allowed: true,
      reason: 'policy_allow',
      matchedPolicyIds: allow.map((policy) => policy.id).toList(),
      hiddenFields: {for (final policy in allow) ...policy.hiddenFields},
      readOnlyFields: {for (final policy in allow) ...policy.readOnlyFields},
    );
  }

  void enforce(AccessRequest request) {
    final decision = evaluate(request);
    if (!decision.allowed) {
      throw StateError(
        'تم رفض العملية بواسطة سياسة الوصول: ${decision.reason}',
      );
    }
  }

  Map<String, Object?> filterReadableFields(
    AccessRequest request,
    Map<String, Object?> values,
  ) {
    final decision = evaluate(request);
    if (!decision.allowed) return const {};
    return Map.unmodifiable(
      Map.of(values)
        ..removeWhere((key, _) => decision.hiddenFields.contains(key)),
    );
  }

  Map<String, Object?> filterWritableFields(
    AccessRequest request,
    Map<String, Object?> values,
  ) {
    final decision = evaluate(request);
    if (!decision.allowed) return const {};
    return Map.unmodifiable(
      Map.of(values)..removeWhere(
        (key, _) =>
            decision.hiddenFields.contains(key) ||
            decision.readOnlyFields.contains(key),
      ),
    );
  }
}
