import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class PermissionAction {
  const PermissionAction._();

  static bool allowed(BuildContext context, String permission) {
    return context.read<AccessController>().hasPermission(permission);
  }

  static Future<bool> require(
    BuildContext context,
    String permission, {
    String? message,
  }) async {
    final access = context.read<AccessController>();
    if (access.hasPermission(permission)) {
      return true;
    }

    await access.recordDeniedAccess(permission);
    if (!context.mounted) {
      return false;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: AppText(message ?? 'ليس لديك صلاحية لتنفيذ هذه العملية.'),
          backgroundColor: Colors.red,
        ),
      );
    return false;
  }
}

class PermissionVisibility extends StatelessWidget {
  const PermissionVisibility({
    super.key,
    required this.permission,
    required this.child,
    this.replacement = const SizedBox.shrink(),
  });

  final String permission;
  final Widget child;
  final Widget replacement;

  @override
  Widget build(BuildContext context) {
    final allowed = context.select<AccessController, bool>(
      (controller) => controller.hasPermission(permission),
    );
    return allowed ? child : replacement;
  }
}

/// Applies optional per-field visibility/edit permissions on top of the
/// existing module/action permissions. When granular restriction is not enabled
/// for [resource], behavior is identical to the legacy UI.
class FieldPermissionControl extends StatelessWidget {
  const FieldPermissionControl({
    super.key,
    required this.resource,
    required this.field,
    required this.child,
    this.viewPermission,
    this.writePermission,
    this.replacement = const SizedBox.shrink(),
    this.readOnlyOpacity = 0.68,
  });

  final String resource;
  final String field;
  final String? viewPermission;
  final String? writePermission;
  final Widget child;
  final Widget replacement;
  final double readOnlyOpacity;

  @override
  Widget build(BuildContext context) {
    final state = context.select<AccessController, (bool, bool)>((controller) {
      final visible = controller.canViewField(
        resource,
        field,
        viewPermission: viewPermission,
      );
      final editable = controller.canEditField(
        resource,
        field,
        viewPermission: viewPermission,
        writePermission: writePermission,
      );
      return (visible, editable);
    });
    if (!state.$1) return replacement;
    if (state.$2) return child;
    return ExcludeFocus(
      child: AbsorbPointer(
        child: Opacity(opacity: readOnlyOpacity, child: child),
      ),
    );
  }
}

/// Visibility-only counterpart for values/cards/reports that are not editable.
class FieldPermissionVisibility extends StatelessWidget {
  const FieldPermissionVisibility({
    super.key,
    required this.resource,
    required this.field,
    required this.child,
    this.viewPermission,
    this.replacement = const SizedBox.shrink(),
  });

  final String resource;
  final String field;
  final String? viewPermission;
  final Widget child;
  final Widget replacement;

  @override
  Widget build(BuildContext context) {
    final visible = context.select<AccessController, bool>(
      (controller) => controller.canViewField(
        resource,
        field,
        viewPermission: viewPermission,
      ),
    );
    return visible ? child : replacement;
  }
}
