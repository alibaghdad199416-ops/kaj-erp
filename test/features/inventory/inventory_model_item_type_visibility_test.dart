import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';

void main() {
  group('InventoryModel persisted itemType visibility', () {
    Map<String, dynamic> baseRow() => <String, dynamic>{
      'id': 'inventory-runtime-test',
      'name': 'Test item',
      'code': 'ITM-1',
      'serialNumber': '',
      'category': 'General',
      'groupId': 'inventory-group-general',
      'unit': 'pcs',
      'quantity': 0,
      'purchasePrice': 0,
      'landedCost': 0,
      'unitCost': 0,
      'salePrice': 0,
      'currency': 'IQD',
      'taxRate': 0,
      'minQuantity': 0,
      'expectedIncoming': 0,
      'expectedOutgoing': 0,
      'date': '',
      'isActive': true,
    };

    test('missing persisted itemType never silently becomes stock', () {
      final item = InventoryModel.fromMap(baseRow());

      expect(item.itemType, isEmpty);
      expect(item.isStockItem, isFalse);
      expect(item.isService, isFalse);
    });

    test('explicit snake_case service type remains service', () {
      final row = baseRow()..['item_type'] = 'SERVICE';
      final item = InventoryModel.fromMap(row);

      expect(item.itemType, 'service');
      expect(item.isService, isTrue);
      expect(item.isStockItem, isFalse);
    });

    test('explicit stock type remains stock', () {
      final row = baseRow()..['itemType'] = 'stock';
      final item = InventoryModel.fromMap(row);

      expect(item.itemType, 'stock');
      expect(item.isStockItem, isTrue);
    });
  });
}
