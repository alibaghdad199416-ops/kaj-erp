import 'package:flutter/widgets.dart';

abstract final class KajBreakpoints {
  static const double compact = 720;
  static const double medium = 1100;
  static const double expanded = 1440;
  static const double ultraWide = 1920;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isMedium(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= compact && width < medium;
  }

  static int gridColumnsFor(double width) {
    if (width >= ultraWide) return 4;
    if (width >= expanded) return 3;
    if (width >= medium) return 2;
    return 1;
  }
}
