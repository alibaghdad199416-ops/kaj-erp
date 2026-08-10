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
  testWidgets('closing full-page work restores the underlying module', (
    tester,
  ) async {
    final module = ValueNotifier<String>('المحاسبة');
    await tester.pumpWidget(
      localizedApp(
        ValueListenableBuilder<String>(
          valueListenable: module,
          builder: (context, value, _) => Column(
            children: [
              Text(value),
              FilledButton(
                key: const ValueKey('open-form'),
                onPressed: () => showAppFullPageRoute<void>(
                  context: context,
                  title: 'تحرير قيد',
                  builder: (pageContext) => TextField(
                    key: const ValueKey('draft'),
                    onSubmitted: (_) =>
                        AppWorkspaceWindowScope.closeCurrent(pageContext),
                  ),
                ),
                child: const Text('فتح'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-form')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('draft')), 'مسودة');
    expect(find.byKey(const ValueKey('workspace-minimize')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('module-page-close')));
    await tester.pumpAndSettle();
    module.value = 'المخزون';
    await tester.pumpAndSettle();
    expect(find.text('المخزون'), findsOneWidget);
    expect(find.byKey(const ValueKey('draft')), findsNothing);
  });
}
