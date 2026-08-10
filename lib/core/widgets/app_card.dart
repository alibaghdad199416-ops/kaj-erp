import 'package:flutter/material.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

/// Backwards-compatible premium card used throughout all ERP modules.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KajDesignTokens.space16),
    this.onTap,
    this.semanticLabel,
    this.accent,
    this.radius = KajDesignTokens.radiusMd,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? accent;
  final double radius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) => KajSurface(
    padding: padding,
    onTap: onTap,
    semanticLabel: semanticLabel,
    accent: accent,
    radius: radius,
    showShadow: showShadow,
    child: child,
  );
}
