import 'dart:async';

import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';

typedef AppDataRefreshCallback =
    Future<void> Function(List<AppDataChangeEvent> events);

bool requiresRefreshBeyondLocalOperations(
  Iterable<AppDataChangeEvent> events,
  Set<String> locallyReconciledOperations,
) => events.any(
  (event) => !locallyReconciledOperations.contains(event.operation),
);

/// Declarative refresh rule for one controller or aggregate view.
///
/// Feature modules declare the data sources that invalidate them instead of
/// adding another hard-coded branch to `main.dart`. Rules are debounced and a
/// second refresh is queued when new changes arrive while the first one runs.
class AppDataRefreshRule {
  AppDataRefreshRule({
    required this.id,
    required Iterable<String> sources,
    required this.refresh,
    this.debounce = const Duration(milliseconds: 420),
  }) : sources = Set<String>.unmodifiable(
         sources
             .map((source) => source.trim())
             .where((source) => source.isNotEmpty),
       );

  final String id;
  final Set<String> sources;
  final AppDataRefreshCallback refresh;
  final Duration debounce;
}

/// Keeps every visible controller synchronized with local mutations and
/// Supabase Realtime events without coupling the event bus to feature classes.
class AppDataRefreshCoordinator {
  AppDataRefreshCoordinator({
    required Iterable<AppDataRefreshRule> rules,
    AppDataChangeBus? bus,
  }) : _bus = bus ?? AppDataChangeBus.instance,
       _states = <String, _RefreshRuleState>{
         for (final rule in rules) rule.id: _RefreshRuleState(rule),
       } {
    if (_states.length != rules.length) {
      throw ArgumentError('Refresh rule ids must be unique.');
    }
  }

  final AppDataChangeBus _bus;
  final Map<String, _RefreshRuleState> _states;
  StreamSubscription<AppDataChangeEvent>? _subscription;

  bool get isRunning => _subscription != null;
  List<String> get ruleIds => List<String>.unmodifiable(_states.keys);

  Future<void> start() async {
    await stop();
    _subscription = _bus.events.listen(_onEvent);
  }

  void _onEvent(AppDataChangeEvent event) {
    for (final state in _states.values) {
      if (event.source != 'all' && !state.rule.sources.contains(event.source)) {
        continue;
      }
      state.pendingEvents.add(event);
      state.timer?.cancel();
      state.timer = Timer(state.rule.debounce, () => unawaited(_run(state)));
    }
  }

  Future<void> refreshAll() async {
    for (final state in _states.values) {
      state.pendingEvents.add(
        AppDataChangeEvent(
          source: 'manual',
          operation: 'refresh-all',
          revision: _bus.revision,
          occurredAt: DateTime.now(),
        ),
      );
    }
    await Future.wait(_states.values.map(_run));
  }

  Future<void> _run(_RefreshRuleState state) async {
    state.timer?.cancel();
    state.timer = null;
    if (state.running) {
      state.runAgain = true;
      return;
    }
    if (state.pendingEvents.isEmpty) return;

    state.running = true;
    final events = List<AppDataChangeEvent>.unmodifiable(state.pendingEvents);
    state.pendingEvents.clear();
    try {
      await state.rule.refresh(events);
    } catch (error, stackTrace) {
      AppLogger.error(
        'Data refresh rule failed: ${state.rule.id}',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      state.running = false;
      if (state.runAgain || state.pendingEvents.isNotEmpty) {
        state.runAgain = false;
        await _run(state);
      }
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final state in _states.values) {
      state.timer?.cancel();
      state.timer = null;
      state.pendingEvents.clear();
      state.runAgain = false;
    }
  }
}

class _RefreshRuleState {
  _RefreshRuleState(this.rule);

  final AppDataRefreshRule rule;
  final List<AppDataChangeEvent> pendingEvents = <AppDataChangeEvent>[];
  Timer? timer;
  bool running = false;
  bool runAgain = false;
}
