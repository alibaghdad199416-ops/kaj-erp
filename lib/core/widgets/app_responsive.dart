import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared viewport-aware sizing for dense ERP dialogs and detail surfaces.
///
/// A preferred desktop size is never allowed to exceed the usable viewport.
/// This keeps the same screen usable at browser zoom 100% and on smaller
/// displays without shrinking the entire UI canvas.
abstract final class AppResponsive {
  static double dialogWidth(
    BuildContext context,
    double preferred, {
    double horizontalMargin = 40,
  }) {
    final available = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - horizontalMargin,
    );
    return math.min(preferred, available);
  }

  static double dialogHeight(
    BuildContext context,
    double preferred, {
    double verticalMargin = 72,
  }) {
    final available = math.max(
      0.0,
      MediaQuery.sizeOf(context).height - verticalMargin,
    );
    return math.min(preferred, available);
  }
}
