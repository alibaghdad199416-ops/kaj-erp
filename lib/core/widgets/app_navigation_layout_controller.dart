import 'package:flutter/foundation.dart';

/// Shares the live application-navigation geometry with the global workspace.
///
/// Floating windows are rendered only inside the module content area, so they
/// can never cover or intercept the side-navigation controls.
class AppNavigationLayoutController {
  AppNavigationLayoutController._();

  static final ValueNotifier<double> sideWidth = ValueNotifier<double>(0);

  static void reset() => sideWidth.value = 0;
}
