import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Opens operational module content in one practical, responsive workspace.
///
/// Desktop workspaces intentionally remain bounded instead of taking over the
/// browser viewport. The route owns the only window header and promotes entity
/// actions into that header, while search/filters/statistics stay connected to
/// the business canvas directly below it.
Future<T?> showAppFullPageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  bool barrierDismissible = false,
  double maxWidth = 1320,
  double maxHeight = 840,
  double minWidth = 760,
  double minHeight = 520,
}) {
  FocusManager.instance.primaryFocus?.unfocus();

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel: title ?? 'module-workspace',
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .32),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, _) => _AppWorkspaceDialog<T>(
      title: title,
      builder: builder,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minWidth: minWidth,
      minHeight: minHeight,
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
          scale: Tween<double>(begin: .985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AppWorkspaceDialog<T> extends StatefulWidget {
  const _AppWorkspaceDialog({
    required this.title,
    required this.builder,
    required this.maxWidth,
    required this.maxHeight,
    required this.minWidth,
    required this.minHeight,
  });

  final String? title;
  final WidgetBuilder builder;
  final double maxWidth;
  final double maxHeight;
  final double minWidth;
  final double minHeight;

  @override
  State<_AppWorkspaceDialog<T>> createState() => _AppWorkspaceDialogState<T>();
}

class _AppWorkspaceDialogState<T> extends State<_AppWorkspaceDialog<T>> {
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
                    ? 'توجد بيانات غير محفوظة. هل تريد إغلاق النافذة دون حفظ؟'
                    : 'There are unsaved changes. Close this window without saving?',
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
    final viewport = MediaQuery.sizeOf(context);
    final desktop = viewport.width >= 900;
    final horizontalInset = desktop ? 24.0 : 8.0;
    final verticalInset = desktop ? 20.0 : 8.0;
    final availableWidth = math.max(0.0, viewport.width - horizontalInset * 2);
    final availableHeight = math.max(0.0, viewport.height - verticalInset * 2);
    final requestedMinWidth = math.min(widget.minWidth, availableWidth);
    final requestedMinHeight = math.min(widget.minHeight, availableHeight);
    final width = desktop
        ? math.min(
            math.max(widget.maxWidth, requestedMinWidth),
            availableWidth,
          )
        : availableWidth;
    final height = desktop
        ? math.min(
            math.max(widget.maxHeight, requestedMinHeight),
            availableHeight,
          )
        : availableHeight;

    return PopScope<dynamic>(
      canPop: false,
      onPopInvokedWithResult: _handleSystemBack,
      child: SafeArea(
        minimum: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        child: Center(
          child: Material(
            key: const ValueKey('module-workspace-window'),
            color: Theme.of(context).colorScheme.surface,
            elevation: desktop ? 16 : 4,
            shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: .24),
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(
              desktop ? KajDesignTokens.radiusMd : KajDesignTokens.radiusSm,
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: AppWorkspaceWindowScope(
                windowId: 0,
                title: widget.title?.trim() ?? '',
                close: _close,
                requestClose: _requestClose,
                setDirty: _setDirty,
                isDirty: _dirty,
                child: _PremiumWorkspaceTheme(
                  child: Builder(
                    builder: (workspaceContext) {
                      final presentation = _WorkspacePresentation.from(
                        workspaceContext,
                        widget.builder(workspaceContext),
                        routeTitle: widget.title,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _WorkspaceHeader(
                            title: presentation.title,
                            actions: presentation.headerActions,
                            onClose: _requestClose,
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: .55),
                          ),
                          Expanded(child: presentation.content),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.title,
    required this.actions,
    required this.onClose,
  });

  final String title;
  final List<Widget> actions;
  final Future<bool> Function() onClose;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return SizedBox(
      height: compact ? 54 : 58,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 12 : 18,
          7,
          compact ? 6 : 10,
          7,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: Directionality.of(context) == TextDirection.rtl,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < actions.length; index++) ...[
                        if (index > 0) const SizedBox(width: 6),
                        actions[index],
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            IconButton(
              key: const ValueKey('module-page-close'),
              tooltip: context.l10n.isArabic ? 'إغلاق' : 'Close',
              onPressed: () => unawaited(onClose()),
              icon: const Icon(Icons.close_rounded, size: 21),
            ),
          ],
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
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 13, vertical: 8),
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
            vertical: 11,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _WorkspacePresentation {
  const _WorkspacePresentation({
    required this.title,
    required this.headerActions,
    required this.content,
  });

  final String title;
  final List<Widget> headerActions;
  final Widget content;

  static _WorkspacePresentation from(
    BuildContext context,
    Widget child, {
    String? routeTitle,
  }) {
    String effectiveTitle(String fallback) {
      final explicit = routeTitle?.trim() ?? '';
      return explicit.isNotEmpty ? explicit : fallback.trim();
    }

    if (child is AppEntityPage) {
      return _WorkspacePresentation(
        title: effectiveTitle(child.title),
        headerActions: child.actions,
        content: AppEntityPage(
          key: child.key,
          title: child.title,
          subtitle: child.subtitle,
          body: child.body,
          leading: child.leading,
          actions: const <Widget>[],
          statistics: child.statistics,
          toolbar: child.toolbar,
          sidebar: child.sidebar,
          showBackButton: false,
          maxWidth: child.maxWidth,
          bodyPadding: child.bodyPadding,
          hideHeader: true,
          toolbarFramed: false,
          mergeHiddenHeaderActionsAndStatistics:
              child.mergeHiddenHeaderActionsAndStatistics,
        ),
      );
    }

    if (child is Scaffold) {
      final appBar = child.appBar is AppBar ? child.appBar! as AppBar : null;
      var scaffoldTitle = '';
      if (appBar?.title is Text) {
        scaffoldTitle = ((appBar!.title! as Text).data ?? '').trim();
      }
      return _WorkspacePresentation(
        title: effectiveTitle(scaffoldTitle),
        headerActions: appBar?.actions ?? const <Widget>[],
        content: _scaffoldAsHeaderlessWorkspace(context, child),
      );
    }

    if (child is AlertDialog) {
      var dialogTitle = '';
      if (child.title is Text) {
        dialogTitle = ((child.title! as Text).data ?? '').trim();
      }
      return _WorkspacePresentation(
        title: effectiveTitle(dialogTitle),
        headerActions: child.actions ?? const <Widget>[],
        content: Material(
          color: child.backgroundColor ?? Theme.of(context).colorScheme.surface,
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 20),
            child: child.content ?? const SizedBox.shrink(),
          ),
        ),
      );
    }

    if (child is Dialog && child.child != null) {
      return _WorkspacePresentation(
        title: effectiveTitle(''),
        headerActions: const <Widget>[],
        content: child.child!,
      );
    }

    return _WorkspacePresentation(
      title: effectiveTitle(''),
      headerActions: const <Widget>[],
      content: child,
    );
  }
}

Widget _scaffoldAsHeaderlessWorkspace(BuildContext context, Scaffold source) {
  final legacyAppBar = source.appBar;
  final appBar = legacyAppBar is AppBar ? legacyAppBar : null;
  final bottom = appBar?.bottom;

  Widget body = source.body ?? const SizedBox.shrink();
  if (bottom != null) {
    body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bottom,
        Expanded(child: body),
      ],
    );
  }

  return Scaffold(
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
}
