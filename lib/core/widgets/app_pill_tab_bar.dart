import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// V4 pill-only module selector used by inventory, partners, sales and
/// purchases.
///
/// There is deliberately no surrounding segmented-control rectangle and no
/// underline. Every module is represented by one independent oval button so
/// the navigation remains light, even and horizontally scrollable.
class AppPillTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AppPillTabBar({
    super.key,
    required this.tabs,
    this.padding = const EdgeInsetsDirectional.fromSTEB(12, 7, 12, 7),
    this.controller,
  });

  final List<AppPillTab> tabs;
  final EdgeInsetsGeometry padding;
  final TabController? controller;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effectiveController =
        controller ?? DefaultTabController.maybeOf(context);

    // Never let TabBar attach to a missing or unrelated inherited controller.
    // In release web builds Flutter's internal _TabBarState can otherwise reach
    // a nullable selected index and throw `Null check operator used on a null value`.
    if (tabs.isEmpty ||
        effectiveController == null ||
        effectiveController.length != tabs.length) {
      return Padding(
        padding: padding,
        child: SizedBox(
          height: 40,
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
          height: 40,
          child: TabBar(
            controller: effectiveController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 3,
            ),
            indicator: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  KajDesignTokens.electricBlue.withValues(alpha: .30),
                  KajDesignTokens.electricBlue.withValues(alpha: .12),
                ],
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: KajDesignTokens.electricBlue.withValues(alpha: .58),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: KajDesignTokens.electricBlue.withValues(alpha: .10),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            indicatorWeight: 0,
            labelColor: dark ? Colors.white : scheme.onSurface,
            unselectedLabelColor: scheme.onSurfaceVariant,
            labelPadding: const EdgeInsetsDirectional.only(end: 6),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            tabs: tabs
                .map(
                  (tab) => Tab(
                    height: 34,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: dark ? .20 : .38,
                        ),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .46),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(tab.icon, size: 15),
                          const SizedBox(width: 7),
                          AppText(
                            tab.label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 9.8,
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
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: scheme.surfaceContainerHighest.withValues(alpha: .38),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .46)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(tab.icon, size: 15),
          const SizedBox(width: 7),
          AppText(
            tab.label,
            maxLines: 1,
            style: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
