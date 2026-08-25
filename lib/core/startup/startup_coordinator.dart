import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';
import 'package:quality_line_erp/core/performance/async_task_pool.dart';

enum StartupState { idle, running, ready, failed }

/// Coordinates cloud-first startup tasks. No local database is opened.
class StartupCoordinator {
  StartupCoordinator._({AsyncTaskPool? taskPool})
    : _taskPool = taskPool ?? const AsyncTaskPool(maxConcurrent: 4);
  static final StartupCoordinator instance = StartupCoordinator._();
  final AsyncTaskPool _taskPool;
  Future<void>? _startupFuture;
  List<NamedAsyncTask> _prerequisites = const [];
  List<NamedAsyncTask> _primaryData = const [];
  List<NamedAsyncTask> _aggregates = const [];
  StartupState _state = StartupState.idle;
  Object? _lastError;
  StartupState get state => _state;
  bool get isReady => _state == StartupState.ready;
  Object? get lastError => _lastError;
  Future<void> run({
    required List<NamedAsyncTask> prerequisites,
    required List<NamedAsyncTask> primaryData,
    required List<NamedAsyncTask> aggregates,
  }) {
    _prerequisites = List.unmodifiable(prerequisites);
    _primaryData = List.unmodifiable(primaryData);
    _aggregates = List.unmodifiable(aggregates);
    return _startupFuture ??= _runOnce();
  }

  Future<void> waitUntilReady({
    Duration timeout = const Duration(seconds: 150),
  }) async {
    Future<void>? startup;
    while ((startup = _startupFuture) == null) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    final readyFuture = startup;
    if (readyFuture == null) {
      throw StateError('Startup coordinator did not register a startup task.');
    }
    await readyFuture.timeout(timeout);
  }

  Future<void> retry() {
    if (_state == StartupState.running)
      return _startupFuture ?? Future<void>.value();
    if (_prerequisites.isEmpty && _primaryData.isEmpty && _aggregates.isEmpty)
      return Future<void>.error(
        StateError('Startup tasks have not been registered yet.'),
      );
    final startup = _runOnce();
    _startupFuture = startup;
    return startup;
  }

  Future<void> _runOnce() async {
    _state = StartupState.running;
    _lastError = null;
    try {
      await _taskPool.runAll(_prerequisites, logger: _log);
      await _taskPool.runAll(_primaryData, logger: _log);
      await _taskPool.runAll(_aggregates, logger: _log);
      _state = StartupState.ready;
      AppLogger.debug('Startup: cloud application data ready');
    } catch (e, st) {
      _lastError = e;
      _state = StartupState.failed;
      AppLogger.debug('Startup failed: $e');
      AppLogger.stack(st);
      rethrow;
    }
  }

  void _log(String message) => AppLogger.debug('Startup: $message');
}
