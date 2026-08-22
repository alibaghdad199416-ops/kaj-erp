import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/design_system/kaj_phase6_components.dart';
import 'package:quality_line_erp/features/settings/recycle_bin/models/recycle_bin_item.dart';

void main() {
  test(
    'legacy executive hero remains test-only after root density closure',
    () {
      const hero = KajExecutiveHero(
        eyebrow: 'Legacy',
        title: 'Legacy',
        subtitle: 'Legacy',
        icon: Icons.account_balance_outlined,
        metrics: <KajExecutiveMetricData>[],
      );
      expect(hero.metrics, isEmpty);
    },
  );

  test('recycle title resolver is entity-aware and fields stay structured', () {
    final item = RecycleBinItem.fromMap(<String, dynamic>{
      'entity_type': 'erp_sales_orders_cloud',
      'record_id': 'opaque-id',
      'payload': <String, Object?>{
        'name': 'Wrong generic name',
        'orderNumber': 'SO-57001',
        'status': 'draft',
      },
    });
    expect(item.title, 'SO-57001');
    expect(item.meaningfulFields.map((field) => field.key), contains('status'));
  });
}
