import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/business_partners/customers/widgets/customer_card.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/widgets/supplier_card.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class _AllowedAccessController extends AccessController {
  @override
  bool canViewField(String resource, String field, {String? viewPermission}) =>
      true;
}

Widget _host(Widget child, Locale locale) =>
    ChangeNotifierProvider<AccessController>(
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
          body: Center(child: SizedBox(width: 280, height: 142, child: child)),
        ),
      ),
    );

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets(
      'customer actions stay within a narrow card in ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(
          _host(
            CustomerCard(
              customer: const CustomerModel(
                id: 'customer',
                name: 'A deliberately long customer business name',
                phone: '+964 770 123 4567',
                address: 'A deliberately long business address',
                nationalId: '123456789012345',
                notes: '',
                createdAt: '2026-08-11T00:00:00Z',
              ),
              onView: () {},
              onEdit: () {},
              onDelete: () {},
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'supplier actions stay within a narrow card in ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(
          _host(
            SupplierCard(
              supplier: SupplierModel(
                id: 'supplier',
                name: 'A deliberately long supplier business name',
                phone: '+964 770 123 4567',
                address: 'A deliberately long business address',
                companyName: 'Quality Line Automotive Trading Company',
                openingBalance: 125000,
                currency: 'IQD',
                createdAt: DateTime.utc(2026, 8, 11),
              ),
              onView: () {},
              onEdit: () {},
              onDelete: () {},
              onToggleStatus: () {},
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
