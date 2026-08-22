import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/dashboard/controllers/dashboard_controller.dart';
import 'package:quality_line_erp/features/dashboard/data/dashboard_repository.dart';
import 'package:quality_line_erp/features/dashboard/models/dashboard_model.dart';

class _QueuedDashboardRepository extends DashboardRepository {
  final List<Completer<DashboardModel>> requests = [];

  @override
  Future<DashboardModel> getDashboardData({
    DateTime? fromDate,
    required DateTime toDate,
  }) {
    final completer = Completer<DashboardModel>();
    requests.add(completer);
    return completer.future;
  }
}

void main() {
  test('late filter response cannot overwrite the newest snapshot', () async {
    final repository = _QueuedDashboardRepository();
    final controller = DashboardController(repository: repository);
    final oldRequest = controller.loadDashboard(force: true);
    final newRequest = controller.setPeriod(DashboardPeriod.today);

    expect(repository.requests, hasLength(2));
    final newestAt = DateTime.utc(2026, 8, 14, 5);
    repository.requests[1].complete(
      DashboardModel.empty(generatedAt: newestAt),
    );
    await newRequest;
    repository.requests[0].complete(
      DashboardModel.empty(generatedAt: DateTime.utc(2026, 8, 13)),
    );
    await oldRequest;

    expect(controller.lastGeneratedAt, newestAt);
    expect(controller.appliedRevision, 1);
    expect(controller.period, DashboardPeriod.today);
    controller.dispose();
  });

  test('failed refresh preserves the last authoritative snapshot', () async {
    final repository = _QueuedDashboardRepository();
    final controller = DashboardController(repository: repository);
    final initial = controller.loadDashboard(force: true);
    final generatedAt = DateTime.utc(2026, 8, 14, 4);
    repository.requests.single.complete(
      DashboardModel.empty(generatedAt: generatedAt),
    );
    await initial;

    final failed = controller.loadDashboard(force: true);
    repository.requests.last.completeError(StateError('database unavailable'));
    await failed;

    expect(controller.lastGeneratedAt, generatedAt);
    expect(controller.errorMessage, isNotNull);
    controller.dispose();
  });

  test('Dashboard source contract uses one strict R65 currency snapshot', () {
    final repository = File(
      'lib/features/dashboard/data/dashboard_repository.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/dashboard/controllers/dashboard_controller.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260814053406_r65_authoritative_dashboard_snapshot.sql',
    ).readAsStringSync();

    expect(
      repository,
      contains('erp_r65_get_authoritative_dashboard_snapshot'),
    );
    expect(
      repository,
      contains("_requiredMoneyMap(row, 'totalSalesByCurrency')"),
    );
    expect(repository, contains("'maintenanceActualCostByCurrency'"));
    expect(controller, contains('revision != _requestRevision'));
    expect(migration, contains("d.document_type='invoice'"));
    expect(migration, contains("d.status='approved'"));
    expect(migration, contains('erp_inventory_cost_layers'));
    expect(migration, contains('erp_inventory_fifo_consumptions'));
    expect(migration, contains("at time zone 'Asia/Baghdad'"));
    expect(migration, contains('customerAdvancesByCurrency'));
    expect(migration, contains('revoke all on function'));
  });
}
