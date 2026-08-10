import 'package:flutter/material.dart';

import 'app_floating_window.dart';

/// Opens module work as a resizable module window.
///
/// The function name is retained for source compatibility. Existing forms may
/// still call `AppWorkspaceWindowScope.closeCurrent(context, result)` and the
/// returned future completes with that result.
Future<T?> showAppModuleDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  bool singleInstance = false,
  String? title,
  String? windowKey,
  double maxWidth = 920,
  double maxHeight = 720,
}) {
  return showAppFloatingWindow<T>(
    context: context,
    title: title,
    builder: builder,
    windowKey: windowKey,
    singleInstance: singleInstance,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}
