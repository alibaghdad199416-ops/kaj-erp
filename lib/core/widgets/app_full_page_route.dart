import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Opens operational module content as a true full-viewport workspace.
///
/// Legacy size arguments remain accepted for source compatibility only.
/// Operational workspaces intentionally fill the available viewport, strip
/// legacy window/AppBar chrome, and keep only functional module content plus a
/// compact close control. This makes forms usable at 100% browser zoom without
/// nested boxes or duplicated modal headers.
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
    barrierLabel: title ?? 'module-workspace',
    barrierColor: Theme.of(context).scaffoldBackgroundColor,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) => _AppFullViewportWorkspace<T>(
      title: title,
      builder: builder,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class _AppFullViewportWorkspace<T> extends StatefulWidget {
  const _AppFullViewportWorkspace({required this.title, required this.builder});

  final String? title;
  final WidgetBuilder builder;

  @override
  State<_AppFullViewportWorkspace<T>> createState() =>
      _AppFullViewportWorkspaceState<T>();
}

class _AppFullViewportWorkspaceState<T>
    extends State<_AppFullViewportWorkspace<T>> {
  bool _dirty = false;
  bool _closing = false;

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
              title: Text(
                context.l10n.isArabic
                    ? 'تغييرات غير محفوظة'
                    : 'Unsaved changes',
              ),
              content: Text(
                context.l10n.isArabic
                    ? 'توجد بيانات غير محفوظة. هل تريد إغلاق الشاشة دون حفظ؟'
                    : 'There are unsaved changes. Close this screen without saving?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    context.l10n.isArabic ? 'متابعة التحرير' : 'Keep editing',
                  ),
                ),
                FilledButton(
                  key: const ValueKey('discard-unsaved-changes'),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
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
        key: const ValueKey('module-full-page-route'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: AppWorkspaceWindowScope(
          windowId: 0,
          title: widget.title?.trim() ?? '',
          close: _close,
          requestClose: _requestClose,
          setDirty: _setDirty,
          isDirty: _dirty,
          child: _PremiumWorkspaceTheme(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Builder(
                      builder: (workspaceContext) =>
                          _normalizeFullViewportContent(
                            workspaceContext,
                            widget.builder(workspaceContext),
                          ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 12,
                  bottom: 12,
                  child: SafeArea(
                    minimum: const EdgeInsets.all(4),
                    child: _FloatingCloseButton(onClose: _requestClose),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumWorkspaceTheme extends StatelessWidget {
  const _PremiumWorkspaceTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final controlStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 15, vertical: 10),
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
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
      child: child,
    );
  }
}

Widget _normalizeFullViewportContent(BuildContext context, Widget child) {
  if (child is AppEntityPage) return child;
  if (child is Scaffold) return _scaffoldAsHeaderlessWorkspace(context, child);

  if (child is AlertDialog) {
    final actions = child.actions ?? const <Widget>[];
    return Material(
      color: child.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (child.title != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 22, 72, 6),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                child: child.title!,
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 14, 24, 24),
              child: child.content ?? const SizedBox.shrink(),
            ),
          ),
          if (actions.isNotEmpty)
            SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: .45),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 18),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  if (child is Dialog && child.child != null) {
    return SizedBox.expand(child: child.child!);
  }

  return SizedBox.expand(child: child);
}

Widget _scaffoldAsHeaderlessWorkspace(BuildContext context, Scaffold source) {
  final legacyAppBar = source.appBar;
  final appBar = legacyAppBar is AppBar ? legacyAppBar : null;
  final legacyActions = <Widget>[
    if (appBar?.leading != null) appBar!.leading!,
    ...?appBar?.actions,
  ];
  final bottom = appBar?.bottom;

  Widget body = source.body ?? const SizedBox.shrink();
  if (bottom != null) {
    body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SafeArea(bottom: false, child: bottom),
        Expanded(child: body),
      ],
    );
  }

  final scaffold = Scaffold(
    key: source.key,
    body: body,
    floatingActionButton: source.floatingActionButton,
    floatingActionButtonLocation: source.floatingActionButtonLocation,
    floatingActionButtonAnimator: source.floatingActionButtonAnimator,
    persistentFooterButtons: source.persistentFooterButtons,
    drawer: source.drawer,
    onDrawerChanged: source.onDrawerChanged,
    endDrawer: source.endDrawer,
    onEndDrawerChanged: source.onEndDrawerChanged,
    bottomNavigationBar: source.bottomNavigationBar,
    bottomSheet: source.bottomSheet,
    backgroundColor: source.backgroundColor,
    resizeToAvoidBottomInset: source.resizeToAvoidBottomInset,
    primary: source.primary,
    drawerDragStartBehavior: source.drawerDragStartBehavior,
    extendBody: source.extendBody,
    extendBodyBehindAppBar: false,
    drawerScrimColor: source.drawerScrimColor,
    drawerEdgeDragWidth: source.drawerEdgeDragWidth,
    drawerEnableOpenDragGesture: source.drawerEnableOpenDragGesture,
    endDrawerEnableOpenDragGesture: source.endDrawerEnableOpenDragGesture,
    restorationId: source.restorationId,
  );

  if (legacyActions.isEmpty) return scaffold;

  return Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(child: scaffold),
      PositionedDirectional(
        top: 12,
        end: 12,
        child: SafeArea(
          minimum: const EdgeInsets.all(4),
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
            elevation: 1,
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Wrap(
                key: const ValueKey('module-inline-actions'),
                spacing: 2,
                runSpacing: 2,
                children: legacyActions,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _FloatingCloseButton extends StatelessWidget {
  const _FloatingCloseButton({required this.onClose});

  final Future<bool> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
      elevation: 1,
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
      child: Tooltip(
        message: context.l10n.isArabic ? 'إغلاق' : 'Close',
        child: InkWell(
          key: const ValueKey('module-page-close'),
          onTap: () => unawaited(onClose()),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.close_rounded,
              size: 21,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
