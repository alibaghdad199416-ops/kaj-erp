import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/accounting/models/journal_entry_model.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_movement_model.dart';

void main() {
  test('journal exposes its source type and linked record together', () {
    final journal = JournalEntryModel.fromMap({
      'id': 'journal-1',
      'entryNumber': 'JE-0042',
      'entryDate': '2026-08-11T10:00:00Z',
      'description': 'Sales inventory cost',
      'currency': 'USD',
      'referenceType': 'sales_invoice_cost',
      'referenceId': 'invoice-42',
      'totalDebit': 175,
      'totalCredit': 175,
      'status': 'posted',
      'createdAt': '2026-08-11T10:00:00Z',
    });

    expect(journal.sourceReferenceLabel, 'sales_invoice_cost • invoice-42');
  });

  test(
    'movement retains product identity, source reference, cost and currency',
    () {
      final movement = InventoryMovementModel.fromMap({
        'id': 'movement-1',
        'productId': 'product-1',
        'movementNumber': 'MV-0042',
        'productName': 'Brake pad',
        'productCode': 'PRD0042',
        'warehouseName': 'Main warehouse',
        'movementType': 'sale_out',
        'quantity': -2,
        'unitCost': 15,
        'totalCost': 30,
        'currency': 'usd',
        'movementDate': '2026-08-11T10:00:00Z',
        'referenceType': 'sales_delivery',
        'referenceId': 'delivery-id',
        'referenceDocumentNumber': 'SD-0042',
        'sourceName': 'Main warehouse',
        'destinationName': 'Customer A',
      });

      expect(movement.productId, 'product-1');
      expect(movement.productCode, 'PRD0042');
      expect(movement.referenceDocumentNumber, 'SD-0042');
      expect(movement.currency, 'USD');
      expect(movement.totalCost, 30);
    },
  );

  group('vehicle current inventory value eligibility', () {
    CarModel car(String status, {String? warehouseId = 'warehouse-1'}) =>
        CarModel(
          id: 'car-1',
          brand: 'Toyota',
          model: 'Land Cruiser',
          year: 2026,
          color: 'White',
          chassis: 'VIN-1',
          plateNumber: '',
          purchasePrice: 40000,
          salePrice: 45000,
          status: status,
          imagePath: '',
          warehouseId: warehouseId,
          currency: 'USD',
        );

    test('includes only in-stock available or reserved-for-sale vehicles', () {
      expect(car('available').isIncludedInCurrentInventoryValue, isTrue);
      expect(car('selling').isIncludedInCurrentInventoryValue, isTrue);
      expect(car('purchasing').isIncludedInCurrentInventoryValue, isFalse);
      expect(car('defined').isIncludedInCurrentInventoryValue, isFalse);
      expect(car('damaged').isIncludedInCurrentInventoryValue, isFalse);
      expect(car('sold').isIncludedInCurrentInventoryValue, isFalse);
      expect(
        car('available', warehouseId: null).isIncludedInCurrentInventoryValue,
        isFalse,
      );
    });
  });
}
