import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_chrome_scope.dart';
import 'package:quality_line_erp/design_system/kaj_brand_motif.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

/// Shared visual primitives for the final Phase 6 finance and administration experience.
class KajExecutiveHero extends StatelessWidget {
  const KajExecutiveHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metrics,
    this.accent,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<KajExecutiveMetricData> metrics;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    if (AppWorkspaceChromeScope.hasTopBarOf(context)) {
      if (metrics.isEmpty) return const SizedBox.shrink();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0) const SizedBox(width: KajDesignTokens.space8),
              KajExecutiveMetric(data: metrics[index]),
            ],
          ],
        ),
      );
    }

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
            end: -40,
            top: -60,
            bottom: -60,
            width: 430,
            child: Opacity(
              opacity: dark ? .12 : .055,
              child: const KajBrandMotif(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KajDesignTokens.space20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
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
                            eyebrow,
                            style: TextStyle(
                              color: effectiveAccent,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space6),
                          AppText(
                            title,
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
                final metricWrap = Wrap(
                  spacing: KajDesignTokens.space8,
                  runSpacing: KajDesignTokens.space8,
                  children: metrics
                      .map((item) => KajExecutiveMetric(data: item))
                      .toList(growable: false),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      heading,
                      const SizedBox(height: KajDesignTokens.space16),
                      metricWrap,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(flex: 4, child: heading),
                    const SizedBox(width: KajDesignTokens.space20),
                    Expanded(flex: 5, child: metricWrap),
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

class KajExecutiveMetricData {
  const KajExecutiveMetricData({
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

class KajExecutiveMetric extends StatelessWidget {
  const KajExecutiveMetric({super.key, required this.data});
  final KajExecutiveMetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 158),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppText(
                data.label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              AppText(
                data.value,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Consistent framed surface for finance and administration submodules.
class KajExecutiveSectionFrame extends StatelessWidget {
  const KajExecutiveSectionFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveAccent = accent ?? KajDesignTokens.electricBlue;
    return KajSurface(
      radius: KajDesignTokens.radiusLg,
      padding: EdgeInsets.zero,
      accent: effectiveAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(KajDesignTokens.space16),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: effectiveAccent.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(
                      KajDesignTokens.radiusSm,
                    ),
                    border: Border.all(
                      color: effectiveAccent.withValues(alpha: .28),
                    ),
                  ),
                  child: Icon(icon, color: effectiveAccent, size: 22),
                ),
                const SizedBox(width: KajDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AppText(
                        title,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        subtitle,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                // ignore: use_null_aware_elements
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
          child,
        ],
      ),
    );
  }
}

class KajExecutiveStatusBadge extends StatelessWidget {
  const KajExecutiveStatusBadge({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
  });
  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
      border: Border.all(color: accent.withValues(alpha: .30)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: accent),
        const SizedBox(width: 6),
        AppText(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
