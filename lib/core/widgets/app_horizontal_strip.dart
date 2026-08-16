import 'package:flutter/material.dart';

/// One polished non-wrapping command/metric rail shared by ERP modules.
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

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) spaced.add(SizedBox(width: spacing));
      spaced.add(
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minControlHeight),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: children[index],
          ),
        ),
      );
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
