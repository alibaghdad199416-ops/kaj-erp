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
  testWidgets('full-page form closes before navigating to another module', (
    tester,
  ) async {
    final module = ValueNotifier<String>('السيارات');
    await tester.pumpWidget(
      localizedApp(
        ValueListenableBuilder<String>(
          valueListenable: module,
          builder: (context, value, _) => Column(
            children: [
              Text(value),
              FilledButton(
                key: const ValueKey('open-vehicle'),
                onPressed: () => showAppFullPageRoute<void>(
                  context: context,
                  title: 'إضافة سيارة',
                  builder: (pageContext) => FilledButton(
                    key: const ValueKey('finish'),
                    onPressed: () =>
                        AppWorkspaceWindowScope.closeCurrent(pageContext),
                    child: const Text('حفظ'),
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
    await tester.tap(find.byKey(const ValueKey('open-vehicle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finish')));
    await tester.pumpAndSettle();
    module.value = 'الصيانة';
    await tester.pumpAndSettle();
    expect(find.text('الصيانة'), findsOneWidget);
  });
}
