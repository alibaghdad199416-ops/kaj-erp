import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

/// Shared visual language for entry, discovery and personal-workspace screens.
class KajEntryPanel extends StatelessWidget {
  const KajEntryPanel({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.padding = const EdgeInsets.all(28),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: KajShellSurface(emphasized: true, padding: padding, child: child),
    ),
  );
}

class KajEntryHeading extends StatelessWidget {
  const KajEntryHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                KajDesignTokens.electricBlue.withValues(alpha: .22),
                KajDesignTokens.champagne.withValues(alpha: .10),
              ],
            ),
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
            border: Border.all(
              color: KajDesignTokens.electricBlue.withValues(alpha: .30),
            ),
          ),
          child: Icon(icon, color: KajDesignTokens.electricBlue),
        ),
        const SizedBox(height: 18),
        AppText(
          eyebrow,
          style: TextStyle(
            color: KajDesignTokens.champagne,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 7),
        AppText(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.4,
          ),
        ),
        const SizedBox(height: 8),
        AppText(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class KajActivitySkeleton extends StatelessWidget {
  const KajActivitySkeleton({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final base = KajDesignTokens.border(brightness).withValues(alpha: .55);
    return KajShellSurface(
      child: Column(
        children: List<Widget>.generate(
          rows,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 13),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(
                      KajDesignTokens.radiusSm,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FractionallySizedBox(
                        widthFactor: .62,
                        child: Container(height: 10, color: base),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: .38,
                        child: Container(height: 8, color: base),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KajProfileSummary extends StatelessWidget {
  const KajProfileSummary({
    super.key,
    required this.name,
    required this.role,
    required this.avatar,
  });

  final String name;
  final String role;
  final Widget avatar;

  @override
  Widget build(BuildContext context) => KajShellSurface(
    emphasized: true,
    child: Row(
      children: <Widget>[
        avatar,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppText(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              AppText(
                role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
