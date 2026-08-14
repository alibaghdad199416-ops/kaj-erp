import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';

void main() {
  test('commercial order details defensively converts RPC payloads', () {
    final details = CommercialOrderDetails.fromRpc(<String, Object?>{
      'order': <String, Object?>{'id': 'order-1'},
      'items': <Object?>[
        <String, Object?>{'id': 'item-1'},
        'ignored',
      ],
      'journalEntries': <Object?>[
        <String, Object?>{'id': 'journal-1'},
      ],
      'reconciliation': <Object?>[
        <String, Object?>{'orderedQuantity': 7, 'executedQuantity': 3},
      ],
    });

    expect(details.order?['id'], 'order-1');
    expect(details.items, hasLength(1));
    expect(details.items.single['id'], 'item-1');
    expect(details.journalEntries.single['id'], 'journal-1');
    expect(details.reconciliation.single['executedQuantity'], 3);
    expect(details.payments, isEmpty);
    expect(details.auditTrail, isEmpty);
  });

  test('commercial order details accepts empty or malformed payloads', () {
    final details = CommercialOrderDetails.fromRpc('invalid');

    expect(details.order, isNull);
    expect(details.items, isEmpty);
    expect(details.logistics, isEmpty);
    expect(details.invoices, isEmpty);
    expect(details.payments, isEmpty);
    expect(details.movements, isEmpty);
    expect(details.journalEntries, isEmpty);
    expect(details.auditTrail, isEmpty);
  });
}
