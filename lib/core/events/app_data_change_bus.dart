import 'dart:async';

/// Application-wide data invalidation channel.
///
/// Every committed mutation receives a monotonically increasing revision.
/// Aggregate views can therefore coalesce bursts without losing the knowledge
/// that a newer change happened while they were loading.
class AppDataChangeBus {
  AppDataChangeBus._();

  static final AppDataChangeBus instance = AppDataChangeBus._();
  final StreamController<AppDataChangeEvent> _controller =
      StreamController<AppDataChangeEvent>.broadcast(sync: true);

  int _revision = 0;

  Stream<AppDataChangeEvent> get events => _controller.stream;
  int get revision => _revision;

  AppDataChangeEvent publish(
    String source, {
    String operation = 'changed',
    String? entityId,
  }) {
    final event = AppDataChangeEvent(
      source: source,
      operation: operation,
      entityId: entityId,
      revision: ++_revision,
      occurredAt: DateTime.now(),
    );
    if (!_controller.isClosed) _controller.add(event);
    return event;
  }
}

class AppDataChangeEvent {
  const AppDataChangeEvent({
    required this.source,
    required this.operation,
    required this.revision,
    required this.occurredAt,
    this.entityId,
  });

  final String source;
  final String operation;
  final String? entityId;
  final int revision;
  final DateTime occurredAt;
}
