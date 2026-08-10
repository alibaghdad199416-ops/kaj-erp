import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';

void main() {
  group('vehicle runtime aliases', () {
    test('writes normalized and compatibility aliases with equal values', () {
      const car = CarModel(
        id: 'car-1',
        vehicleType: 'SUV',
        brand: 'Toyota',
        model: 'Land Cruiser',
        year: 2026,
        color: 'Black',
        chassis: 'JT123456789012345',
        plateNumber: '12345 بغداد',
        carNumber: 'CAR-100',
        purchasePrice: 50000,
        salePrice: 55000,
        currency: 'USD',
        costCurrency: 'IQD',
        saleCurrency: 'USD',
        status: 'متوفرة',
        imagePath: 'cars/car-1.jpg',
        warehouseId: 'warehouse-1',
      );

      final map = car.toCloudMap();
      expect(map['plate_number'], map['plateNumber']);
      expect(map['plate_number'], map['plate']);
      expect(map['chassis'], map['vin']);
      expect(map['purchase_price'], map['purchasePrice']);
      expect(map['sale_price'], map['salePrice']);
      expect(map['warehouse_id'], map['warehouseId']);
      expect(map['cost_currency'], 'IQD');
      expect(map['sale_currency'], 'USD');
      expect(map['schema_version'], 4);
    });

    test('reads historical camelCase and normalized snake_case records', () {
      final camelCase = CarModel.fromCloudMap({
        'id': 'car-camel',
        'vehicleType': 'Sedan',
        'make': 'Kia',
        'model': 'K5',
        'year': 2025,
        'color': 'White',
        'vin': 'KN123456789012345',
        'plateNumber': 'A-100',
        'purchasePrice': 20000,
        'salePrice': 23000,
        'currency': 'USD',
        'status': 'available',
        'imagePath': '',
      });
      final snakeCase = CarModel.fromCloudMap({
        'id': 'car-snake',
        'vehicle_type': 'Pickup',
        'brand': 'Ford',
        'model': 'Ranger',
        'year': 2024,
        'color': 'Blue',
        'chassis_number': 'FR123456789012345',
        'car_number': 'CAR-200',
        'purchase_price': 30000,
        'sale_price': 34000,
        'currency': 'USD',
        'status': 'available',
        'image_path': '',
      });

      expect(camelCase.brand, 'Kia');
      expect(camelCase.plateNumber, 'A-100');
      expect(snakeCase.vehicleType, 'Pickup');
      expect(snakeCase.carNumber, 'CAR-200');
    });

    test('accepts vehicle without plate or internal vehicle number', () {
      const car = CarModel(
        id: 'car-number-only',
        brand: 'Toyota',
        model: 'Hilux',
        year: 2025,
        color: 'White',
        chassis: 'HL123456789012345',
        plateNumber: '',
        carNumber: '',
        purchasePrice: 25000,
        salePrice: 28000,
        currency: 'USD',
        status: 'متوفرة',
        imagePath: '',
      );

      expect(car.validate, returnsNormally);
    });
  });

  group('product runtime fields', () {
    test('round-trips bilingual identifiers, currency, and tax fields', () {
      const product = InventoryModel(
        id: 'product-1',
        name: 'فلتر زيت',
        nameEn: 'Oil Filter',
        description: 'فلتر محرك',
        code: 'OF-01',
        sku: 'SKU-OF-01',
        barcode: '1234567890',
        serialNumber: '',
        category: 'قطع غيار',
        groupId: 'group-1',
        unit: 'قطعة',
        quantity: 5,
        purchasePrice: 10,
        landedCost: 1,
        unitCost: 11,
        salePrice: 15,
        currency: 'USD',
        taxRate: 5,
        minQuantity: 2,
        expectedIncoming: 0,
        expectedOutgoing: 0,
        date: '2026-07-27T00:00:00Z',
      );

      final map = product.toCloudMap();
      final restored = InventoryModel.fromCloudMap(map);
      expect(restored.nameEn, 'Oil Filter');
      expect(restored.sku, 'SKU-OF-01');
      expect(restored.barcode, '1234567890');
      expect(restored.currency, 'USD');
      expect(restored.taxRate, 5);
      expect(map['sale_price'], map['salePrice']);
      expect(map['tax_rate'], map['taxRate']);
    });
  });
}
