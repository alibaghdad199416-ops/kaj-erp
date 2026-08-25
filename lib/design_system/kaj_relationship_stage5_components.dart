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
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      KajDesignTokens.champagne.withValues(alpha: .94),
                      scheme.primary.withValues(alpha: .88),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      eyebrow.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.25,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppText(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 12),
                          trailing!,
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    AppText(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              // Keep explicit conditions for compatibility with the current
              // Flutter/Dart collection-element syntax.
              // ignore: use_null_aware_elements
              if (secondaryAction != null) secondaryAction!,
              // ignore: use_null_aware_elements
              if (primaryAction != null) primaryAction!,
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                identity,
                if (primaryAction != null || secondaryAction != null) ...[
                  const SizedBox(height: 18),
                  actions,
                ],
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 20),
                    actions,
                  ],
                ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 10, runSpacing: 10, children: metrics),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: theme.colorScheme.primary, size: 21),
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
              // ignore: use_null_aware_elements
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
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
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
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
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
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
                      size: 17,
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
                Container(width: 22, height: 1, color: scheme.outlineVariant),
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
