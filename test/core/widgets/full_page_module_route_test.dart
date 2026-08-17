import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_floating_window.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';

MaterialApp _app(Widget home) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

void main() {
  testWidgets(
    'module content uses full viewport close-only chrome',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool? result;
      var actionTapped = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open-module-window'),
                  onPressed: () async {
                    result = await showAppFloatingWindow<bool>(
                      context: context,
                      title: 'عنوان داخلي لا يظهر كرأس نافذة',
                      maxWidth: 900,
                      maxHeight: 650,
                      builder: (windowContext) => Scaffold(
                        appBar: AppBar(
                          title: const Text('عنوان AppBar قديم لا يظهر'),
                          actions: [
                            IconButton(
                              key: const ValueKey('inline-appbar-action'),
                              onPressed: () => actionTapped = true,
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        body: Center(
                          child: FilledButton(
                            key: const ValueKey('save-module-window'),
                            onPressed: () =>
                                AppWorkspaceWindowScope.closeCurrent(
                                  windowContext,
                                  true,
                                ),
                            child: const Text('حفظ'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('فتح'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-module-window')));
      await tester.pumpAndSettle();

      final panel = find.byKey(const ValueKey('module-full-page-route'));
      expect(panel, findsOneWidget);
      expect(
        find.byKey(const ValueKey('module-window-move-surface')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('module-window-resize-corner')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('module-page-close')), findsOneWidget);
      expect(find.byKey(const ValueKey('module-page-back')), findsNothing);
      expect(find.byKey(const ValueKey('module-window-shrink')), findsNothing);
      expect(find.byKey(const ValueKey('module-window-grow')), findsNothing);
      expect(
        find.byKey(const ValueKey('module-window-maximize')),
        findsNothing,
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('عنوان داخلي لا يظهر كرأس نافذة'), findsNothing);
      expect(find.text('عنوان AppBar قديم لا يظهر'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inline-appbar-action')),
        findsOneWidget,
      );

      final size = tester.getSize(panel);
      final topLeft = tester.getTopLeft(panel);
      expect(size.width, 1400);
      expect(size.height, 900);
      expect(topLeft, Offset.zero);

      await tester.tap(find.byKey(const ValueKey('inline-appbar-action')));
      await tester.pump();
      expect(actionTapped, isTrue);

      await tester.tap(find.byKey(const ValueKey('save-module-window')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(panel, findsNothing);
    },
  );

  testWidgets(
    'AlertDialog title and actions remain full viewport content',
    (tester) async {
      bool? closed;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const ValueKey('open-alert-window'),
                onPressed: () async {
                  closed = await showAppFloatingWindow<bool>(
                    context: context,
                    builder: (windowContext) => AlertDialog(
                      title: const Text('بيانات المستخدم'),
                      content: const Text('محتوى النافذة'),
                      actions: [
                        TextButton(
                          key: const ValueKey('legacy-dialog-save'),
                          onPressed: () => Navigator.pop(windowContext, true),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-alert-window')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('module-page-close')), findsOneWidget);
      expect(find.text('بيانات المستخدم'), findsOneWidget);
      expect(find.text('محتوى النافذة'), findsOneWidget);
      final actionTop = tester
          .getTopLeft(find.byKey(const ValueKey('legacy-dialog-save')))
          .dy;
      final contentTop = tester.getTopLeft(find.text('محتوى النافذة')).dy;
      expect(actionTop, greaterThan(contentTop));

      await tester.tap(find.byKey(const ValueKey('legacy-dialog-save')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    },
  );
}
