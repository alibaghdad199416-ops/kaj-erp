import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/core/data/query_page.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/data/car_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';

void main() {
  test('concurrent ordinary car loads share one request', () async {
    final repository = _CountingCarRepository();
    final response = Completer<List<CarModel>>();
    repository.responses.add(response);
    final controller = CarsController(repository: repository);

    final first = controller.loadCars();
    final second = controller.loadCars();
    expect(repository.calls, 1);
    response.complete(const <CarModel>[]);
    await Future.wait(<Future<void>>[first, second]);

    expect(repository.calls, 1);
  });

  test('forced refresh during a car load schedules one follow-up', () async {
    final repository = _CountingCarRepository();
    final firstResponse = Completer<List<CarModel>>();
    final secondResponse = Completer<List<CarModel>>();
    repository.responses.addAll(<Completer<List<CarModel>>>[
      firstResponse,
      secondResponse,
    ]);
    final controller = CarsController(repository: repository);

    final first = controller.loadCars();
    final forcedA = controller.loadCars(force: true);
    final forcedB = controller.loadCars(force: true);
    expect(repository.calls, 1);
    firstResponse.complete(const <CarModel>[]);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 2);
    secondResponse.complete(const <CarModel>[]);
    await Future.wait(<Future<void>>[first, forcedA, forcedB]);

    expect(repository.calls, 2);
  });

  test('a recently loaded cars page reuses its fresh result', () async {
    final repository = _CountingCarRepository();
    final response = Completer<List<CarModel>>()..complete(const <CarModel>[]);
    repository.responses.add(response);
    final controller = CarsController(repository: repository);

    await controller.loadCars();
    await controller.loadCars();

    expect(repository.calls, 1);
  });
}

class _CountingCarRepository extends CarRepository {
  final List<Completer<List<CarModel>>> responses =
      <Completer<List<CarModel>>>[];
  int calls = 0;

  @override
  Future<List<CarModel>> getCars({QueryPage page = const QueryPage()}) {
    return responses[calls++].future;
  }
}
