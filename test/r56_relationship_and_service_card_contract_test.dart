import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'R56 opportunity action and repository share canonical RPC contract',
    () {
      final opportunity = File(
        'lib/features/customer_service/pages/add_opportunity_page.dart',
      ).readAsStringSync();
      final repository = File(
        'lib/features/maintenance/data/maintenance_repository.dart',
      ).readAsStringSync();
      expect(opportunity, contains('Save & Create Maintenance Draft'));
      expect(opportunity, contains('findByOpportunity(item.id)'));
      expect(repository, contains('erp_r56_find_maintenance_by_opportunity'));
      expect(repository, contains('erp_r56_create_cloud_maintenance_order'));
    },
  );

  test('vehicle service PDF model cannot receive internal vehicle values', () {
    final source = File(
      'lib/core/printing/vehicle_service_card_pdf_service.dart',
    ).readAsStringSync();
    for (final forbidden in <String>[
      'purchasePrice',
      'acquisitionCost',
      'unitCost',
      'partsCost',
      'laborCost',
      'totalCost',
      'profit',
      'carCostAdded',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains("card['maintenanceHistory']"));
    expect(source, contains("order['salePrice']"));
  });

  test('business partner shared path loads R56 360 once', () {
    final source = File(
      'lib/features/business_partners/shared/data/business_partner_card_service.dart',
    ).readAsStringSync();
    expect('erp_r56_business_partner_360'.allMatches(source), hasLength(1));
  });
}
