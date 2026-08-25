import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flutter rendering and Arabic direction smoke test', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Text('خط الجودة')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('خط الجودة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
