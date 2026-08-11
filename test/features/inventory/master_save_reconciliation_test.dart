import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/data/query_page.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/data/car_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_group_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';

class _InventoryRepository extends InventoryRepository {
  _InventoryRepository({required this.committedAfterError});
  final bool committedAfterError;
  final List<InventoryModel> rows = [];

  @override
  Future<void> addInventory(
    InventoryModel item, {
    String? warehouseId,
    required int openingQuantity,
    List<String> imagesBase64 = const [],
  }) async {
    if (committedAfterError) rows.add(item);
    throw StateError('simulated response loss');
  }

  @override
  Future<bool> inventoryProductExists(String id) async =>
      rows.any((item) => item.id == id);

  @override
  Future<List<InventoryModel>> getInventory({
    String? warehouseId,
    QueryPage page = const QueryPage(),
  }) async => List.of(rows);

  @override
  Future<List<WarehouseModel>> getWarehouses({
    bool includeInactive = false,
  }) async => const [];

  @override
  Future<List<InventoryGroupModel>> getGroups() async => const [];
}

class _CarRepository extends CarRepository {
  _CarRepository({required this.committedAfterError});
  final bool committedAfterError;
  final List<CarModel> rows = [];

  @override
  Future<void> insertCar(CarModel car) async {
    if (committedAfterError) rows.add(car);
    throw StateError('simulated response loss');
  }

  @override
  Future<bool> carExists(String id) async => rows.any((car) => car.id == id);

  @override
  Future<List<CarModel>> getCars({QueryPage page = const QueryPage()}) async =>
      List.of(rows);
}

const product = InventoryModel(
  id: 'product-r55',
  name: 'R55 product',
  code: 'R55-P',
  serialNumber: '',
  category: 'Parts',
  groupId: 'parts',
  unit: 'piece',
  quantity: 0,
  purchasePrice: 10,
  landedCost: 10,
  unitCost: 10,
  salePrice: 12,
  minQuantity: 0,
  expectedIncoming: 0,
  expectedOutgoing: 0,
  date: '2026-08-11',
  currency: 'USD',
);

const car = CarModel(
  id: 'car-r55',
  brand: 'Toyota',
  model: 'R55',
  year: 2026,
  color: 'Black',
  chassis: 'R55-CHASSIS',
  plateNumber: '',
  purchasePrice: 10000,
  salePrice: 12000,
  status: 'defined',
  imagePath: '',
  currency: 'USD',
);

void main() {
  test('genuine product failure creates no selector ghost', () async {
    final repository = _InventoryRepository(committedAfterError: false);
    final controller = InventoryController(repository: repository);

    await expectLater(
      controller.addInventory(product, openingQuantity: 0),
      throwsStateError,
    );
    expect(controller.items, isEmpty);
    expect(repository.rows, isEmpty);
  });

  test('ambiguous product response reconciles canonical commit once', () async {
    final repository = _InventoryRepository(committedAfterError: true);
    final controller = InventoryController(repository: repository);

    await controller.addInventory(product, openingQuantity: 0);
    expect(controller.items.map((item) => item.id), ['product-r55']);
  });

  test('genuine car failure creates no selector ghost', () async {
    final repository = _CarRepository(committedAfterError: false);
    final controller = CarsController(repository: repository);

    await expectLater(controller.addCar(car), throwsStateError);
    expect(controller.cars, isEmpty);
    expect(repository.rows, isEmpty);
  });

  test('ambiguous car response reconciles canonical commit once', () async {
    final repository = _CarRepository(committedAfterError: true);
    final controller = CarsController(repository: repository);

    await controller.addCar(car);
    expect(controller.cars.map((item) => item.id), ['car-r55']);
  });
}
