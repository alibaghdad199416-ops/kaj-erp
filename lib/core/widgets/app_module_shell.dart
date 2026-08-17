import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

import 'app_top_navigation.dart';
import 'app_top_profile_action.dart';
import 'app_workspace_top_bar.dart';

/// Application shell with a single continuous module workspace.
///
/// Only the upper module/navigation bar owns framed shell chrome. The business
/// area stays borderless and uses a restrained gutter so desktop screens can
/// use their full width at 100% browser zoom.
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
                  Row(
                    children: <Widget>[
                      Expanded(child: AppTopNavigation(currentRoute: route)),
                      const AppTopProfileAction(),
                    ],
                  ),
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
    return ColoredBox(
      color: KajDesignTokens.workspace(brightness),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 10),
        child: child,
      ),
    );
  }
}
