import 'package:flutter/material.dart';

import 'app_floating_window.dart';

/// Opens former workspace content as a normal resizable module window.
Future<T?> showAppWorkspaceDialog<T>({
  required BuildContext context,
  required Widget child,
  bool dismissible = false,
  String? title,
  String? windowKey,
  bool singleInstance = false,
  double maxWidth = 920,
  double maxHeight = 720,
}) {
  return showAppFloatingWindow<T>(
    context: context,
    title: title,
    builder: (_) => child,
    windowKey: windowKey,
    singleInstance: singleInstance,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}

/// Opens workspace content using the familiar [showDialog] builder shape.
///
/// Dialog-shaped builders are normalized into full-page content. Legacy
/// arguments remain accepted so existing modules migrate through one central
/// entry point without retaining floating windows or a taskbar.
Future<T?> showAppWorkspaceDialogBuilder<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  bool useRootNavigator = true,
  Color? barrierColor,
  String? title,
  String? windowKey,
  bool singleInstance = false,
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
