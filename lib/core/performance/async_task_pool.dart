import 'dart:async';

import 'package:flutter/foundation.dart';

typedef AsyncTask = Future<void> Function();

@immutable
class NamedAsyncTask {
  const NamedAsyncTask({required this.name, required this.run});

  final String name;
  final AsyncTask run;
}

class AsyncTaskPool {
  const AsyncTaskPool({
    this.maxConcurrent = 4,
    this.timeout = const Duration(seconds: 15),
  }) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  final Duration timeout;

  Future<void> runAll(
    Iterable<NamedAsyncTask> tasks, {
    void Function(String message)? logger,
  }) async {
    final queue = List<NamedAsyncTask>.of(tasks, growable: false);
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final currentIndex = nextIndex;
        if (currentIndex >= queue.length) return;
        nextIndex += 1;
        final task = queue[currentIndex];
        final stopwatch = Stopwatch()..start();
        try {
          await task.run().timeout(timeout);
          logger?.call(
            '${task.name} completed in ${stopwatch.elapsedMilliseconds} ms',
          );
        } on TimeoutException {
          logger?.call(
            '${task.name} timed out after ${timeout.inSeconds} seconds',
          );
        } catch (error) {
          logger?.call('${task.name} failed: $error');
        } finally {
          stopwatch.stop();
        }
      }
    }

    final workerCount = queue.length < maxConcurrent
        ? queue.length
        : maxConcurrent;
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }
}
