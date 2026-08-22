import 'package:flutter/material.dart';

import 'app_full_page_route.dart';

/// Opens module work in one centered operational window.
///
/// The legacy function name remains so existing modules share the same runtime
/// implementation. Desktop windows are bounded and responsive; compact
/// confirm/delete/error prompts should continue to use ordinary dialogs.
Future<T?> showAppFloatingWindow<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  double maxWidth = 1080,
  double maxHeight = 780,
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
