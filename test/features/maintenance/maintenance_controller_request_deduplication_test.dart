import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/features/maintenance/controllers/maintenance_controller.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

void main() {
  test('maintenance loads coalesce and retain one forced follow-up', () async {
    final repository = _CountingMaintenanceRepository();
    final firstResponse = Completer<List<MaintenanceOrderModel>>();
    final secondResponse = Completer<List<MaintenanceOrderModel>>();
    repository.responses.addAll(<Completer<List<MaintenanceOrderModel>>>[
      firstResponse,
      secondResponse,
    ]);
    final controller = MaintenanceController(repository: repository);

    final first = controller.loadOrders();
    final shared = controller.loadOrders();
    final forcedA = controller.loadOrders(force: true);
    final forcedB = controller.loadOrders(force: true);
    expect(repository.calls, 1);
    firstResponse.complete(const <MaintenanceOrderModel>[]);
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 2);
    secondResponse.complete(const <MaintenanceOrderModel>[]);
    await Future.wait(<Future<void>>[first, shared, forcedA, forcedB]);

    expect(repository.calls, 2);
  });
}

class _CountingMaintenanceRepository extends MaintenanceRepository {
  final List<Completer<List<MaintenanceOrderModel>>> responses =
      <Completer<List<MaintenanceOrderModel>>>[];
  int calls = 0;

  @override
  Future<List<MaintenanceOrderModel>> getOrders() {
    return responses[calls++].future;
  }
}
