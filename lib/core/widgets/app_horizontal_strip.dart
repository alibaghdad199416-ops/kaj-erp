import 'package:flutter/material.dart';

/// Polished command/metric rail shared by ERP modules.
///
/// Short rails stay single-line and horizontally scrollable. Dense navigation
/// rails automatically wrap on desktop so every destination remains visible at
/// 100% browser zoom instead of ending in a clipped, partially visible chip.
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
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (children.length >= 8 && MediaQuery.sizeOf(context).width >= 900) {
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
  }
}
