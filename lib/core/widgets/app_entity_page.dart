import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/constants/app_sizes.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_section_header.dart';

import 'app_back_button.dart';
import 'app_horizontal_strip.dart';
import 'app_page_lifecycle_scope.dart';
import 'app_window_close_button.dart';
import 'app_workspace_chrome_scope.dart';

/// Shared ERP workspace layout.
///
/// The page keeps one continuous business canvas. Headerless embedded modules
/// deliberately use tighter edge spacing so tabs, filters and business content
/// remain visually connected instead of appearing as separate stacked boxes.
/// When the `AppModuleShell` already renders its desktop workspace top bar,
/// this page automatically suppresses the duplicate section title and keeps
/// actions, statistics and filters in the connected command canvas below it.
class AppEntityPage extends StatelessWidget {
  const AppEntityPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.statistics,
    this.toolbar,
    this.sidebar,
    this.showBackButton = true,
    this.maxWidth = 1600,
    this.bodyPadding,
    this.hideHeader = false,
    this.toolbarFramed = false,
    this.mergeHiddenHeaderActionsAndStatistics = true,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? statistics;
  final Widget? toolbar;
  final Widget? sidebar;
  final bool showBackButton;
  final double maxWidth;
  final EdgeInsetsGeometry? bodyPadding;
  final bool hideHeader;

  /// Kept for source compatibility. Toolbars are intentionally no longer put
  /// in their own card; the module is one continuous workspace.
  final bool toolbarFramed;
  final bool mergeHiddenHeaderActionsAndStatistics;

  @override
  Widget build(BuildContext context) {
    final insideModuleWindow = AppWorkspaceWindowScope.maybeOf(context) != null;
    final shellHasWorkspaceTopBar = AppWorkspaceChromeScope.hasTopBarOf(context);
    final effectiveHideHeader =
        hideHeader || (shellHasWorkspaceTopBar && !insideModuleWindow);
    final effectiveShowBackButton = showBackButton && !insideModuleWindow;
    final effectiveToolbar = toolbar;
    final railChildren = <Widget>[
      ...actions,
      ?statistics,
      if (insideModuleWindow && !effectiveHideHeader)
        const AppWindowCloseButton(),
    ];

    final content = SafeArea(
      top: false,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final horizontal = compact
                    ? AppSizes.compactScreenPadding
                    : 16.0;
                final padding =
                    bodyPadding ??
                    EdgeInsetsDirectional.fromSTEB(
                      horizontal,
                      effectiveHideHeader ? 4 : 14,
                      horizontal,
                      compact ? 12 : 16,
                    );

                final chrome = <Widget>[
                  if (!effectiveHideHeader)
                    KajSectionHeader(
                      title: title,
                      subtitle: subtitle,
                      compact: compact,
                      icon: leading == null && !effectiveShowBackButton
                          ? Icons.grid_view_rounded
                          : null,
                      actions: <Widget>[
                        if (leading != null || effectiveShowBackButton)
                          leading ?? const AppBackButton(),
                      ],
                    ),
                  if (railChildren.isNotEmpty) ...<Widget>[
                    SizedBox(
                      height: effectiveHideHeader
                          ? KajDesignTokens.space4
                          : KajDesignTokens.space10,
                    ),
                    AppHorizontalStrip(
                      key: const ValueKey('module-command-rail'),
                      spacing: KajDesignTokens.space8,
                      children: railChildren,
                    ),
                  ],
                  if (effectiveToolbar != null) ...<Widget>[
                    SizedBox(
                      height: effectiveHideHeader
                          ? KajDesignTokens.space8
                          : KajDesignTokens.space10,
                    ),
                    KeyedSubtree(
                      key: const ValueKey('module-bounded-toolbar'),
                      child: effectiveToolbar,
                    ),
                  ],
                ];

                final bodySpacing = SizedBox(
                  height: chrome.isEmpty
                      ? 0
                      : effectiveHideHeader
                      ? KajDesignTokens.space8
                      : KajDesignTokens.space10,
                );

                final bodyPanel = ClipRect(
                  key: const ValueKey('module-continuous-workspace'),
                  child: body,
                );

                final shortHeight = constraints.maxHeight < 680;

                return Padding(
                  padding: padding,
                  child: shortHeight
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (chrome.isNotEmpty)
                              Flexible(
                                flex: 2,
                                fit: FlexFit.loose,
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'app-entity-page-short-height-scroll',
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: chrome,
                                  ),
                                ),
                              ),
                            if (chrome.isNotEmpty) bodySpacing,
                            Expanded(flex: 3, child: bodyPanel),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ...chrome,
                            if (chrome.isNotEmpty) bodySpacing,
                            Expanded(child: bodyPanel),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );

    if (sidebar == null) return content;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) return content;
        return Row(
          children: <Widget>[
            sidebar!,
            Expanded(child: content),
          ],
        );
      },
    );
  }
}
