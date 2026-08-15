import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/constants/app_sizes.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_section_header.dart';

import 'app_back_button.dart';
import 'app_horizontal_strip.dart';
import 'app_page_lifecycle_scope.dart';
import 'app_window_close_button.dart';

/// Shared ERP workspace layout.
///
/// Only the module identity header is framed. Statistics, commands and filters
/// occupy one horizontal command rail and the business body is a continuous,
/// unboxed workspace. This removes the nested "rectangle inside rectangle"
/// appearance while keeping dense controls usable through horizontal scrolling.
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
    final effectiveShowBackButton = showBackButton && !insideModuleWindow;
    final railChildren = <Widget>[
      ...actions,
      ?statistics,
      ?toolbar,
      if (insideModuleWindow) const AppWindowCloseButton(),
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
                final padding =
                    bodyPadding ??
                    EdgeInsets.all(
                      compact
                          ? AppSizes.compactScreenPadding
                          : AppSizes.screenPadding,
                    );
                return Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!hideHeader)
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
                          height: hideHeader
                              ? KajDesignTokens.space8
                              : KajDesignTokens.space12,
                        ),
                        AppHorizontalStrip(
                          key: const ValueKey('module-command-rail'),
                          spacing: KajDesignTokens.space8,
                          children: railChildren,
                        ),
                      ],
                      SizedBox(
                        height: railChildren.isEmpty && hideHeader
                            ? 0
                            : KajDesignTokens.space12,
                      ),
                      Expanded(
                        child: ClipRect(
                          key: const ValueKey('module-continuous-workspace'),
                          child: body,
                        ),
                      ),
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
        return Row(children: <Widget>[sidebar!, Expanded(child: content)]);
      },
    );
  }
}
