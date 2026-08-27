import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/constants/app_sizes.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_section_header.dart';
import 'package:quality_line_erp/design_system/kaj_v4_components.dart';

import 'app_back_button.dart';
import 'app_card.dart';
import 'app_horizontal_strip.dart';
import 'app_page_lifecycle_scope.dart';
import 'app_window_close_button.dart';

/// Shared V4 responsive layout for ERP list and management pages.
///
/// The page keeps existing module widgets intact while imposing the approved
/// hierarchy: strong identity header, compact command/filter strip, optional
/// metrics, and one framed working surface.
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
    this.toolbarFramed = true,
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
  final bool toolbarFramed;
  final bool mergeHiddenHeaderActionsAndStatistics;

  @override
  Widget build(BuildContext context) {
    final insideModuleWindow = AppWorkspaceWindowScope.maybeOf(context) != null;
    // A workspace window already has its own title/chrome. Rendering another
    // section header inside it creates the duplicated module-top container
    // that is especially noticeable in RTL and narrow layouts.
    final effectiveHideHeader = hideHeader || insideModuleWindow;
    final effectiveActions = <Widget>[
      ...actions,
      if (insideModuleWindow && toolbar == null) const AppWindowCloseButton(),
    ];
    final effectiveToolbar = insideModuleWindow && toolbar != null
        ? AppHorizontalStrip(
            children: <Widget>[toolbar!, const AppWindowCloseButton()],
          )
        : toolbar;
    final effectiveShowBackButton = showBackButton && !insideModuleWindow;

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
                            ...effectiveActions,
                          ],
                        )
                      else if (mergeHiddenHeaderActionsAndStatistics &&
                          (effectiveActions.isNotEmpty || statistics != null))
                        _InlineCommandMetricsRow(
                          actions: effectiveActions,
                          statistics: statistics,
                        )
                      else if (effectiveActions.isNotEmpty)
                        AppHorizontalStrip(children: effectiveActions),
                      if (statistics != null &&
                          (!effectiveHideHeader ||
                              !mergeHiddenHeaderActionsAndStatistics)) ...<
                        Widget
                      >[
                        SizedBox(
                          height: effectiveHideHeader
                              ? KajDesignTokens.space8
                              : KajDesignTokens.space16,
                        ),
                        statistics!,
                      ],
                      if (effectiveToolbar != null) ...<Widget>[
                        SizedBox(
                          height: effectiveHideHeader
                              ? KajDesignTokens.space8
                              : KajDesignTokens.space12,
                        ),
                        if (toolbarFramed)
                          AppCard(
                            padding: const EdgeInsets.all(12),
                            showShadow: false,
                            accent: KajDesignTokens.electricBlue,
                            child: effectiveToolbar,
                          )
                        else
                          effectiveToolbar,
                      ],
                      SizedBox(
                        height: effectiveHideHeader
                            ? KajDesignTokens.space8
                            : KajDesignTokens.space16,
                      ),
                      Expanded(
                        child: KajV4Panel(
                          padding: EdgeInsets.zero,
                          showTopGlow: true,
                          child: ClipRect(child: body),
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

/// Keeps page commands and KPI explanation boxes on one horizontal line.
///
/// The row scrolls instead of wrapping. This is important for dense ERP
/// workspaces where a second command line is easily mistaken for a different
/// workflow stage.
class _InlineCommandMetricsRow extends StatelessWidget {
  const _InlineCommandMetricsRow({
    required this.actions,
    required this.statistics,
  });

  final List<Widget> actions;
  final Widget? statistics;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[...actions, ?statistics];
    return AppHorizontalStrip(
      spacing: KajDesignTokens.space8,
      children: children,
    );
  }
}
