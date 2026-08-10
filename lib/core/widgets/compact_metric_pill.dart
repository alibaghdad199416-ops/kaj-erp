import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Compact V4 metric indicator used by module dashboards and headers.
class CompactMetricPill extends StatelessWidget {
  const CompactMetricPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = color ?? KajDesignTokens.electricBlue;
    final content = Container(
      constraints: const BoxConstraints(
        minHeight: 54,
        minWidth: 170,
        maxWidth: 260,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 13, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: dark
              ? const <Color>[Color(0xFF111C24), Color(0xFF091117)]
              : const <Color>[Colors.white, Color(0xFFF7F9FA)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: effectiveColor.withValues(alpha: .24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .24 : .05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: effectiveColor.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: effectiveColor.withValues(alpha: .20)),
            ),
            child: Icon(icon, size: 18, color: effectiveColor),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: content,
    );
  }
}
