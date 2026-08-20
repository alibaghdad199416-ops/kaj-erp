import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/widgets/app_horizontal_strip.dart';

Widget _host({
  required Locale locale,
  required double width,
  required double height,
  required List<Widget> children,
}) {
  return MaterialApp(
    locale: locale,
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: AppHorizontalStrip(children: children),
        ),
      ),
    ),
  );
}

Widget _button(String label, {Key? key}) => SizedBox(
  key: key,
  width: 110,
  child: OutlinedButton(onPressed: () {}, child: Text(label)),
);

void main() {
  for (final locale in const <Locale>[Locale('en'), Locale('ar')]) {
    testWidgets(
      'short rail stays single-line without overflow on wide desktop in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            locale: locale,
            width: 900,
            height: 200,
            children: <Widget>[_button('Create'), _button('Refresh')],
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Wrap), findsNothing);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(find.text('Create'), findsOneWidget);
        expect(find.text('Refresh'), findsOneWidget);
      },
    );

    testWidgets(
      'dense rail wraps into compact rows on desktop in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            locale: locale,
            width: 1000,
            height: 320,
            children: <Widget>[
              for (var index = 0; index < 8; index++) _button('Item $index'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Wrap), findsOneWidget);
        for (var index = 0; index < 8; index++) {
          expect(find.text('Item $index'), findsOneWidget);
        }

        // Eight 110px controls in a 1000px box must occupy two compact rows
        // instead of forcing horizontal scrolling.
        final first = tester.getTopLeft(find.text('Item 0')).dy;
        final later = tester.getTopLeft(find.text('Item 7')).dy;
        expect(later, greaterThan(first));
      },
    );

    testWidgets(
      'short rail on a narrow window stays reachable without overflow in ${locale.languageCode}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(500, 800);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            locale: locale,
            width: 320,
            height: 420,
            children: <Widget>[
              for (var index = 0; index < 6; index++) _button('Action $index'),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Wrap), findsNothing);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        for (var index = 0; index < 6; index++) {
          expect(find.text('Action $index'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('controls receive the shared compact minimum control height', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        width: 900,
        height: 200,
        children: <Widget>[
          const SizedBox(width: 80, height: 20, child: Text('S')),
          _button('Go'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final stripSize = tester.getSize(find.byType(AppHorizontalStrip));
    expect(stripSize.height, greaterThanOrEqualTo(42));
  });
}
