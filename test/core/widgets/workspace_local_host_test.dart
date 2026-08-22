import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_full_page_route.dart';

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
  testWidgets('legacy Navigator.pop result closes the bounded workspace', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => FilledButton(
            key: const ValueKey('open-pop'),
            onPressed: () async {
              result = await showAppFullPageRoute<bool>(
                context: context,
                builder: (pageContext) => FilledButton(
                  key: const ValueKey('pop-result'),
                  onPressed: () => Navigator.pop(pageContext, true),
                  child: const Text('إكمال'),
                ),
              );
            },
            child: const Text('فتح'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-pop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pop-result')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byKey(const ValueKey('module-workspace-window')), findsNothing);
  });
}
