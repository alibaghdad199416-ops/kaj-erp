import 'package:flutter/material.dart';

/// One non-wrapping horizontal strip for dense ERP commands and metrics.
///
/// The strip owns the only horizontal scroll view in a command area. Child
/// widgets must therefore return plain rows/items rather than nesting another
/// horizontal scroller. Scrollbars and overscroll decoration are intentionally
/// disabled so the row does not look like a ruler under the module buttons.
class AppHorizontalStrip extends StatelessWidget {
  const AppHorizontalStrip({
    super.key,
    required this.children,
    this.spacing = 8,
    this.padding = EdgeInsets.zero,
    this.alignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) spaced.add(SizedBox(width: spacing));
      spaced.add(children[index]);
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
  }
}
