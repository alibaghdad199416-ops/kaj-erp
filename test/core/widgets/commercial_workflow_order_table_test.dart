import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/commercial_workflow_order_card.dart';
import 'package:quality_line_erp/core/widgets/commercial_workflow_order_table.dart';

void main() {
  testWidgets('commercial order row is the primary details navigation surface', (
    tester,
  ) async {
    Map<String, Object?>? opened;
    final order = <String, Object?>{
      'orderNumber': 'SO-2026-101',
      'effectiveAt': '2026-08-21T10:30:00Z',
      'customerName': 'Customer One',
      'createdByName': 'User One',
      'currency': 'IQD',
      'total': 1234.75,
      'status': 'approved',
    };

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 1500,
            height: 700,
            child: CommercialWorkflowOrderTable(
              orders: <Map<String, Object?>>[order],
              purchase: false,
              actionsBuilder: (_) => const <CommercialWorkflowAction>[],
              onDetails: (value) => opened = value,
              isBusy: (_) => false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Details & Items'), findsNothing);
    expect(find.text('1,235 IQD'), findsOneWidget);

    await tester.tap(find.text('SO-2026-101'));
    await tester.pump();

    expect(opened, same(order));
  });

  testWidgets('busy commercial order row cannot open details', (tester) async {
    var opened = false;
    final order = <String, Object?>{
      'orderNumber': 'PO-2026-200',
      'createdAt': '2026-08-21T10:30:00Z',
      'supplierName': 'Supplier One',
      'createdByName': 'Buyer',
      'currency': 'USD',
      'total': 20,
      'status': 'draft',
    };

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 1500,
            height: 700,
            child: CommercialWorkflowOrderTable(
              orders: <Map<String, Object?>>[order],
              purchase: true,
              actionsBuilder: (_) => const <CommercialWorkflowAction>[],
              onDetails: (_) => opened = true,
              isBusy: (_) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('PO-2026-200'));
    await tester.pump();

    expect(opened, isFalse);
  });
}
