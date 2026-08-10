import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'kaj_design_tokens.dart';

/// Final shared primitives for fixes 04-08. These preserve the requested
/// translucent luxury look while guaranteeing readable contrast.
class KajTranslucentPanel extends StatelessWidget {
  const KajTranslucentPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.opacity,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? opacity;
  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: KajDesignTokens.surface(
          b,
        ).withValues(alpha: opacity ?? (b == Brightness.dark ? .92 : .96)),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.strongBorder(b)),
        boxShadow: KajDesignTokens.softShadow(b),
      ),
      child: child,
    );
  }
}

class KajDetailsGrid extends StatelessWidget {
  const KajDetailsGrid({
    super.key,
    required this.children,
    this.minCellWidth = 240,
  });
  final List<Widget> children;
  final double minCellWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = (c.maxWidth / minCellWidth).floor().clamp(1, 4);
      final width = (c.maxWidth - ((columns - 1) * 12)) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((e) => SizedBox(width: width, child: e))
            .toList(),
      );
    },
  );
}

class KajDetailCell extends StatelessWidget {
  const KajDetailCell({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });
  final String label;
  final String value;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KajDesignTokens.raisedSurface(b).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        border: Border.all(color: KajDesignTokens.border(b)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: KajDesignTokens.textSecondary(b),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  AppSelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: KajDesignTokens.textPrimary(b),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KajResponsiveDataTable extends StatelessWidget {
  const KajResponsiveDataTable({
    super.key,
    required this.table,
    this.header,
    this.footer,
    this.minWidth = 840,
  });
  final Widget table;
  final Widget? header;
  final Widget? footer;
  final double minWidth;
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return KajTranslucentPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (header != null)
            Padding(padding: const EdgeInsets.all(14), child: header),
          if (header != null)
            Divider(height: 1, color: KajDesignTokens.border(brightness)),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: table,
            ),
          ),
          if (footer != null) ...<Widget>[
            Divider(height: 1, color: KajDesignTokens.border(brightness)),
            Padding(padding: const EdgeInsets.all(14), child: footer),
          ],
        ],
      ),
    );
  }
}
