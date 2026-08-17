import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Compact, horizontally scrollable module selector shared across ERP screens.
///
/// The bar deliberately owns its complete vertical extent so it can be placed
/// inside AppBar.bottom, page toolbars, and full-screen workspaces without
/// RenderFlex overflow at 100% browser zoom.
class AppPillTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AppPillTabBar({
    super.key,
    required this.tabs,
    this.padding = const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
    this.controller,
  });

  final List<AppPillTab> tabs;
  final EdgeInsetsGeometry padding;
  final TabController? controller;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effectiveController =
        controller ?? DefaultTabController.maybeOf(context);

    if (tabs.isEmpty ||
        effectiveController == null ||
        effectiveController.length != tabs.length) {
      return Padding(
        padding: padding,
        child: SizedBox(
          height: 36,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs
                  .map(
                    (tab) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: _StaticPill(tab: tab),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          height: 36,
          child: TabBar(
            controller: effectiveController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 1,
              vertical: 2,
            ),
            indicator: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  KajDesignTokens.electricBlue.withValues(alpha: .24),
                  KajDesignTokens.electricBlue.withValues(alpha: .09),
                ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: KajDesignTokens.electricBlue.withValues(alpha: .52),
              ),
            ),
            indicatorWeight: 1,
            labelColor: dark ? Colors.white : scheme.onSurface,
            unselectedLabelColor: scheme.onSurfaceVariant,
            labelPadding: const EdgeInsetsDirectional.only(end: 5),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            tabs: tabs
                .map(
                  (tab) => Tab(
                    height: 32,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: dark ? .18 : .34,
                        ),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .42),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(tab.icon, size: 16),
                          const SizedBox(width: 7),
                          AppText(
                            tab.label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 11.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class AppPillTab {
  const AppPillTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _StaticPill extends StatelessWidget {
  const _StaticPill({required this.tab});

  final AppPillTab tab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: scheme.surfaceContainerHighest.withValues(alpha: .34),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(tab.icon, size: 16),
          const SizedBox(width: 7),
          AppText(
            tab.label,
            maxLines: 1,
            style: const TextStyle(fontSize: 11.2, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
