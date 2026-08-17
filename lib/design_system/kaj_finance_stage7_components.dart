import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
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
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 18),
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
    final insideOperationalWorkspace =
        AppWorkspaceWindowScope.maybeOf(context) != null;

    if (insideOperationalWorkspace) {
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (actions.isNotEmpty || metrics.isNotEmpty) ...<Widget>[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ...actions,
                    ...metrics.map((item) => _KajFinanceMetric(data: item)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(child: child),
          ],
        ),
      );
    }

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
            emphasized: true,
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: KajDesignTokens.champagneGold.withValues(
                          alpha: .12,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: KajDesignTokens.champagneGold.withValues(
                            alpha: .28,
                          ),
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 21,
                        color: KajDesignTokens.champagneGold,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            eyebrow.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: KajDesignTokens.champagneGold,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .75,
                            ),
                          ),
                          const SizedBox(height: 3),
                          AppText(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          AppText(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.4,
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
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: identity),
                    const SizedBox(width: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                );
              },
            ),
          ),
          if (metrics.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1180
                    ? 4
                    : width >= 720
                    ? 2
                    : 1;
                final itemWidth = (width - ((columns - 1) * 10)) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
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
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: accent, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(data.label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                AppText(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 19, color: KajDesignTokens.champagneGold),
                  const SizedBox(width: 9),
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
                        const SizedBox(height: 2),
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
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: .45)),
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
