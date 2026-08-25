import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

class KajAdminMetricData {
  const KajAdminMetricData({
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

class KajAdminWorkspace extends StatelessWidget {
  const KajAdminWorkspace({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.metrics = const <KajAdminMetricData>[],
    this.actions = const <Widget>[],
    this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<KajAdminMetricData> metrics;
  final List<Widget> actions;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: <Color>[
                scheme.surfaceContainerHighest.withValues(alpha: .92),
                scheme.surface.withValues(alpha: .98),
              ],
            ),
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusXl),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .7),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: scheme.shadow.withValues(alpha: .08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final heading = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        KajDesignTokens.radiusLg,
                      ),
                    ),
                    child: Icon(icon, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppText(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        AppText(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (compact) ...<Widget>[
                    heading,
                    if (actions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: heading),
                        if (actions.isNotEmpty) ...<Widget>[
                          const SizedBox(width: 16),
                          Wrap(spacing: 8, runSpacing: 8, children: actions),
                        ],
                      ],
                    ),
                  if (metrics.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: metrics
                          .map((metric) => _KajAdminMetric(data: metric))
                          .toList(growable: false),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        if (child != null) ...<Widget>[const SizedBox(height: 14), child!],
      ],
    );
  }
}

class _KajAdminMetric extends StatelessWidget {
  const _KajAdminMetric({required this.data});
  final KajAdminMetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = data.accent ?? scheme.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 245),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: .65),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(data.icon, size: 20, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppText(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  AppText(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KajAdminSection extends StatelessWidget {
  const KajAdminSection({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final String? title;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusXl),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: AppText(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

enum KajAdminStateKind { loading, empty, error, success, locked }

class KajAdminState extends StatelessWidget {
  const KajAdminState({
    super.key,
    required this.kind,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel,
  });
  final KajAdminStateKind kind;
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (kind) {
      KajAdminStateKind.loading => Icons.sync_rounded,
      KajAdminStateKind.empty => Icons.inbox_outlined,
      KajAdminStateKind.error => Icons.error_outline,
      KajAdminStateKind.success => Icons.verified_outlined,
      KajAdminStateKind.locked => Icons.lock_outline,
    };
    final color = kind == KajAdminStateKind.error
        ? scheme.error
        : scheme.primary;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (kind == KajAdminStateKind.loading)
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                Icon(icon, size: 44, color: color),
              const SizedBox(height: 14),
              AppText(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              AppText(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (onAction != null && actionLabel != null) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh),
                  label: AppText(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
