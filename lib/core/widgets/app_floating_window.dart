import 'package:flutter/material.dart';

import 'app_full_page_route.dart';

/// Opens module work in one centered, resizable module window.
///
/// The legacy function name remains so existing modules share the same runtime
/// implementation. Windows are transient and have no persistent taskbar.
Future<T?> showAppFloatingWindow<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double maxWidth = 620,
  double maxHeight = 520,
  String? windowKey,
  bool singleInstance = false,
}) {
  return showAppFullPageRoute<T>(
    context: context,
    title: title,
    builder: builder,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}
