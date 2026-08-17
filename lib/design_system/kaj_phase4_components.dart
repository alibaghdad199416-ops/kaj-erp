import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_chrome_scope.dart';
import 'package:quality_line_erp/design_system/kaj_brand_motif.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

/// Shared luxury presentation primitives for Phase 4 business partners.
///
/// Business state deliberately remains in feature controllers. These widgets
/// only provide a consistent KAJ visual language across customers, suppliers,
/// partner profiles, balances, documents, and activity panels.
class KajPartnerHero extends StatelessWidget {
  const KajPartnerHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (AppWorkspaceChromeScope.hasTopBarOf(context)) {
      if (actions.isEmpty) return const SizedBox.shrink();
      return SizedBox(
        height: 40,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: KajDesignTokens.space8),
                actions[index],
              ],
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = KajDesignTokens.champagneGold;

    return KajSurface(
      radius: KajDesignTokens.radiusLg,
      padding: EdgeInsets.zero,
      accent: accent,
      child: Stack(
        children: <Widget>[
          PositionedDirectional(
            end: -22,
            top: -28,
            bottom: -28,
            width: 330,
            child: Opacity(
              opacity: dark ? .12 : .075,
              child: const KajBrandMotif(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KajDesignTokens.space20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final identity = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: dark ? .16 : .11),
                        borderRadius: BorderRadius.circular(
                          KajDesignTokens.radiusMd,
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: .48),
                        ),
                      ),
                      child: Icon(
                        Icons.handshake_outlined,
                        color: accent,
                        size: 29,
                      ),
                    ),
                    const SizedBox(width: KajDesignTokens.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            AppTranslation.translate('علاقات الأعمال'),
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              letterSpacing: 1.35,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space6),
                          AppText(
                            title,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: compact ? 23 : 29,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: KajDesignTokens.space8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: AppText(
                              subtitle,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                                height: 1.45,
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
                  children: actions,
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      identity,
                      if (actions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: KajDesignTokens.space16),
                        commands,
                      ],
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: identity),
                    if (actions.isNotEmpty) ...<Widget>[
                      const SizedBox(width: KajDesignTokens.space20),
                      commands,
                    ],
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

class KajPartnerCardShell extends StatelessWidget {
  const KajPartnerCardShell({
    super.key,
    required this.child,
    required this.accent,
    this.onTap,
  });

  final Widget child;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: .72),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? .18 : .055,
                ),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              PositionedDirectional(
                start: 0,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class KajPartnerMetric extends StatelessWidget {
  const KajPartnerMetric({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 145),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
        border: Border.all(color: accent.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                AppText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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
