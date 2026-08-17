import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

/// Shared premium surfaces for maintenance, partners and CRM.
class KajRelationshipHero extends StatelessWidget {
  const KajRelationshipHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.primaryAction,
    this.secondaryAction,
    this.trailing,
    this.metrics = const <Widget>[],
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final Widget? trailing;
  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return KajShellSurface(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      KajDesignTokens.champagne.withValues(alpha: .90),
                      scheme.primary.withValues(alpha: .84),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      eyebrow.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.05,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppText(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: compact ? 19 : 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 10),
                          trailing!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    AppText(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.6,
                        color: scheme.onSurfaceVariant,
                        height: 1.42,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (secondaryAction != null) secondaryAction!,
              if (primaryAction != null) primaryAction!,
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                identity,
                if (primaryAction != null || secondaryAction != null) ...[
                  const SizedBox(height: 14),
                  actions,
                ],
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    if (primaryAction != null || secondaryAction != null) ...[
                      const SizedBox(width: 16),
                      actions,
                    ],
                  ],
                ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: metrics),
              ],
            ],
          );
        },
      ),
    );
  }
}

class KajRelationshipSection extends StatelessWidget {
  const KajRelationshipSection({
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
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KajShellSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
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
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class KajRelationshipState extends StatelessWidget {
  const KajRelationshipState.loading({super.key, required this.label})
    : icon = Icons.sync_rounded,
      message = null,
      action = null,
      loading = true;

  const KajRelationshipState.empty({
    super.key,
    required this.label,
    this.message,
    this.action,
  }) : icon = Icons.auto_awesome_mosaic_outlined,
       loading = false;

  const KajRelationshipState.error({
    super.key,
    required this.label,
    this.message,
    this.action,
  }) : icon = Icons.error_outline_rounded,
       loading = false;

  final String label;
  final String? message;
  final Widget? action;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: KajShellSurface(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 13),
              Flexible(child: AppText(label)),
            ],
          ),
        ),
      );
    }
    return KajSystemState(
      icon: icon,
      title: label,
      message: message ?? '',
      action: action,
    );
  }
}

class KajWorkflowRibbon extends StatelessWidget {
  const KajWorkflowRibbon({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  final List<String> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(steps.length, (index) {
          final active = index <= currentIndex;
          return Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: active
                        ? scheme.primary.withValues(alpha: .34)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    AppText(
                      steps[index],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                Container(width: 20, height: 1, color: scheme.outlineVariant),
            ],
          );
        }),
      ),
    );
  }
}

extension KajRelationshipCopy on BuildContext {
  String relationshipText(String arabic, String english) =>
      l10n.isArabic ? arabic : english;
}
