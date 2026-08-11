import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/vehicle_service_card_pdf_service.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/business_partner_profile_dialog.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/cars/pages/vehicle_service_card_page.dart';
import 'package:quality_line_erp/features/maintenance/pages/add_maintenance_order_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = VehicleServiceCardPdfService();
  final fixture = <String, Object?>{
    'vehicle': <String, Object?>{
      'id': '11111111-1111-4111-8111-111111111111',
      'carNumber': 'CAR-R56-1',
      'brand': 'KAJ',
      'model': 'Acceptance',
      'year': 2026,
      'chassis': 'VIN-R56-1',
      'purchasePrice': 987654.32,
      'inventoryValue': 876543.21,
    },
    'maintenanceHistory': <Object?>[
      <String, Object?>{
        'id': '22222222-2222-4222-8222-222222222222',
        'orderNumber': 'MO-R56-1',
        'opportunityNumber': 'OPP-R56-1',
        'maintenanceDate': '2026-08-11T10:30:00Z',
        'workflowStage': 'invoice_approved',
        'currencyCode': 'USD',
        'salePrice': 125,
        'paidAmount': 50,
        'invoiceNumber': 'MINV-R56-1',
        'partsCost': 765432.10,
        'items': <Object?>[
          <String, Object?>{
            'name': 'Customer service',
            'quantity': 1,
            'unitPrice': 125,
            'unitCost': 876543.21,
          },
        ],
      },
    ],
  };

  test('print presentation excludes every internal-cost sentinel', () {
    final presentation = service.buildPresentation(fixture);
    final encoded = jsonEncode(presentation);
    expect(encoded, contains('CAR-R56-1'));
    expect(encoded, contains('MO-R56-1'));
    expect(encoded, contains('125'));
    expect(encoded, isNot(contains('987654.32')));
    expect(encoded, isNot(contains('876543.21')));
    expect(encoded, isNot(contains('765432.1')));
  });

  test('linked opportunity keeps its canonical existing car', () {
    expect(
      resolveInitialMaintenanceVehicle(
        initialCarId: 'car-existing',
        opportunityId: 'opportunity-r56',
        eligibleCarIds: const ['car-first', 'car-existing'],
      ),
      'car-existing',
    );
  });

  test('linked opportunity without car requires explicit selection', () {
    expect(
      resolveInitialMaintenanceVehicle(
        initialCarId: null,
        opportunityId: 'opportunity-r56',
        eligibleCarIds: const ['car-first', 'car-second'],
      ),
      isNull,
    );
  });

  for (final arabic in <bool>[false, true]) {
    test(
      'vehicle service PDF builds in ${arabic ? 'Arabic' : 'English'}',
      () async {
        final bytes = await service.build(card: fixture, arabic: arabic);
        expect(bytes.length, greaterThan(1000));
        expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
      },
    );
  }

  for (final locale in const <Locale>[Locale('ar'), Locale('en')]) {
    for (final width in <double>[390, 760, 1280]) {
      testWidgets(
        'service card is structured and actionable in ${locale.languageCode} at $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var opened = false;
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: VehicleServiceCardPage(
                car: const CarModel(
                  id: 'car-r56',
                  brand: 'Quality',
                  model: 'Line',
                  year: 2026,
                  color: 'Black',
                  chassis: 'VIN-R56',
                  plateNumber: 'R56',
                  carNumber: 'CAR-R56',
                  purchasePrice: 0,
                  salePrice: 0,
                  status: 'sold',
                  imagePath: '',
                ),
                cardLoader: (_) async => fixture,
                onOpenMaintenance: (_) async => opened = true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final maintenanceTile = find.byType(ExpansionTile);
          expect(maintenanceTile, findsOneWidget);
          await tester.tap(maintenanceTile);
          await tester.pumpAndSettle();
          final action = find.byKey(
            const ValueKey(
              'open-maintenance-22222222-2222-4222-8222-222222222222',
            ),
          );
          expect(action, findsOneWidget);
          if (width < 500) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -650),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(action);
          await tester.pump();
          expect(opened, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final partnerType in const <String>['Customer', 'Supplier']) {
    testWidgets('$partnerType 360 related rows invoke real navigation', (
      tester,
    ) async {
      Map<String, Object?>? opened;
      final customer = partnerType == 'Customer';
      final record = <String, Object?>{
        'entityType': customer ? 'sales_invoice' : 'purchases_invoice',
        'id': 'document-r56',
        'parentId': 'order-r56',
        'documentNumber': customer ? 'SINV-R56' : 'PINV-R56',
        'status': 'approved',
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBusinessPartnerProfileDialog(
                context: context,
                title: 'Business Partner',
                accountingSectionTitle: 'Accounting',
                paymentsSectionTitle: 'Payments',
                documentsSectionTitle: 'Documents',
                partnerId: 'partner-r56',
                partnerName: 'R56 Partner',
                partnerType: partnerType,
                icon: Icons.business,
                summary: <String, Object?>{
                  'commercialChain': <Object?>[record],
                  'accountsByCurrency': <Object?>[
                    <String, Object?>{
                      'accountName': 'Partner USD',
                      'currencyCode': 'USD',
                    },
                    <String, Object?>{
                      'accountName': 'Partner IQD',
                      'currencyCode': 'IQD',
                    },
                  ],
                },
                onOpenRecord: (value) async => opened = value,
              ),
              child: const Text('Open profile'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      final row = find.byKey(
        ValueKey(
          'related-${customer ? 'sales_invoice' : 'purchases_invoice'}-document-r56',
        ),
      );
      final profileList = find.byType(ListView).last;
      await tester.scrollUntilVisible(
        row,
        260,
        scrollable: find
            .descendant(of: profileList, matching: find.byType(Scrollable))
            .first,
      );
      expect(row, findsOneWidget);
      final tile = tester.widget<ListTile>(row);
      expect(tile.onTap, isNotNull);
      tile.onTap!();
      await tester.pump();
      expect(opened?['parentId'], 'order-r56');
      expect(tester.takeException(), isNull);
    });
  }
}
