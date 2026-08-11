import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

/// Opens module work in a movable, manually resizable content window.
///
/// The window has no title header, footer, taskbar, back button, minimum button,
/// maximum button, or restore button. The only visible window control is one
/// close button positioned inside the content surface. Dragging that close dock
/// moves the window; an invisible corner hit area keeps two-axis resizing.
Future<T?> showAppFullPageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool barrierDismissible = false,
  double maxWidth = 920,
  double maxHeight = 720,
  double minWidth = 440,
  double minHeight = 320,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: title ?? 'module-window',
    barrierColor: Colors.black.withValues(alpha: .64),
    transitionDuration: const Duration(milliseconds: 210),
    pageBuilder: (dialogContext, _, _) => _AppResizableModuleWindow<T>(
      title: title,
      builder: builder,
      barrierDismissible: barrierDismissible,
      preferredSize: Size(maxWidth, maxHeight),
      minimumSize: Size(minWidth, minHeight),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: .965, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AppResizableModuleWindow<T> extends StatefulWidget {
  const _AppResizableModuleWindow({
    required this.title,
    required this.builder,
    required this.barrierDismissible,
    required this.preferredSize,
    required this.minimumSize,
  });

  final String? title;
  final WidgetBuilder builder;
  final bool barrierDismissible;
  final Size preferredSize;
  final Size minimumSize;

  @override
  State<_AppResizableModuleWindow<T>> createState() =>
      _AppResizableModuleWindowState<T>();
}

class _AppResizableModuleWindowState<T>
    extends State<_AppResizableModuleWindow<T>> {
  bool _dirty = false;
  bool _closing = false;
  Size? _customSize;
  Offset _windowOffset = Offset.zero;

  void _setDirty(bool value) {
    if (!mounted || _dirty == value) return;
    setState(() => _dirty = value);
  }

  void _close([dynamic result]) {
    if (!mounted || _closing) return;
    _closing = true;
    Navigator.of(context, rootNavigator: true).pop<T>(result as T?);
  }

  Future<bool> _requestClose() async {
    if (!mounted || _closing) return false;
    if (_dirty) {
      final accepted =
          await showDialog<bool>(
            context: context,
            useRootNavigator: true,
            builder: (dialogContext) => AlertDialog(
              title: AppText(
                context.l10n.isArabic
                    ? 'تغييرات غير محفوظة'
                    : 'Unsaved changes',
              ),
              content: AppText(
                context.l10n.isArabic
                    ? 'توجد بيانات غير محفوظة. هل تريد إغلاق النافذة دون حفظ؟'
                    : 'There are unsaved changes. Close this window without saving?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: AppText(
                    context.l10n.isArabic ? 'متابعة التحرير' : 'Keep editing',
                  ),
                ),
                FilledButton(
                  key: const ValueKey('discard-unsaved-changes'),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: AppText(
                    context.l10n.isArabic
                        ? 'إغلاق دون حفظ'
                        : 'Close without saving',
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!accepted || !mounted) return false;
    }
    _close();
    return true;
  }

  void _resizeFromCorner(DragUpdateDetails details) {
    if (!mounted) return;
    setState(() {
      final current = _customSize ?? widget.preferredSize;
      _customSize = Size(
        math.max(widget.minimumSize.width, current.width + details.delta.dx),
        math.max(widget.minimumSize.height, current.height + details.delta.dy),
      );
    });
  }

  void _moveWindow(DragUpdateDetails details, Size viewport, Size size) {
    if (!mounted) return;
    final halfFreeWidth = math.max(0.0, (viewport.width - size.width) / 2);
    final halfFreeHeight = math.max(0.0, (viewport.height - size.height) / 2);
    setState(() {
      _windowOffset = Offset(
        (_windowOffset.dx + details.delta.dx)
            .clamp(-halfFreeWidth, halfFreeWidth)
            .toDouble(),
        (_windowOffset.dy + details.delta.dy)
            .clamp(-halfFreeHeight, halfFreeHeight)
            .toDouble(),
      );
    });
  }

  Future<void> _handleSystemBack(bool didPop, dynamic result) async {
    if (didPop || _closing) return;
    await _requestClose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<dynamic>(
      canPop: false,
      onPopInvokedWithResult: _handleSystemBack,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final horizontalMargin = viewport.maxWidth < 720 ? 8.0 : 26.0;
            final verticalMargin = viewport.maxHeight < 620 ? 8.0 : 22.0;
            final available = Size(
              math.max(280.0, viewport.maxWidth - horizontalMargin * 2),
              math.max(240.0, viewport.maxHeight - verticalMargin * 2),
            );
            final minimum = Size(
              math.min(widget.minimumSize.width, available.width),
              math.min(widget.minimumSize.height, available.height),
            );
            final preferred = _customSize ?? widget.preferredSize;
            final size = Size(
              preferred.width.clamp(minimum.width, available.width).toDouble(),
              preferred.height
                  .clamp(minimum.height, available.height)
                  .toDouble(),
            );

            final closeDock = _CloseAndMoveDock(
              onClose: _requestClose,
              onMove: (details) => _moveWindow(
                details,
                Size(viewport.maxWidth, viewport.maxHeight),
                size,
              ),
            );

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.barrierDismissible
                        ? () => unawaited(_requestClose())
                        : null,
                    child: const SizedBox.expand(),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: _windowOffset,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: AppWorkspaceWindowScope(
                        windowId: 0,
                        title: widget.title?.trim() ?? '',
                        close: _close,
                        requestClose: _requestClose,
                        setDirty: _setDirty,
                        isDirty: _dirty,
                        child: KajShellSurface(
                          key: const ValueKey('module-full-page-route'),
                          padding: EdgeInsets.zero,
                          radius: KajDesignTokens.radiusLg,
                          emphasized: true,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              KajDesignTokens.radiusLg,
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: _WindowContentNavigator<T>(
                                      builder: (contentContext) =>
                                          _normalizeContent(
                                            widget.builder(contentContext),
                                            closeDock: closeDock,
                                          ),
                                      onRootPopped: _close,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: _InvisibleResizeCorner(
                                    onPanUpdate: _resizeFromCorner,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Widget _normalizeContent(Widget child, {required Widget closeDock}) {
  if (child is AppEntityPage) {
    return _PlainContentAsWindow(
      closeDock: closeDock,
      showCloseOverlay: false,
      child: child,
    );
  }
  if (child is AlertDialog) {
    return _AlertDialogAsWindow(dialog: child, closeDock: closeDock);
  }
  if (child is Scaffold) {
    return _ScaffoldAsWindow(scaffold: child, closeDock: closeDock);
  }
  if (child is Dialog) {
    final dialogChild = child.child;
    if (dialogChild != null) {
      return _PlainContentAsWindow(closeDock: closeDock, child: dialogChild);
    }
  }
  return _PlainContentAsWindow(closeDock: closeDock, child: child);
}

/// A local Navigator preserves existing `Navigator.pop(context, result)` calls
/// in older forms. The permanent guard route prevents an empty window frame.
class _WindowContentNavigator<T> extends StatelessWidget {
  const _WindowContentNavigator({
    required this.builder,
    required this.onRootPopped,
  });

  final WidgetBuilder builder;
  final ValueChanged<T?> onRootPopped;

  @override
  Widget build(BuildContext context) => HeroControllerScope.none(
    child: Navigator(
      key: const ValueKey('module-window-content-navigator'),
      onGenerateInitialRoutes: (_, _) => <Route<dynamic>>[
        PageRouteBuilder<dynamic>(
          settings: const RouteSettings(name: 'module-window-guard'),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        _WindowContentRoute<T>(builder: builder, onPopped: onRootPopped),
      ],
      onGenerateRoute: (_) => null,
    ),
  );
}

class _WindowContentRoute<T> extends PageRouteBuilder<T> {
  _WindowContentRoute({required WidgetBuilder builder, required this.onPopped})
    : super(
        settings: const RouteSettings(name: 'module-window-content'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) =>
            FocusTraversalGroup(child: Builder(builder: builder)),
      );

  final ValueChanged<T?> onPopped;
  bool _reported = false;

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped && !_reported) {
      _reported = true;
      scheduleMicrotask(() => onPopped(result));
    }
    return popped;
  }
}

class _CloseAndMoveDock extends StatelessWidget {
  const _CloseAndMoveDock({required this.onClose, required this.onMove});

  final Future<bool> Function() onClose;
  final GestureDragUpdateCallback onMove;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.move,
    child: GestureDetector(
      key: const ValueKey('module-window-move-surface'),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onMove,
      child: Tooltip(
        message: context.l10n.isArabic ? 'إغلاق' : 'Close',
        child: InkWell(
          key: const ValueKey('module-page-close'),
          onTap: () => unawaited(onClose()),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  KajDesignTokens.electricBlue.withValues(alpha: .28),
                  KajDesignTokens.electricBlue.withValues(alpha: .08),
                ],
              ),
              border: Border.all(
                color: KajDesignTokens.electricBlue.withValues(alpha: .68),
              ),
            ),
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: KajDesignTokens.electricBlue,
            ),
          ),
        ),
      ),
    ),
  );
}

class _WindowContentFrame extends StatelessWidget {
  const _WindowContentFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _ScaffoldAsWindow extends StatelessWidget {
  const _ScaffoldAsWindow({required this.scaffold, required this.closeDock});

  final Scaffold scaffold;
  final Widget closeDock;

  @override
  Widget build(BuildContext context) {
    final appBar = scaffold.appBar is AppBar
        ? scaffold.appBar! as AppBar
        : null;
    final actions = <Widget>[
      ...?appBar?.actions,
      if (scaffold.floatingActionButton != null) scaffold.floatingActionButton!,
    ];
    final bottom = appBar?.bottom;
    final backgroundColor =
        scaffold.backgroundColor ?? Theme.of(context).colorScheme.surface;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 10),
          decoration: BoxDecoration(
            gradient: KajDesignTokens.surfaceGradient(
              Theme.of(context).brightness,
            ),
            border: Border(
              bottom: BorderSide(
                color: KajDesignTokens.border(Theme.of(context).brightness),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              if (appBar?.title case final title?)
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 12),
              if (actions.isNotEmpty)
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: Directionality.of(context) == TextDirection.rtl,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (
                          var index = 0;
                          index < actions.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 7),
                          actions[index],
                        ],
                      ],
                    ),
                  ),
                ),
              if (actions.isNotEmpty) const SizedBox(width: 8),
              closeDock,
            ],
          ),
        ),
        if (bottom != null)
          DecoratedBox(
            decoration: BoxDecoration(
              color: KajDesignTokens.raisedSurface(
                Theme.of(context).brightness,
              ),
              border: Border(
                bottom: BorderSide(
                  color: KajDesignTokens.border(Theme.of(context).brightness),
                ),
              ),
            ),
            child: SizedBox(height: bottom.preferredSize.height, child: bottom),
          ),
        Expanded(child: scaffold.body ?? const SizedBox.shrink()),
      ],
    );

    return ColoredBox(
      color: backgroundColor,
      child: _WindowContentFrame(child: body),
    );
  }
}

class _AlertDialogAsWindow extends StatelessWidget {
  const _AlertDialogAsWindow({required this.dialog, required this.closeDock});

  final AlertDialog dialog;
  final Widget closeDock;

  @override
  Widget build(BuildContext context) {
    final title = dialog.title;
    final actions = dialog.actions ?? const <Widget>[];
    return _WindowContentFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: <Widget>[
                if (title != null)
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: title,
                    ),
                  )
                else
                  const Spacer(),
                if (actions.isNotEmpty) const SizedBox(width: 12),
                if (actions.isNotEmpty)
                  Flexible(
                    flex: 2,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: Directionality.of(context) == TextDirection.rtl,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (
                            var index = 0;
                            index < actions.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 7),
                            actions[index],
                          ],
                        ],
                      ),
                    ),
                  ),
                if (actions.isNotEmpty) const SizedBox(width: 8),
                closeDock,
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: dialog.scrollable
                  ? SingleChildScrollView(
                      padding: EdgeInsets.zero,
                      child: dialog.content ?? const SizedBox.shrink(),
                    )
                  : Align(
                      alignment: AlignmentDirectional.topStart,
                      child: SizedBox(
                        width: double.infinity,
                        child: dialog.content ?? const SizedBox.shrink(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainContentAsWindow extends StatelessWidget {
  const _PlainContentAsWindow({
    required this.closeDock,
    required this.child,
    this.showCloseOverlay = true,
  });

  final Widget closeDock;
  final Widget child;
  final bool showCloseOverlay;

  @override
  Widget build(BuildContext context) => _WindowContentFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showCloseOverlay)
          Container(
            height: 56,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 9, 12, 9),
            decoration: BoxDecoration(
              gradient: KajDesignTokens.surfaceGradient(
                Theme.of(context).brightness,
              ),
              border: Border(
                bottom: BorderSide(
                  color: KajDesignTokens.border(Theme.of(context).brightness),
                ),
              ),
            ),
            child: Row(children: <Widget>[const Spacer(), closeDock]),
          ),
        Expanded(child: child),
      ],
    ),
  );
}

class _InvisibleResizeCorner extends StatelessWidget {
  const _InvisibleResizeCorner({required this.onPanUpdate});

  final GestureDragUpdateCallback onPanUpdate;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeDownRight,
    child: GestureDetector(
      key: const ValueKey('module-window-resize-corner'),
      behavior: HitTestBehavior.translucent,
      onPanUpdate: onPanUpdate,
      child: const SizedBox(width: 22, height: 22),
    ),
  );
}
