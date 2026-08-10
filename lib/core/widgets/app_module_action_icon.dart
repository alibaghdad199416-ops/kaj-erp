import 'package:flutter/material.dart';

import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Compact module-style action used by document workspaces.
///
/// The button mirrors the active-module mark in the workspace top bar: a
/// rounded square, layered tint, fine border, and a tooltip instead of a wide
/// text label. Every operational action uses the same system accent so the
/// command bar reads as one premium control family instead of a collection of
/// unrelated semantic colors. Meaning is carried by the icon and tooltip.
class AppModuleActionIcon extends StatelessWidget {
  const AppModuleActionIcon({
    super.key,
    required this.tooltip,
    required this.icon,
    this.color,
    required this.onPressed,
    this.busy = false,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;

  /// Kept for source compatibility with older call sites. All command icons
  /// intentionally use the same system accent; meaning is carried by [icon]
  /// and [tooltip], not by a second color family.
  final Color? color;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    const systemAccent = KajDesignTokens.electricBlue;
    final effective = enabled
        ? systemAccent
        : systemAccent.withValues(alpha: .42);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6, top: 8, bottom: 8),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    effective.withValues(alpha: .28),
                    effective.withValues(alpha: .08),
                  ],
                ),
                border: Border.all(
                  color: effective.withValues(alpha: .72),
                  width: 1,
                ),
                boxShadow: enabled
                    ? <BoxShadow>[
                        BoxShadow(
                          color: effective.withValues(alpha: .17),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Center(
                child: busy
                    ? SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: effective,
                        ),
                      )
                    : Icon(icon, size: 19, color: effective),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
