import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

/// Unified luxury shell for sales, purchases, invoices, payments and approvals.
class KajCommercialWorkspace extends StatelessWidget {
  const KajCommercialWorkspace({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.actions = const <Widget>[],
    this.metrics = const <KajCommercialWorkspaceMetric>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final List<Widget> actions;
  final List<KajCommercialWorkspaceMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KajShellSurface(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              final heading = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
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
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        AppText(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    heading,
                    if (actions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      Wrap(spacing: 10, runSpacing: 10, children: actions),
                    ],
                    if (metrics.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: metrics
                            .map((e) => _MetricTile(data: e))
                            .toList(),
                      ),
                    ],
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: heading),
                      if (actions.isNotEmpty)
                        Wrap(spacing: 10, children: actions),
                    ],
                  ),
                  if (metrics.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: metrics
                          .map((e) => _MetricTile(data: e))
                          .toList(),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Expanded(child: child),
      ],
    );
  }
}

class KajCommercialWorkspaceMetric {
  const KajCommercialWorkspaceMetric({
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});
  final KajCommercialWorkspaceMetric data;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = data.accent ?? scheme.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(data.icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppText(
                data.value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              AppText(
                data.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class KajCommercialDocumentHeader extends StatelessWidget {
  const KajCommercialDocumentHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.description_outlined,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return KajShellSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                AppText(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class KajCommercialSection extends StatelessWidget {
  const KajCommercialSection({
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
    return KajShellSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 21),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppText(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    // Explicit control flow keeps this compatible with the project's
                    // current Flutter/Dart collection-element syntax.
                    // ignore: use_null_aware_elements
                    if (subtitle != null)
                      AppText(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              // ignore: use_null_aware_elements
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class KajCommercialWorkflowRibbon extends StatelessWidget {
  const KajCommercialWorkflowRibbon({
    super.key,
    required this.steps,
    required this.activeIndex,
  });
  final List<String> steps;
  final int activeIndex;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(steps.length, (index) {
          final active = index <= activeIndex;
          return Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: active ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      active
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 17,
                      color: active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    AppText(
                      steps[index],
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (index != steps.length - 1)
                Container(width: 22, height: 1, color: scheme.outlineVariant),
            ],
          );
        }),
      ),
    );
  }
}

class KajCommercialLoadingState extends StatelessWidget {
  const KajCommercialLoadingState({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => KajSystemState(
    icon: Icons.sync_rounded,
    title: label ?? AppTranslation.translate('جارٍ تحميل العمليات التجارية'),
    message: AppTranslation.translate(
      'يتم الآن مزامنة الأوامر والفواتير والدفعات.',
    ),
    tone: Theme.of(context).colorScheme.primary,
    action: const SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2.4),
    ),
  );
}

class KajCommercialEmptyState extends StatelessWidget {
  const KajCommercialEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => KajSystemState(
    icon: Icons.receipt_long_outlined,
    title: title,
    message: message,
    tone: Theme.of(context).colorScheme.onSurfaceVariant,
    action: actionLabel != null && onAction != null
        ? KajPrimaryAction(label: actionLabel!, onPressed: onAction)
        : null,
  );
}
