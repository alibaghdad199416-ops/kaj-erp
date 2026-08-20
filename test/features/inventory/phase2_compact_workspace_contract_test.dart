import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phase 2 notification center remains compact and responsive', () {
    final source = File(
      'lib/features/notifications/pages/notification_center_page.dart',
    ).readAsStringSync();

    expect(source, contains('final compact = constraints.maxWidth < 700;'));
    expect(source, contains('margin: const EdgeInsets.only(bottom: 7)'));
    expect(source, contains('class _CompactIconAction'));
    expect(
      source,
      contains("title: ar ? 'لا توجد تنبيهات' : 'No notifications'"),
    );
    expect(source, isNot(contains('vertical: 54')));
  });

  test('warehouse workspace removes duplicate management header chrome', () {
    final source = File(
      'lib/features/inventory/pages/warehouse_management_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('KajInventoryActionBar(')));
    expect(source, contains('const minimumCardWidth = 285.0;'));
    expect(source, contains('.clamp(1, 4)'));
    expect(source, contains('mainAxisExtent: 124'));
    expect(source, contains('class _WarehouseMetricChip'));
  });

  test('inventory cards use compact responsive grid and icon actions', () {
    final page = File(
      'lib/features/inventory/pages/inventory_page.dart',
    ).readAsStringSync();
    final card = File(
      'lib/features/inventory/widgets/inventory_card.dart',
    ).readAsStringSync();

    expect(page, contains('const minimumCardWidth = 330.0;'));
    expect(page, contains('.clamp(1, 4)'));
    expect(page, contains('? 142'));
    expect(card, contains('width: 52'));
    expect(card, contains('BoxConstraints.tightFor(width: 30, height: 30)'));
  });
}
