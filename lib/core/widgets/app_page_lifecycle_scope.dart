import 'package:flutter/material.dart';

/// Compatibility lifecycle scope for forms that historically lived inside
/// floating workspace windows.
///
/// Runtime modules now open as transient resizable module windows. The legacy
/// class name remains so existing forms can keep using [markDirty], [requestCloseCurrent]
/// and [closeCurrent] without importing or rendering any window/taskbar UI.
class AppWorkspaceWindowScope extends InheritedWidget {
  const AppWorkspaceWindowScope({
    super.key,
    required this.windowId,
    required this.title,
    required this.close,
    required this.requestClose,
    required this.setDirty,
    required this.isDirty,
    required super.child,
    this.minimize = _noop,
    this.toggleMaximize = _noop,
  });

  final int windowId;
  final String title;
  final void Function([dynamic result]) close;
  final Future<bool> Function() requestClose;
  final ValueChanged<bool> setDirty;
  final bool isDirty;

  /// Retained for source compatibility and mapped to resize/maximize controls.
  final VoidCallback minimize;
  final VoidCallback toggleMaximize;

  static void _noop() {}

  static AppWorkspaceWindowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppWorkspaceWindowScope>();

  static void markDirty(BuildContext context, [bool dirty = true]) {
    maybeOf(context)?.setDirty(dirty);
  }

  static Future<bool> requestCloseCurrent(BuildContext context) async {
    final scope = maybeOf(context);
    if (scope != null) return scope.requestClose();
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return true;
    }
    return false;
  }

  static void closeCurrent(BuildContext context, [dynamic result]) {
    final scope = maybeOf(context);
    if (scope != null) {
      scope.close(result);
      return;
    }
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop(result);
    }
  }

  @override
  bool updateShouldNotify(AppWorkspaceWindowScope oldWidget) =>
      oldWidget.windowId != windowId ||
      oldWidget.title != title ||
      oldWidget.isDirty != isDirty;
}
