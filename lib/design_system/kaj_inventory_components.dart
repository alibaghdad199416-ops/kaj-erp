import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_breakpoints.dart';
import 'package:quality_line_erp/design_system/kaj_component_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_motion.dart';

class KajInventoryActionBar extends StatelessWidget {
  const KajInventoryActionBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actions = const <Widget>[],
    this.metrics = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> actions;
  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final foreground = dark ? Colors.white : const Color(0xFF11171A);
    return AnimatedContainer(
      duration: KajMotion.standard,
      curve: KajMotion.standardCurve,
      padding: KajComponentTokens.cardPadding,
      decoration: BoxDecoration(
        color: KajDesignTokens.surface(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < KajBreakpoints.medium;
              final heading = Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: KajDesignTokens.primaryGradient(brightness),
                      borderRadius: BorderRadius.circular(
                        KajDesignTokens.radiusMd,
                      ),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppText(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        AppText(
                          subtitle,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .62),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
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
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: heading),
                  if (actions.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 16),
                    Flexible(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (metrics.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Wrap(spacing: 8, runSpacing: 8, children: metrics),
          ],
        ],
      ),
    );
  }
}

class KajInventoryMetricPill extends StatelessWidget {
  const KajInventoryMetricPill({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = accent ?? Theme.of(context).colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 148),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KajDesignTokens.raisedSurface(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppText(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              AppText(
                value,
                style: const TextStyle(
                  fontSize: 14,
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

class KajInventoryPanel extends StatelessWidget {
  const KajInventoryPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: KajDesignTokens.surface(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: child,
    );
  }
}
