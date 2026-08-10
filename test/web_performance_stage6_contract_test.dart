import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/performance/async_task_pool.dart';

void main() {
  test('task pool respects its concurrency limit', () async {
    var active = 0;
    var peak = 0;
    final tasks = List.generate(
      8,
      (index) => NamedAsyncTask(
        name: 'task-$index',
        run: () async {
          active += 1;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active -= 1;
        },
      ),
    );

    await const AsyncTaskPool(maxConcurrent: 3).runAll(tasks);

    expect(peak, lessThanOrEqualTo(3));
    expect(active, 0);
  });

  test('task failure does not stop remaining work', () async {
    var completed = 0;
    await const AsyncTaskPool(maxConcurrent: 2).runAll([
      NamedAsyncTask(name: 'failure', run: () async => throw StateError('x')),
      NamedAsyncTask(name: 'success', run: () async => completed += 1),
    ]);

    expect(completed, 1);
  });
}
