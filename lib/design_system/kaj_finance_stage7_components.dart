import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

class KajFinanceMetricData {
  const KajFinanceMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
}

class KajFinanceWorkspace extends StatelessWidget {
  const KajFinanceWorkspace({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.metrics = const <KajFinanceMetricData>[],
    this.actions = const <Widget>[],
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 24),
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final List<KajFinanceMetricData> metrics;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[scheme.surface, scheme.surfaceContainerLowest],
        ),
      ),
      child: ListView(
        padding: padding,
        children: <Widget>[
          KajShellSurface(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: KajDesignTokens.champagneGold.withValues(
                          alpha: .14,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: KajDesignTokens.champagneGold.withValues(
                            alpha: .36,
                          ),
                        ),
                      ),
                      child: Icon(icon, color: KajDesignTokens.champagneGold),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            eyebrow.toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: KajDesignTokens.champagneGold,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AppText(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AppText(
                            subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                if (compact || actions.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      identity,
                      if (actions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        Wrap(spacing: 10, runSpacing: 10, children: actions),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: identity),
                    const SizedBox(width: 18),
                    Wrap(spacing: 10, runSpacing: 10, children: actions),
                  ],
                );
              },
            ),
          ),
          if (metrics.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1180
                    ? 4
                    : width >= 720
                    ? 2
                    : 1;
                final itemWidth = (width - ((columns - 1) * 12)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: metrics
                      .map(
                        (metric) => SizedBox(
                          width: itemWidth,
                          child: _KajFinanceMetric(data: metric),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _KajFinanceMetric extends StatelessWidget {
  const _KajFinanceMetric({required this.data});
  final KajFinanceMetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = data.accent ?? theme.colorScheme.primary;
    return KajShellSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(data.icon, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(data.label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 3),
                AppText(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
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

class KajFinanceSection extends StatelessWidget {
  const KajFinanceSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KajShellSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20, color: KajDesignTokens.champagneGold),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AppText(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 3),
                        AppText(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // ignore: use_null_aware_elements
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: .5)),
          child,
        ],
      ),
    );
  }
}

class KajFinanceState extends StatelessWidget {
  const KajFinanceState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return KajSystemState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}
