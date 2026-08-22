import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/widgets/opportunity_card.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class _AllowedAccessController extends AccessController {
  @override
  bool canViewField(String resource, String field, {String? viewPermission}) =>
      true;
}

final _opportunity = OpportunityModel(
  id: 'opportunity-phase4',
  opportunityNumber: 'OPP-2026-000123',
  customerId: 'customer-phase4',
  customerName: 'Quality Line Automotive Long Customer Name',
  customerPhone: '+964 770 123 4567',
  title: 'Premium vehicle fleet opportunity with a deliberately long title',
  source: 'زيارة المعرض',
  expectedValue: 125000,
  currency: 'USD',
  stage: 'proposal',
  probability: 75,
  status: OpportunityStatus.pending,
  carId: 'car-phase4',
  carName: '2026 Premium Vehicle Long Display Name',
  saleId: 'sale-phase4',
  salesOrderNumber: 'SO-2026-00123',
  salesOrderStatus: 'order_approved',
  deliveryNumber: 'SD-2026-00077',
  deliveryStatus: 'delivery_approved',
  invoiceNumber: 'SI-2026-00088',
  invoiceStatus: 'posted',
  paymentStatus: 'partial',
  maintenanceOrderId: 'maintenance-phase4',
  maintenanceOrderNumber: 'MO-2026-00111',
  maintenanceOrderStatus: 'order_approved',
  assignedUserId: 'user-owner',
  assignedUserName: 'Responsible Account Manager Long Name',
  createdByUserId: 'user-creator',
  createdByUserName: 'CRM Administrator Long Name',
  createdAt: DateTime(2026, 8, 18, 8, 30),
  followUpDate: DateTime(2026, 8, 25),
  notes:
      'A concise but deliberately long follow-up note for responsive testing.',
  updatedAt: DateTime(2026, 8, 18, 9, 45),
);

Widget _host({required Locale locale, required double width}) {
  return ChangeNotifierProvider<AccessController>(
    create: (_) => _AllowedAccessController(),
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: OpportunityCard(
                opportunity: _opportunity,
                onEdit: () {},
                onWon: () {},
                onLost: () {},
                onDelete: () {},
                canEdit: true,
                canDelete: true,
                canUpdateStatus: true,
                canCreateSale: true,
                canViewSale: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final locale in const <Locale>[Locale('ar'), Locale('en')]) {
    for (final width in const <double>[560, 1120]) {
      testWidgets(
        'opportunity card has no overflow at $width px in ${locale.languageCode}',
        (tester) async {
          await tester.pumpWidget(_host(locale: locale, width: width));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
