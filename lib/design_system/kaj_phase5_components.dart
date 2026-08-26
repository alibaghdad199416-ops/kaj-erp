import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_brand_motif.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

/// Shared visual primitives for the Phase 5 commercial experience.
///
/// These widgets are intentionally presentation-only. Sales and purchasing
/// controllers remain the source of truth for business state and permissions.
class KajCommercialHero extends StatelessWidget {
  const KajCommercialHero({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metrics,
    this.actions = const <Widget>[],
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<KajCommercialMetricData> metrics;
  final List<Widget> actions;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final effectiveAccent = accent ?? KajDesignTokens.champagneGold;

    return KajSurface(
      radius: KajDesignTokens.radiusLg,
      padding: EdgeInsets.zero,
      accent: effectiveAccent,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            end: -30,
            top: -40,
            bottom: -40,
            width: 380,
            child: Opacity(
              opacity: dark ? .11 : .065,
              child: const KajBrandMotif(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KajDesignTokens.space20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Four metrics plus heading/actions need more width than the
                // previous breakpoint guaranteed. Stack below 1180px to
                // prevent narrow desktop/tablet overflow.
                final compact = constraints.maxWidth < 1180;
                final heading = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: effectiveAccent.withValues(
                          alpha: dark ? .18 : .1,
                        ),
                        borderRadius: BorderRadius.circular(
                          KajDesignTokens.radiusMd,
                        ),
                        border: Border.all(
                          color: effectiveAccent.withValues(alpha: .45),
                        ),
                      ),
                      child: Icon(icon, color: effectiveAccent, size: 30),
                    ),
                    const SizedBox(width: KajDesignTokens.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            AppTranslation.translate('العمليات التجارية'),
                            style: TextStyle(
                              color: effectiveAccent,
                              fontSize: 10,
                              letterSpacing: 1.25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space6),
                          AppText(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: compact ? 23 : 29,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space8),
                          AppText(
                            subtitle,
                            maxLines: compact ? 4 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final metricsWidget = Wrap(
                  spacing: KajDesignTokens.space8,
                  runSpacing: KajDesignTokens.space8,
                  children: metrics
                      .map((metric) => KajCommercialMetric(data: metric))
                      .toList(growable: false),
                );

                final actionsWidget = actions.isEmpty
                    ? null
                    : Wrap(spacing: 8, runSpacing: 8, children: actions);

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      heading,
                      const SizedBox(height: KajDesignTokens.space16),
                      metricsWidget,
                      if (actionsWidget != null) ...<Widget>[
                        const SizedBox(height: KajDesignTokens.space12),
                        actionsWidget,
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 4, child: heading),
                    const SizedBox(width: KajDesignTokens.space20),
                    Expanded(flex: 5, child: metricsWidget),
                    if (actionsWidget != null) ...<Widget>[
                      const SizedBox(width: KajDesignTokens.space16),
                      Flexible(child: actionsWidget),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class KajCommercialMetricData {
  const KajCommercialMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
}

class KajCommercialMetric extends StatelessWidget {
  const KajCommercialMetric({super.key, required this.data});

  final KajCommercialMetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 152, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: data.accent.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
        border: Border.all(color: data.accent.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(data.icon, color: data.accent, size: 19),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  data.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KajCommercialWorkflow extends StatelessWidget {
  const KajCommercialWorkflow({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.accent,
  });

  final List<String> steps;
  final int currentIndex;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? KajDesignTokens.electricBlue;
    final safeIndex = steps.isEmpty
        ? -1
        : currentIndex.clamp(0, steps.length - 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(steps.length, (index) {
          final reached = index <= safeIndex;
          return Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: reached
                      ? effectiveAccent.withValues(alpha: .12)
                      : scheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: reached
                        ? effectiveAccent.withValues(alpha: .48)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      reached
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: reached
                          ? effectiveAccent
                          : scheme.onSurfaceVariant,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    AppText(
                      steps[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: reached
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: reached ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                Container(
                  width: 28,
                  height: 1,
                  color: reached
                      ? effectiveAccent.withValues(alpha: .6)
                      : scheme.outlineVariant,
                ),
            ],
          );
        }),
      ),
    );
  }
}
