import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

export 'kaj_relationship_stage5_components.dart';

/// Phase 3 presentation primitives for the maintenance and opportunity flows.
///
/// These widgets intentionally keep business state outside the design system.
/// They only provide the shared visual language required by KAJ: crisp geometry,
/// restrained metallic accents, strong hierarchy, and adaptive RTL/LTR layout.
class KajPhaseHero extends StatelessWidget {
  const KajPhaseHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.primaryAction,
    this.secondaryAction,
    this.trailing,
    this.accent = KajDesignTokens.electricBlue,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final dark = brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final onVariant = theme.colorScheme.onSurfaceVariant;

    return KajSurface(
      padding: EdgeInsets.zero,
      radius: KajDesignTokens.radiusLg,
      accent: accent,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _KajPhaseHeroPainter(accent: accent, dark: dark),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KajDesignTokens.space20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: compact ? 48 : 58,
                      height: compact ? 48 : 58,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            accent.withValues(alpha: dark ? .30 : .17),
                            accent.withValues(alpha: dark ? .08 : .05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(
                          KajDesignTokens.radiusMd,
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: .42),
                        ),
                      ),
                      child: Icon(icon, color: accent, size: compact ? 25 : 30),
                    ),
                    const SizedBox(width: KajDesignTokens.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            eyebrow.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              color: accent,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space6),
                          AppText(
                            title,
                            style: TextStyle(
                              fontSize: compact ? 23 : 29,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              color: onSurface,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 780),
                            child: AppText(
                              subtitle,
                              style: TextStyle(
                                fontSize: compact ? 12 : 13,
                                height: 1.45,
                                color: onVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final commands = Wrap(
                  spacing: KajDesignTokens.space8,
                  runSpacing: KajDesignTokens.space8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (secondaryAction != null) secondaryAction!,
                    if (primaryAction != null) primaryAction!,
                    if (trailing != null) trailing!,
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      identity,
                      if (primaryAction != null ||
                          secondaryAction != null ||
                          trailing != null) ...<Widget>[
                        const SizedBox(height: KajDesignTokens.space16),
                        commands,
                      ],
                    ],
                  );
                }

                return Row(
                  children: <Widget>[
                    Expanded(child: identity),
                    const SizedBox(width: KajDesignTokens.space20),
                    commands,
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

class KajWorkflowStepper extends StatelessWidget {
  const KajWorkflowStepper({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.completedColor = KajDesignTokens.success,
    this.activeColor = KajDesignTokens.electricBlue,
    this.compact = false,
  });

  final List<String> steps;
  final int currentIndex;
  final Color completedColor;
  final Color activeColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final effectiveIndex = currentIndex < 0
        ? -1
        : currentIndex.clamp(0, steps.length - 1);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(steps.length, (index) {
          final complete = index < effectiveIndex;
          final active = index == effectiveIndex;
          final color = complete
              ? completedColor
              : active
              ? activeColor
              : scheme.outlineVariant;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: compact ? 116 : 148,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 11,
                  vertical: compact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: complete || active ? .10 : .035,
                  ),
                  borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
                  border: Border.all(
                    color: color.withValues(
                      alpha: complete || active ? .58 : .34,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: compact ? 22 : 25,
                      height: compact ? 22 : 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: complete || active ? color : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: color),
                      ),
                      child: complete
                          ? const Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: Colors.white,
                            )
                          : AppText(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                color: active ? Colors.white : color,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    const SizedBox(width: KajDesignTokens.space8),
                    Expanded(
                      child: AppText(
                        steps[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          color: active || complete
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                          fontWeight: active || complete
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (index != steps.length - 1)
                Container(
                  width: compact ? 18 : 28,
                  height: 1,
                  color: index < effectiveIndex
                      ? completedColor.withValues(alpha: .65)
                      : scheme.outlineVariant,
                ),
            ],
          );
        }),
      ),
    );
  }
}

class KajStatusBadge extends StatelessWidget {
  const KajStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          AppText(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class KajLabeledMetric extends StatelessWidget {
  const KajLabeledMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent = KajDesignTokens.electricBlue,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
        border: Border.all(color: accent.withValues(alpha: .20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: KajDesignTokens.space8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppText(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              AppText(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurface,
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

class _KajPhaseHeroPainter extends CustomPainter {
  const _KajPhaseHeroPainter({required this.accent, required this.dark});

  final Color accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: dark ? .10 : .075);

    final direction = TextDirection.ltr;
    final anchor = direction == TextDirection.ltr ? size.width : 0.0;
    final sign = direction == TextDirection.ltr ? -1.0 : 1.0;
    for (var row = 0; row < 3; row++) {
      final y = 14.0 + row * 30;
      for (var i = 0; i < 5; i++) {
        final x = anchor + sign * (28 + i * 58 + (row.isOdd ? 24 : 0));
        final path = Path()
          ..moveTo(x, y + 12)
          ..lineTo(x + sign * 12, y)
          ..lineTo(x + sign * 38, y)
          ..lineTo(x + sign * 26, y + 12)
          ..lineTo(x + sign * 38, y + 24)
          ..lineTo(x + sign * 12, y + 24)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KajPhaseHeroPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.dark != dark;
}
