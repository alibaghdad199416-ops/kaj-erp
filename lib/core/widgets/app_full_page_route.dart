import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_horizontal_strip.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';

/// Opens module work in one consistent premium, movable and resizable window.
/// Every legacy Dialog/AlertDialog/Scaffold is normalized into the same header,
/// content viewport and command footer so controls cannot escape the window.
Future<T?> showAppFullPageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool barrierDismissible = false,
  double maxWidth = 1040,
  double maxHeight = 760,
  double minWidth = 520,
  double minHeight = 380,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: title ?? 'module-window',
    barrierColor: Colors.black.withValues(alpha: .68),
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
          scale: Tween<double>(begin: .97, end: 1).animate(curved),
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
            final horizontalMargin = viewport.maxWidth < 720 ? 8.0 : 24.0;
            final verticalMargin = viewport.maxHeight < 620 ? 8.0 : 20.0;
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
              clipBehavior: Clip.none,
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
                            clipBehavior: Clip.hardEdge,
                            child: _PremiumWindowTheme(
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PremiumWindowTheme extends StatelessWidget {
  const _PremiumWindowTheme({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final controlStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      textStyle: WidgetStatePropertyAll(
        base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
        ),
      ),
    );
    return Theme(
      data: base.copyWith(
        filledButtonTheme: FilledButtonThemeData(style: controlStyle),
        outlinedButtonTheme: OutlinedButtonThemeData(style: controlStyle),
        textButtonTheme: TextButtonThemeData(style: controlStyle),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 13,
          ),
        ),
      ),
      child: child,
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
  if (child is Dialog && child.child != null) {
    return _PlainContentAsWindow(closeDock: closeDock, child: child.child!);
  }
  return _PlainContentAsWindow(closeDock: closeDock, child: child);
}

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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
              color: KajDesignTokens.electricBlue.withValues(alpha: .10),
              border: Border.all(
                color: KajDesignTokens.electricBlue.withValues(alpha: .52),
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

class _WindowHeader extends StatelessWidget {
  const _WindowHeader({
    required this.title,
    required this.closeDock,
    this.actions,
  });
  final Widget? title;
  final Widget closeDock;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final values = actions ?? const <Widget>[];
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: KajDesignTokens.surfaceGradient(Theme.of(context).brightness),
        border: Border(
          bottom: BorderSide(
            color: KajDesignTokens.border(Theme.of(context).brightness),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: title == null
                ? const SizedBox.shrink()
                : DefaultTextStyle.merge(
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title!,
                  ),
          ),
          if (values.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(flex: 2, child: AppHorizontalStrip(children: values)),
          ],
          const SizedBox(width: 10),
          closeDock,
        ],
      ),
    );
  }
}

class _WindowFooter extends StatelessWidget {
  const _WindowFooter({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: KajDesignTokens.raisedSurface(Theme.of(context).brightness),
        border: Border(
          top: BorderSide(
            color: KajDesignTokens.border(Theme.of(context).brightness),
          ),
        ),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppHorizontalStrip(
          spacing: 8,
          children: Directionality.of(context) == TextDirection.rtl
              ? actions.reversed.toList(growable: false)
              : actions,
        ),
      ),
    );
  }
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
    final footerActions = scaffold.persistentFooterButtons;
    final backgroundColor =
        scaffold.backgroundColor ?? Theme.of(context).colorScheme.surface;
    return ColoredBox(
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WindowHeader(
            title: appBar?.title,
            closeDock: closeDock,
            actions: actions,
          ),
          if (bottom != null)
            SizedBox(height: bottom.preferredSize.height, child: bottom),
          Expanded(
            child: ClipRect(child: scaffold.body ?? const SizedBox.shrink()),
          ),
          if (footerActions != null && footerActions.isNotEmpty)
            _WindowFooter(actions: footerActions),
        ],
      ),
    );
  }
}

class _AlertDialogAsWindow extends StatelessWidget {
  const _AlertDialogAsWindow({required this.dialog, required this.closeDock});
  final AlertDialog dialog;
  final Widget closeDock;

  @override
  Widget build(BuildContext context) {
    final actions = dialog.actions ?? const <Widget>[];
    final content = dialog.content ?? const SizedBox.shrink();
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WindowHeader(
            title: dialog.title,
            closeDock: closeDock,
            actions: actions,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: ClipRect(
                child: dialog.scrollable
                    ? SingleChildScrollView(child: content)
                    : Align(
                        alignment: AlignmentDirectional.topStart,
                        child: SizedBox(width: double.infinity, child: content),
                      ),
              ),
            ),
          ),
        ],
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
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (showCloseOverlay) _WindowHeader(title: null, closeDock: closeDock),
        Expanded(child: ClipRect(child: child)),
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
      child: const SizedBox(width: 24, height: 24),
    ),
  );
}
