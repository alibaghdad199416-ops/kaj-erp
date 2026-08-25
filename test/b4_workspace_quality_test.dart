import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_full_page_route.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';

Widget localizedApp(Widget home) => MaterialApp(
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
  testWidgets('module work opens as a full page without taskbar controls', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('open-page'),
            onPressed: () async {
              result = await showAppFullPageRoute<bool>(
                context: context,
                title: 'تحرير المخزون',
                builder: (pageContext) => FilledButton(
                  key: const ValueKey('save-page'),
                  onPressed: () =>
                      AppWorkspaceWindowScope.closeCurrent(pageContext, true),
                  child: const Text('حفظ'),
                ),
              );
            },
            child: const Text('فتح'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-page')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('module-full-page-route')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('workspace-minimize')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-maximize')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('save-page')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
