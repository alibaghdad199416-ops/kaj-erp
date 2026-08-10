import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Shared V4 visual primitives reconstructed from the approved KAJ reference
/// boards. They deliberately contain no business logic so every module can use
/// the same premium automotive language without changing repositories, RPCs,
/// permissions, or document workflows.
class KajV4Panel extends StatelessWidget {
  const KajV4Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.accent,
    this.radius = 14,
    this.onTap,
    this.showTopGlow = false,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? accent;
  final double radius;
  final VoidCallback? onTap;
  final bool showTopGlow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final line = accent ?? KajDesignTokens.electricBlue;
    final surface = dark ? const Color(0xFF0B1218) : Colors.white;
    final raised = dark ? const Color(0xFF111B23) : const Color(0xFFF7F9FA);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .34 : .08),
            blurRadius: dark ? 26 : 18,
            offset: const Offset(0, 12),
          ),
          if (showTopGlow)
            BoxShadow(
              color: line.withValues(alpha: dark ? .10 : .06),
              blurRadius: 28,
              spreadRadius: -8,
              offset: const Offset(0, -4),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: clipBehavior,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: dark ? const Color(0xFF263541) : const Color(0xFFD9E1E5),
            ),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: <Color>[raised, surface],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            hoverColor: line.withValues(alpha: .045),
            highlightColor: line.withValues(alpha: .06),
            splashColor: line.withValues(alpha: .08),
            child: Stack(
              children: <Widget>[
                if (showTopGlow)
                  PositionedDirectional(
                    top: 0,
                    start: 28,
                    end: 28,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.transparent,
                            line.withValues(alpha: .88),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KajV4PageHeader extends StatelessWidget {
  const KajV4PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.icon = Icons.grid_view_rounded,
    this.actions = const <Widget>[],
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final IconData icon;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleBlock = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: compact ? 38 : 44,
          height: compact ? 38 : 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: <Color>[
                KajDesignTokens.electricBlue.withValues(alpha: .22),
                KajDesignTokens.electricBlue.withValues(alpha: .06),
              ],
            ),
            border: Border.all(
              color: KajDesignTokens.electricBlue.withValues(alpha: .38),
            ),
          ),
          child: Icon(
            icon,
            size: compact ? 19 : 22,
            color: KajDesignTokens.electricBlue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (eyebrow != null && eyebrow!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: AppText(
                    eyebrow!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: KajDesignTokens.champagne,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .25,
                    ),
                  ),
                ),
              AppText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.35,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 3),
                AppText(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    if (actions.isEmpty) return titleBlock;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              titleBlock,
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            ],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: titleBlock),
            const SizedBox(width: 18),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
      },
    );
  }
}

class KajV4MetricCard extends StatelessWidget {
  const KajV4MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.accent = KajDesignTokens.electricBlue,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return KajV4Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      accent: accent,
      showTopGlow: true,
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .11),
              border: Border.all(color: accent.withValues(alpha: .24)),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.45,
                  ),
                ),
                if (caption != null && caption!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  AppText(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KajV4StatusBadge extends StatelessWidget {
  const KajV4StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = KajDesignTokens.success,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: .30)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        AppText(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class KajV4ActionTile extends StatelessWidget {
  const KajV4ActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = KajDesignTokens.electricBlue,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) => KajV4Panel(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
    accent: accent,
    child: Row(
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: accent.withValues(alpha: .10),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppText(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        Icon(
          Icons.arrow_forward_ios_rounded,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    ),
  );
}
