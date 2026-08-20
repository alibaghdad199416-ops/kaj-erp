import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_snapshot.dart';

void main() {
  test(
    'snapshot keeps quantities, warehouses, billing, FIFO and payments distinct',
    () {
      final snapshot = MaintenanceOrderSnapshot.fromRpc(<String, Object?>{
        'snapshotAt': '2026-08-14T04:51:03.123456Z',
        'order': <String, Object?>{
          'id': '64000000-0000-4000-8000-000000000001',
          'orderNumber': 'MO-R64-001',
          'carId': 'car-1',
          'carName': 'Vehicle 101',
          'warehouseId': 'BGW',
          'pricingType': 'paid',
          'status': 'approved',
          'currencyCode': 'usd',
          'workflowStage': 'invoice_approved',
          'salePrice': 1800.125,
          'paidAmount': 1500.125,
          'maintenanceDate': '2026-08-14T01:30:00Z',
        },
        'lines': <Object?>[
          <String, Object?>{
            'id': 'line-1',
            'productId': 'P-101',
            'productName': 'Brake pad',
            'warehouseId': 'BGW',
            'warehouseName': 'Baghdad',
            'quantity': 7,
            'unitCost': 10.25,
            'unitPrice': 30.5,
            'lineType': 'stock',
          },
        ],
        'reconciliation': <String, Object?>{
          'currency': 'USD',
          'workflowStage': 'invoice_approved',
          'hasApprovedInvoice': true,
          'requestedMaterialsCost': 71.75,
          'issuedMaterialsActualCost': 62.5,
          'laborCost': 100,
          'totalOperationalCost': 162.5,
          'materialsInvoiced': 213.5,
          'laborInvoiced': 1586.625,
          'servicesInvoiced': 0,
          'totalInvoiced': 1800.125,
          'paid': 1500.125,
          'outstanding': 300,
          'lines': <Object?>[
            <String, Object?>{
              'lineId': 'line-1',
              'requestedQuantity': 7,
              'issuedQuantity': 0,
              'invoicedQuantity': 7,
              'unitInvoiceValue': 30.5,
              'issuedActualCost': 0,
            },
          ],
        },
        'issueState': <String, Object?>{
          'issuedMaterialsActualCost': 62.5,
          'lines': <Object?>[
            <String, Object?>{
              'lineId': 'line-1',
              'requestedQuantity': 7,
              'issuedQuantity': 7,
              'remainingQuantity': 0,
              'issuedActualCost': 62.5,
            },
          ],
          'warehouses': <Object?>[
            <String, Object?>{'warehouseId': 'BGW', 'issuedQuantity': 3},
            <String, Object?>{'warehouseId': 'EBL', 'issuedQuantity': 4},
          ],
          'events': <Object?>[
            <String, Object?>{
              'issueId': 'issue-bgw',
              'lineId': 'line-1',
              'warehouseId': 'BGW',
              'quantity': 3,
              'status': 'executed',
            },
            <String, Object?>{
              'issueId': 'issue-ebl',
              'lineId': 'line-1',
              'warehouseId': 'EBL',
              'quantity': 4,
              'status': 'executed',
            },
          ],
        },
      });

      expect(snapshot.order.currencyCode, 'USD');
      expect(
        snapshot.snapshotAt,
        DateTime.utc(2026, 8, 14, 4, 51, 3, 123, 456),
      );
      expect(snapshot.lines.single.productId, 'P-101');
      expect(snapshot.reconciliation.lines.single['requestedQuantity'], 7);
      expect(snapshot.reconciliation.lines.single['issuedQuantity'], 7);
      expect(snapshot.reconciliation.lines.single['remainingQuantity'], 0);
      expect(snapshot.reconciliation.warehouses, hasLength(2));
      expect(
        snapshot.reconciliation.warehouses.map((row) => row['warehouseId']),
        ['BGW', 'EBL'],
      );
      expect(snapshot.reconciliation.issueEvents, hasLength(2));
      expect(snapshot.reconciliation.issuedMaterialsActualCost, 62.5);
      expect(snapshot.reconciliation.materialsInvoiced, 213.5);
      expect(snapshot.reconciliation.materialsInvoiced, isNot(62.5));
      expect(snapshot.reconciliation.totalInvoiced, 1800.125);
      expect(snapshot.reconciliation.paid, 1500.125);
      expect(snapshot.reconciliation.outstanding, 300);
    },
  );

  test(
    'snapshot rejects missing authoritative sections instead of erasing order data',
    () {
      expect(
        () => MaintenanceOrderSnapshot.fromRpc(<String, Object?>{
          'order': <String, Object?>{'id': 'order-1'},
          'lines': const <Object?>[],
        }),
        throwsStateError,
      );
    },
  );

  test('maintenance details authoritative refresh uses one snapshot call', () {
    final dialog = File(
      'lib/features/maintenance/pages/maintenance_order_details_dialog.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/maintenance/data/maintenance_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260814045103_r64_maintenance_authoritative_snapshot.sql',
    ).readAsStringSync();

    expect(dialog, contains('await _repository.getOrderSnapshot(_order.id)'));
    expect(dialog, isNot(contains('Future.wait<Object>')));
    expect(dialog, isNot(contains('_loadDetailsRich')));
    expect(repository, contains("'erp_r90_get_maintenance_order_snapshot'"));
    expect(migration, contains('erp_r57_maintenance_cost_reconciliation'));
    expect(migration, contains('erp_r57_maintenance_material_issue_state'));
    expect(migration, contains('erp_r9_get_cloud_maintenance_order_lines'));
    expect(migration, contains("'maintenance.view'"));
  });
}
