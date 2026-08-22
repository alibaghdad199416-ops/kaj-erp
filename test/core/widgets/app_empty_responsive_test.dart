import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';

Widget _host({required Locale locale, required Widget child}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  for (final locale in const <Locale>[Locale('en'), Locale('ar')]) {
    testWidgets(
      'empty state adapts through bounded heights and keeps action reachable in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(500, 600);
        addTearDown(tester.view.reset);
        var actionCount = 0;

        await tester.pumpWidget(
          _host(
            locale: locale,
            child: AppEmpty(
              title: 'No matching records',
              message: 'Change the filters or create the first record.',
              action: FilledButton(
                key: const ValueKey('empty-action'),
                onPressed: () => actionCount += 1,
                child: const Text('Create record'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final height in const <double>[180, 125.4, 100, 72, 300]) {
          tester.view.physicalSize = Size(500, height);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'AppEmpty overflow at height $height',
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('empty-action')), findsOneWidget);
        }

        tester.view.physicalSize = const Size(500, 100);
        await tester.pump();
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -120),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('empty-action')));
        await tester.pump();
        expect(actionCount, 1);
      },
    );

    testWidgets(
      'title-only and title-message empty states fit short bounds in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 100);
        addTearDown(tester.view.reset);

        for (final message in <String?>[null, 'No data matched the filters.']) {
          await tester.pumpWidget(
            _host(
              locale: locale,
              child: AppEmpty(title: 'No data', message: message),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'AppEntityPage panel keeps its bounded AppEmpty usable in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 420);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            locale: locale,
            child: AppEntityPage(
              title: 'Records',
              hideHeader: true,
              statistics: const SizedBox(height: 150),
              toolbar: const SizedBox(height: 180),
              body: AppEmpty(
                title: 'No records',
                message: 'Create the first record to continue.',
                action: FilledButton(
                  onPressed: () {},
                  child: const Text('Create'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Create'), findsOneWidget);
      },
    );
  }
}
