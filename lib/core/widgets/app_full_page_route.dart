import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Opens operational module content as a true full-viewport workspace.
///
/// The legacy size arguments remain in the API for source compatibility, but
/// operational workspaces no longer render as centered/resizable boxes. This
/// keeps modules usable at 100% browser zoom and removes the duplicated outer
/// window header while preserving close/dirty-state semantics.
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
    transitionDuration: const Duration(milliseconds: 180),
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
                // Keep close access outside the module's own AppBar/action area.
                // `start` is intentionally opposite Material's usual end-aligned
                // FAB/action placement in both LTR and RTL layouts.
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

Widget _normalizeFullViewportContent(BuildContext context, Widget child) {
  if (child is AppEntityPage || child is Scaffold) return child;

  if (child is AlertDialog) {
    final actions = child.actions ?? const <Widget>[];
    return Material(
      color: child.backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (child.title != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 72, 8),
              child: DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                child: child.title!,
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 24, 24),
              child: child.content ?? const SizedBox.shrink(),
            ),
          ),
          if (actions.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 20),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: actions,
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

class _FloatingCloseButton extends StatelessWidget {
  const _FloatingCloseButton({required this.onClose});

  final Future<bool> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
      elevation: 2,
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
      child: Tooltip(
        message: context.l10n.isArabic ? 'إغلاق' : 'Close',
        child: InkWell(
          key: const ValueKey('module-page-close'),
          onTap: () => unawaited(onClose()),
          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
          child: SizedBox(
            width: 42,
            height: 42,
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
