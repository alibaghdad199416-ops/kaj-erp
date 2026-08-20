import 'package:flutter/material.dart';

/// Polished command/metric rail shared by ERP modules.
///
/// Rails that fit comfortably on one line stay single-line and remain reachable
/// through a discreet horizontal scroll. Dense rails (8+ controls) automatically
/// wrap on desktop so every destination stays visible at 100% browser zoom
/// instead of ending in a clipped, partially visible chip. The wrap decision
/// uses the actual layout width so bounded module rails behave consistently
/// inside windows, dialogs and splitters.
class AppHorizontalStrip extends StatelessWidget {
  const AppHorizontalStrip({
    super.key,
    required this.children,
    this.spacing = 8,
    this.padding = EdgeInsets.zero,
    this.alignment = CrossAxisAlignment.center,
    this.minControlHeight = 42,
  });

  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment alignment;
  final double minControlHeight;

  Widget _item(Widget child) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: minControlHeight),
    child: Align(alignment: AlignmentDirectional.centerStart, child: child),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the actual available layout width when bounded; otherwise fall
        // back to the window width so unbounded (sliver/overflow) parents
        // remain safe.
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Dense rails (8+ controls) wrap on desktop so every destination stays
        // visible at 100% browser zoom. Short rails remain on one horizontally
        // scrollable line so mixed-content rails (actions + statistics) never
        // balloon into tall stacked rows.
        final wrapChildren = children.length >= 8 && availableWidth >= 900;

        if (wrapChildren) {
          return Padding(
            padding: padding,
            child: Wrap(
              spacing: spacing,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: children.map(_item).toList(growable: false),
            ),
          );
        }

        final spaced = <Widget>[];
        for (var index = 0; index < children.length; index++) {
          if (index > 0) spaced.add(SizedBox(width: spacing));
          spaced.add(_item(children[index]));
        }

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(
            context,
          ).copyWith(scrollbars: false, overscroll: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: alignment,
              children: spaced,
            ),
          ),
        );
      },
    );
  }
}
