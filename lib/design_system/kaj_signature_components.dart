import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_brand_motif.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Signature-edition page hero used by the application entry and overview
/// modules. It intentionally avoids business logic so every module can share
/// the same premium composition without visual drift.
class KajSignaturePageHero extends StatelessWidget {
  const KajSignaturePageHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    this.trailing,
    this.metrics = const <KajSignatureMetricData>[],
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final List<KajSignatureMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final foreground = dark ? Colors.white : const Color(0xFF101619);
    final muted = foreground.withValues(alpha: .66);

    return Container(
      decoration: BoxDecoration(
        gradient: dark
            ? const LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[Color(0xFF111B22), Color(0xFF071014)],
              )
            : const LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[Colors.white, Color(0xFFF1F6F7)],
              ),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusXl),
        border: Border.all(
          color: KajDesignTokens.champagne.withValues(alpha: dark ? .30 : .38),
        ),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: KajBrandMotif(
              opacity: .075,
              alignment: AlignmentDirectional.centerEnd,
              accent: KajDesignTokens.champagne,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final intro = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: KajDesignTokens.primaryGradient(brightness),
                        borderRadius: BorderRadius.circular(
                          KajDesignTokens.radiusMd,
                        ),
                        boxShadow: KajDesignTokens.accentShadow(
                          brightness,
                          accent: KajDesignTokens.electricBlue,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 23),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            eyebrow.toUpperCase(),
                            style: TextStyle(
                              color: KajDesignTokens.champagne,
                              fontSize: 10.5,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 7),
                          AppText(
                            title,
                            style: TextStyle(
                              color: foreground,
                              fontSize: compact ? 24 : 30,
                              height: 1.12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: context.l10n.isArabic ? -.3 : -.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: AppText(
                              subtitle,
                              style: TextStyle(
                                color: muted,
                                fontSize: 13.5,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact && trailing != null) ...<Widget>[
                      const SizedBox(width: 18),
                      trailing!,
                    ],
                  ],
                );

                final metricStrip = metrics.isEmpty
                    ? const SizedBox.shrink()
                    : Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: metrics
                            .map((item) => KajSignatureMetric(data: item))
                            .toList(growable: false),
                      );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    intro,
                    if (compact && trailing != null) ...<Widget>[
                      const SizedBox(height: 18),
                      trailing!,
                    ],
                    if (metrics.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 22),
                      metricStrip,
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

class KajSignatureMetricData {
  const KajSignatureMetricData({
    required this.label,
    required this.value,
    required this.icon,
    this.accent = KajDesignTokens.electricBlue,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
}

class KajSignatureMetric extends StatelessWidget {
  const KajSignatureMetric({super.key, required this.data});

  final KajSignatureMetricData data;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final foreground = dark ? Colors.white : const Color(0xFF101619);

    return Container(
      width: 176,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KajDesignTokens.raisedSurface(brightness).withValues(alpha: .86),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        border: Border.all(color: data.accent.withValues(alpha: .24)),
      ),
      child: Row(
        children: <Widget>[
          Icon(data.icon, color: data.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground.withValues(alpha: .58),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
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

class KajSignatureSearchSurface extends StatelessWidget {
  const KajSignatureSearchSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
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
