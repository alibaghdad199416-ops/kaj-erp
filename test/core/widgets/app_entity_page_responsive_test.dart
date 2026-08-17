import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
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

Widget _highRiskPage({
  required bool hideHeader,
  required bool toolbarFramed,
  bool withSidebar = false,
}) {
  final page = AppEntityPage(
    title: 'Entity management',
    subtitle: 'A deliberately descriptive subtitle for responsive coverage.',
    hideHeader: hideHeader,
    toolbarFramed: toolbarFramed,
    actions: <Widget>[
      FilledButton(onPressed: () {}, child: const Text('Create')),
      OutlinedButton(onPressed: () {}, child: const Text('Refresh')),
      OutlinedButton(onPressed: () {}, child: const Text('Export')),
    ],
    statistics: const SizedBox(
      height: 220,
      child: ColoredBox(
        color: Color(0x1100AEEF),
        child: Center(child: Text('Statistics')),
      ),
    ),
    toolbar: const SizedBox(
      height: 360,
      child: ColoredBox(
        color: Color(0x11FFB000),
        child: Center(child: Text('Toolbar controls')),
      ),
    ),
    sidebar: withSidebar
        ? const SizedBox(
            width: 160,
            child: ColoredBox(color: Color(0x1100FF00)),
          )
        : null,
    body: ListView.builder(
      key: const ValueKey('bounded-entity-body'),
      itemCount: 30,
      itemBuilder: (context, index) => ListTile(title: Text('Row $index')),
    ),
  );
  return page;
}

void main() {
  for (final locale in const <Locale>[Locale('en'), Locale('ar')]) {
    testWidgets(
      'entity page keeps chrome reachable and body bounded through short-height resize in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1440, 900);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            locale: locale,
            child: _highRiskPage(
              hideHeader: false,
              toolbarFramed: true,
              withSidebar: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        for (final size in const <Size>[
          Size(1024, 768),
          Size(1024, 650),
          Size(800, 616),
          Size(720, 500),
          Size(1024, 768),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'AppEntityPage overflow at ${size.width}x${size.height}',
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        }

        final bodySize = tester.getSize(
          find.byKey(const ValueKey('bounded-entity-body')),
        );
        expect(bodySize.height, greaterThan(0));
        expect(bodySize.height, lessThan(768));
      },
    );

    testWidgets(
      'hidden unframed entity chrome remains reachable at 800x600 in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 600);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            locale: locale,
            child: _highRiskPage(hideHeader: true, toolbarFramed: false),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('app-entity-page-short-height-scroll')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'entity toolbar receives finite width for flex filters at normal and short heights',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 820);
      addTearDown(tester.view.reset);

      var sawUnboundedWidth = false;
      final page = AppEntityPage(
        title: 'Bounded toolbar regression',
        hideHeader: true,
        actions: <Widget>[
          FilledButton(onPressed: () {}, child: const Text('Create')),
        ],
        toolbar: LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth) sawUnboundedWidth = true;
            return Row(
              key: const ValueKey('width-sensitive-toolbar'),
              children: <Widget>[
                const Expanded(
                  child: TextField(
                    decoration: InputDecoration(hintText: 'Search'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Filter'),
                  ),
                ),
              ],
            );
          },
        ),
        body: ListView.builder(
          key: const ValueKey('bounded-filter-body'),
          itemCount: 20,
          itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
        ),
      );

      await tester.pumpWidget(_host(locale: const Locale('en'), child: page));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(sawUnboundedWidth, isFalse);
      expect(
        find.byKey(const ValueKey('module-bounded-toolbar')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('width-sensitive-toolbar')))
            .width,
        greaterThan(0),
      );

      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(sawUnboundedWidth, isFalse);
      expect(
        find.byKey(const ValueKey('app-entity-page-short-height-scroll')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('bounded-filter-body')))
            .height,
        greaterThan(0),
      );
    },
  );
}
