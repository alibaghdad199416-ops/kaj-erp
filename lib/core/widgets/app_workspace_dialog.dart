import 'package:flutter/material.dart';

import 'app_floating_window.dart';

/// Opens former workspace content as one normal responsive module window.
Future<T?> showAppWorkspaceDialog<T>({
  required BuildContext context,
  required Widget child,
  bool dismissible = false,
  String? title,
  String? windowKey,
  bool singleInstance = false,
  double maxWidth = 1180,
  double maxHeight = 820,
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
/// Operational builders are normalized by the central window route so the
/// screen has one header only and keeps its working controls close to content.
Future<T?> showAppWorkspaceDialogBuilder<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  bool useRootNavigator = true,
  Color? barrierColor,
  String? title,
  String? windowKey,
  bool singleInstance = false,
  double maxWidth = 1180,
  double maxHeight = 820,
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
