import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maintenance workspace uses the responsive operational order table', () {
    final source = File(
      'lib/features/maintenance/pages/maintenance_page.dart',
    ).readAsStringSync();

    expect(source, contains('final shellOwnsIdentity'));
    expect(source, contains('constraints.maxWidth >= 900'));
    expect(source, contains('visualDensity: VisualDensity.compact'));
    expect(source, contains('_maintenanceOrdersTable(orders)'));
    expect(source, contains('DataTable('));
    expect(source, contains("'Order number'"));
    expect(source, contains("'Workflow stage'"));
    expect(source, isNot(contains('mainAxisExtent:')));
  });

  test('business partner shell avoids duplicate hero under module top bar', () {
    final source = File(
      'lib/features/business_partners/pages/business_partners_page.dart',
    ).readAsStringSync();

    expect(source, contains('AppWorkspaceChromeScope.hasTopBarOf(context)'));
    expect(source, contains('if (!shellOwnsIdentity)'));
    expect(source, contains('KajRelationshipHero('));
  });

  test('customer and supplier grids use actual width with compact cards', () {
    final customers = File(
      'lib/features/business_partners/customers/pages/customers_page.dart',
    ).readAsStringSync();
    final suppliers = File(
      'lib/features/business_partners/suppliers/pages/suppliers_page.dart',
    ).readAsStringSync();

    for (final source in <String>[customers, suppliers]) {
      expect(source, contains('const minimumCardWidth = 300.0;'));
      expect(source, contains('.clamp(1, 4)'));
      expect(source, contains('mainAxisExtent: 142'));
      expect(source, contains('padding: const EdgeInsets.all(6)'));
    }
  });

  test('partner cards retain readable content within the tighter height', () {
    final customer = File(
      'lib/features/business_partners/customers/widgets/customer_card.dart',
    ).readAsStringSync();
    final supplier = File(
      'lib/features/business_partners/suppliers/widgets/supplier_card.dart',
    ).readAsStringSync();
    final shared = File(
      'lib/features/business_partners/shared/widgets/partner_compact_card_parts.dart',
    ).readAsStringSync();

    for (final source in <String>[customer, supplier]) {
      expect(source, contains('width: 42'));
      expect(source, contains('height: 42'));
      expect(source, contains('maxLines: 2'));
    }
    expect(shared, contains('width: 24'));
    expect(shared, contains('height: 24'));
  });
}
