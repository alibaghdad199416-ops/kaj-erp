import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';

void main() {
  testWidgets('pill tabs fit a 48px embedded app-bar slot at 100 percent zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 0,
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(48),
                child: AppPillTabBar(
                  key: ValueKey('settings-pill-tabs'),
                  tabs: <AppPillTab>[
                    AppPillTab('Users', Icons.people_outline),
                    AppPillTab('Permissions', Icons.security_outlined),
                    AppPillTab('Audit Log', Icons.history),
                  ],
                ),
              ),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final size = tester.getSize(
      find.byKey(const ValueKey('settings-pill-tabs')),
    );
    expect(size.height, lessThanOrEqualTo(48));
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Audit Log'), findsOneWidget);
  });
}
