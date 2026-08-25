import 'package:flutter/material.dart';

/// Shared sizing contract used across forms without changing the established
/// colors, shapes, or visual identity.
abstract final class AppLayoutMetrics {
  static const double controlHeight = 40;
  static const double compactControlHeight = 34;
  static const double iconButtonSize = 36;
  static const double fieldHorizontalPadding = 12;
  static const double fieldVerticalPadding = 10;
  static const double sectionGap = 12;
  static const double controlGap = 8;
  static const double pagePadding = 16;
  static const double dialogPadding = 16;
  static const double tableHeadingHeight = 42;
  static const double tableRowMinHeight = 40;
  static const double tableRowMaxHeight = 56;

  static ButtonStyle normalizeButton(ButtonStyle? base) {
    return (base ?? const ButtonStyle()).copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(0, controlHeight)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.15),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
    );
  }
}
