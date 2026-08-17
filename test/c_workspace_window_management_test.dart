import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_full_page_route.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';

Widget localizedApp(Widget home) => MaterialApp(
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
  testWidgets('dirty module window confirms before close', (tester) async {
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('open-dirty'),
            onPressed: () => showAppFullPageRoute<void>(
              context: context,
              title: 'مسودة فاتورة',
              builder: (windowContext) => Builder(
                builder: (scopedContext) => FilledButton(
                  key: const ValueKey('mark-dirty'),
                  onPressed: () =>
                      AppWorkspaceWindowScope.markDirty(scopedContext, true),
                  child: const Text('تعديل'),
                ),
              ),
            ),
            child: const Text('فتح'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-dirty')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mark-dirty')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('module-page-close')));
    await tester.pumpAndSettle();

    expect(find.text('تغييرات غير محفوظة'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('discard-unsaved-changes')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('module-full-page-route')), findsNothing);
  });
}
