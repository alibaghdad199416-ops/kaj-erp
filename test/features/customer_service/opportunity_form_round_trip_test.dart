import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/pages/add_opportunity_page.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/models/user_model.dart';

const _customer = CustomerModel(
  id: 'customer-r49',
  name: 'R49 Customer',
  phone: '07700000000',
  address: '',
  nationalId: '',
  notes: '',
  createdAt: '2026-08-10T10:00:00.000Z',
);

final _user = UserModel(
  id: 'user-r49',
  username: 'r49-admin',
  fullName: 'R49 Admin',
  email: 'r49@example.test',
  phone: '',
  roleId: 'role-admin',
  roleName: 'Administrator',
  passwordHash: '',
  isActive: true,
  createdAt: _createdAt,
);

final _createdAt = DateTime.utc(2026, 8, 10, 10);

class _AllowedAccessController extends AccessController {
  @override
  UserModel get currentUser => _user;

  @override
  List<UserModel> get users => [_user];

  @override
  bool hasPermission(String code) => true;

  @override
  bool canViewField(String resource, String field, {String? viewPermission}) =>
      true;

  @override
  bool canEditField(
    String resource,
    String field, {
    String? writePermission,
    String? viewPermission,
  }) => true;
}

class _SeededCustomersController extends CustomersController {
  @override
  List<CustomerModel> get customers => const [_customer];
}

class _CapturingOpportunitiesController extends OpportunitiesController {
  OpportunityModel? submitted;

  @override
  Future<void> add(OpportunityModel item) async => submitted = item;

  @override
  Future<void> update(OpportunityModel item) async => submitted = item;
}

Widget _app({
  required OpportunitiesController opportunities,
  OpportunityModel? opportunity,
  Locale locale = const Locale('en'),
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AccessController>(
      create: (_) => _AllowedAccessController(),
    ),
    ChangeNotifierProvider<CustomersController>(
      create: (_) => _SeededCustomersController(),
    ),
    ChangeNotifierProvider<OpportunitiesController>.value(value: opportunities),
  ],
  child: MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: AddOpportunityPage(
      key: ValueKey(opportunity?.id ?? 'new-opportunity'),
      opportunity: opportunity,
    ),
  ),
);

void main() {
  testWidgets(
    'actual opportunity form preserves 1234.56 USD through submit and edit',
    (tester) async {
      final controller = _CapturingOpportunitiesController();
      await tester.pumpWidget(_app(opportunities: controller));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, _customer.name);
      final valueField = find.byKey(
        const ValueKey('opportunity-expected-value-field'),
      );
      await tester.scrollUntilVisible(
        valueField,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(valueField, '1234.56');
      final save = find.byKey(const ValueKey('opportunity-save-button'));
      await tester.scrollUntilVisible(
        save,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();

      final submitted = controller.submitted;
      expect(submitted, isNotNull);
      expect(submitted!.expectedValue, 1234.56);
      expect(submitted.currency, 'USD');

      final repositoryPayload = submitted.toMap();
      expect(repositoryPayload['expectedValue'], 1234.56);
      expect(repositoryPayload['currency'], 'USD');
      final readBack = OpportunityModel.fromMap(repositoryPayload);

      await tester.pumpWidget(
        _app(opportunities: controller, opportunity: readBack),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('opportunity-expected-value-field')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final editField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('opportunity-expected-value-field')),
      );
      expect(editField.controller!.text, '1234.56');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('opportunity-currency-field')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      final currency = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('opportunity-currency-field')),
      );
      expect(currency.initialValue, 'USD');
    },
  );

  testWidgets('actual edit form renders zero IQD in Arabic RTL', (
    tester,
  ) async {
    final controller = _CapturingOpportunitiesController();
    final row = OpportunityModel.fromMap({
      'id': 'opportunity-zero',
      'opportunityNumber': 'OPP0002',
      'customerId': _customer.id,
      'customerName': _customer.name,
      'customerPhone': _customer.phone,
      'title': '',
      'source': '',
      'expectedValue': '0',
      'currency': 'IQD',
      'stage': 'new',
      'probability': 0,
      'status': 'pending',
      'assignedUserId': _user.id,
      'assignedUserName': _user.fullName,
      'createdByUserId': _user.id,
      'createdByUserName': _user.fullName,
      'createdAt': _createdAt.toIso8601String(),
    });

    await tester.pumpWidget(
      _app(
        opportunities: controller,
        opportunity: row,
        locale: const Locale('ar'),
      ),
    );
    await tester.pumpAndSettle();

    final value = tester.widget<TextFormField>(
      find.byKey(const ValueKey('opportunity-expected-value-field')),
    );
    expect(value.controller!.text, '0.0');
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
