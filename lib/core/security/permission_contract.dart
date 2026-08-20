/// Canonical permission-code grammar shared by UI policy checks, record scope,
/// field permissions and future PostgreSQL enforcement.
///
/// The current installation is intentionally transitional: granular actions and
/// fields are opt-in, while record scope falls back to company-wide visibility
/// until an explicit scope is assigned. Keeping that compatibility behavior in
/// one contract prevents Flutter and PostgreSQL permission semantics from
/// drifting while R95+ migrates modules to stricter resource/action policies.
enum RecordScopeMode { own, all, legacyAll }

abstract final class PermissionContract {
  static String action(String resource, String action) {
    final resourceKey = _segment(resource, argument: 'resource');
    final actionPath = _path(action, argument: 'action');
    return '$resourceKey.$actionPath';
  }

  static String actionRestriction(String resource) =>
      action(resource, 'actions.restrict');

  static String recordScopeOwn(String resource) =>
      action(resource, 'records.own');

  static String recordScopeAll(String resource) =>
      action(resource, 'records.all');

  static String fieldRestriction(String resource) =>
      action(resource, 'fields.restrict');

  static String fieldView(String resource, String field) =>
      action(resource, 'fields.${_segment(field, argument: 'field')}.view');

  static String fieldEdit(String resource, String field) =>
      action(resource, 'fields.${_segment(field, argument: 'field')}.edit');

  static bool hasRestrictedActions(
    Set<String> permissionCodes,
    String resource,
  ) {
    return permissionCodes.contains(actionRestriction(resource));
  }

  /// Preserves the Phase 11 migration contract: broad legacy permission first,
  /// then explicit granular action permission once action restrictions are on.
  static bool canPerformAction(
    Set<String> permissionCodes, {
    required String resource,
    required String actionName,
    required String legacyPermission,
  }) {
    if (!permissionCodes.contains(legacyPermission)) return false;
    if (!hasRestrictedActions(permissionCodes, resource)) return true;
    return permissionCodes.contains(action(resource, actionName));
  }

  /// Mirrors PostgreSQL R84 record-scope precedence exactly.
  ///
  /// `records.all` wins when both permissions exist, then `records.own`.
  /// Absence of either remains a deliberate legacy company-wide fallback until
  /// R95+ explicitly closes the migration for that subject/module.
  static RecordScopeMode resolveRecordScope(
    Set<String> permissionCodes,
    String resource,
  ) {
    if (permissionCodes.contains(recordScopeAll(resource))) {
      return RecordScopeMode.all;
    }
    if (permissionCodes.contains(recordScopeOwn(resource))) {
      return RecordScopeMode.own;
    }
    return RecordScopeMode.legacyAll;
  }

  static String _path(String value, {required String argument}) {
    final parts = value.trim().split('.');
    if (parts.isEmpty) {
      throw ArgumentError.value(value, argument, 'must not be empty');
    }
    return parts
        .map((part) => _segment(part, argument: argument))
        .join('.');
  }

  static String _segment(String value, {required String argument}) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.contains('.') ||
        RegExp(r'\s').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        argument,
        'must be one non-empty permission segment without dots or whitespace',
      );
    }
    return normalized;
  }
}
