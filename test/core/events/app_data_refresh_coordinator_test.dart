import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/events/app_data_refresh_coordinator.dart';

void main() {
  test('refreshes only rules invalidated by the published source', () async {
    var carsRefreshes = 0;
    var accountingRefreshes = 0;
    final coordinator = AppDataRefreshCoordinator(
      rules: <AppDataRefreshRule>[
        AppDataRefreshRule(
          id: 'cars',
          sources: const <String>{'cars'},
          debounce: Duration.zero,
          refresh: (_) async => carsRefreshes += 1,
        ),
        AppDataRefreshRule(
          id: 'accounting',
          sources: const <String>{'accounting'},
          debounce: Duration.zero,
          refresh: (_) async => accountingRefreshes += 1,
        ),
      ],
    );

    await coordinator.start();
    AppDataChangeBus.instance.publish('cars', operation: 'updated');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await coordinator.stop();

    expect(carsRefreshes, 1);
    expect(accountingRefreshes, 0);
  });

  test('queues one more refresh when a change arrives during a load', () async {
    var refreshes = 0;
    final firstRefreshStarted = Completer<void>();
    final releaseFirstRefresh = Completer<void>();
    final coordinator = AppDataRefreshCoordinator(
      rules: <AppDataRefreshRule>[
        AppDataRefreshRule(
          id: 'inventory',
          sources: const <String>{'inventory'},
          debounce: Duration.zero,
          refresh: (_) async {
            refreshes += 1;
            if (refreshes == 1) {
              firstRefreshStarted.complete();
              await releaseFirstRefresh.future;
            }
          },
        ),
      ],
    );

    await coordinator.start();
    AppDataChangeBus.instance.publish('inventory');
    await firstRefreshStarted.future;
    AppDataChangeBus.instance.publish('inventory');
    await Future<void>.delayed(Duration.zero);
    releaseFirstRefresh.complete();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await coordinator.stop();

    expect(refreshes, 2);
  });

  test('all source invalidates every registered rule', () async {
    var firstRefreshes = 0;
    var secondRefreshes = 0;
    final coordinator = AppDataRefreshCoordinator(
      rules: <AppDataRefreshRule>[
        AppDataRefreshRule(
          id: 'first',
          sources: const <String>{'cars'},
          debounce: Duration.zero,
          refresh: (_) async => firstRefreshes += 1,
        ),
        AppDataRefreshRule(
          id: 'second',
          sources: const <String>{'accounting'},
          debounce: Duration.zero,
          refresh: (_) async => secondRefreshes += 1,
        ),
      ],
    );

    await coordinator.start();
    AppDataChangeBus.instance.publish('all', operation: 'backup-restore');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await coordinator.stop();

    expect(firstRefreshes, 1);
    expect(secondRefreshes, 1);
  });

  test('local reconciliation is skipped but external realtime stays fresh', () {
    const localOperations = <String>{'insert', 'update', 'delete'};
    final local = AppDataChangeEvent(
      source: 'cars',
      operation: 'update',
      revision: 1,
      occurredAt: DateTime.utc(2026),
    );
    final external = AppDataChangeEvent(
      source: 'cars',
      operation: 'cloud-realtime',
      revision: 2,
      occurredAt: DateTime.utc(2026),
    );

    expect(
      requiresRefreshBeyondLocalOperations(<AppDataChangeEvent>[
        local,
      ], localOperations),
      isFalse,
    );
    expect(
      requiresRefreshBeyondLocalOperations(<AppDataChangeEvent>[
        external,
      ], localOperations),
      isTrue,
    );
    expect(
      requiresRefreshBeyondLocalOperations(<AppDataChangeEvent>[
        local,
        external,
      ], localOperations),
      isTrue,
    );
  });
}
