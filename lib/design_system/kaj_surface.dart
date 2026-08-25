import 'package:flutter/material.dart';

import 'kaj_design_tokens.dart';

/// Reusable premium surface used by cards, panels and module sections.
///
/// V4 reconstructs the smoked-glass panels from the approved automotive ERP
/// boards: restrained border, subtle top highlight, deep shadow, and a very
/// small hover lift. Business widgets remain unaware of those visual details.
class KajSurface extends StatefulWidget {
  const KajSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(KajDesignTokens.space16),
    this.onTap,
    this.accent,
    this.radius = KajDesignTokens.radiusMd,
    this.showShadow = true,
    this.clipBehavior = Clip.antiAlias,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final double radius;
  final bool showShadow;
  final Clip clipBehavior;
  final String? semanticLabel;

  @override
  State<KajSurface> createState() => _KajSurfaceState();
}

class _KajSurfaceState extends State<KajSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final accent = widget.accent ?? KajDesignTokens.electricBlue;
    final active = _hovered && widget.onTap != null;
    final border = active
        ? accent.withValues(alpha: .68)
        : KajDesignTokens.border(brightness);

    Widget result = AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, active ? -1.5 : 0, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: dark
              ? const <Color>[Color(0xFF111D25), Color(0xFF081016)]
              : const <Color>[Colors.white, Color(0xFFF7F9FA)],
        ),
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: border, width: 1),
        boxShadow: widget.showShadow
            ? (active
                  ? KajDesignTokens.accentShadow(brightness, accent: accent)
                  : KajDesignTokens.softShadow(brightness))
            : null,
      ),
      clipBehavior: widget.clipBehavior,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: accent.withValues(alpha: .045),
          splashColor: accent.withValues(alpha: .09),
          highlightColor: accent.withValues(alpha: .055),
          child: Stack(
            children: <Widget>[
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
                        accent.withValues(alpha: dark ? .24 : .16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: widget.padding, child: widget.child),
            ],
          ),
        ),
      ),
    );

    result = MouseRegion(
      onEnter: widget.onTap == null
          ? null
          : (_) => setState(() => _hovered = true),
      onExit: widget.onTap == null
          ? null
          : (_) => setState(() => _hovered = false),
      child: result,
    );

    if (widget.semanticLabel != null) {
      result = Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        child: result,
      );
    }
    return result;
  }
}
