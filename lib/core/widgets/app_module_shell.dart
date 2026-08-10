import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

import 'app_top_navigation.dart';
import 'app_workspace_top_bar.dart';

/// V4 application shell.
///
/// The approved design always keeps the global navigation visually separate
/// from the working canvas. On desktop the side rail and compact workspace bar
/// are visible together; on narrow screens the original top navigation remains
/// available. Module pages still own their business content and workflows.
class AppModuleShell extends StatelessWidget {
  const AppModuleShell({super.key, required this.route, required this.child});

  final String route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final moduleContent = PopScope<dynamic>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !context.mounted) return;
        await Navigator.of(context).maybePop();
      },
      child: _RuntimeAwareModuleContent(route: route, child: child),
    );

    final usesSideNavigation = context.select<AppPreferencesController, bool>(
      (preferences) => preferences.usesSideNavigation,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final compact = viewport.maxWidth < 840;
            if (!usesSideNavigation || compact) {
              return Column(
                children: <Widget>[
                  AppTopNavigation(currentRoute: route),
                  Expanded(child: _WorkspaceCanvas(child: moduleContent)),
                ],
              );
            }

            return Row(
              children: <Widget>[
                AppSideNavigation(
                  key: const ValueKey('app-side-navigation'),
                  currentRoute: route,
                  forceCollapsed: viewport.maxWidth < 1040,
                ),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      AppWorkspaceTopBar(currentRoute: route),
                      Expanded(child: _WorkspaceCanvas(child: moduleContent)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RuntimeAwareModuleContent extends StatelessWidget {
  const _RuntimeAwareModuleContent({required this.route, required this.child});

  final String route;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(route), child: child);
}

class _WorkspaceCanvas extends StatelessWidget {
  const _WorkspaceCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12),
      child: KajShellSurface(
        padding: EdgeInsets.zero,
        radius: KajDesignTokens.radiusLg,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
          child: ColoredBox(
            color: KajDesignTokens.workspace(brightness),
            child: child,
          ),
        ),
      ),
    );
  }
}
