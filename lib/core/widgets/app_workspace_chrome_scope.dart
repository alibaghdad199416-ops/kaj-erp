import 'package:flutter/widgets.dart';

/// Describes which application-shell chrome already owns the current module.
///
/// Desktop side-navigation layouts render the `AppWorkspaceTopBar` above the
/// business canvas. Descendants can use this scope to avoid rendering a second
/// module title/header while keeping compact/mobile layouts self-describing.
class AppWorkspaceChromeScope extends InheritedWidget {
  const AppWorkspaceChromeScope({
    super.key,
    required this.hasWorkspaceTopBar,
    required super.child,
  });

  final bool hasWorkspaceTopBar;

  static AppWorkspaceChromeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppWorkspaceChromeScope>();

  static bool hasTopBarOf(BuildContext context) =>
      maybeOf(context)?.hasWorkspaceTopBar ?? false;

  @override
  bool updateShouldNotify(AppWorkspaceChromeScope oldWidget) =>
      hasWorkspaceTopBar != oldWidget.hasWorkspaceTopBar;
}
