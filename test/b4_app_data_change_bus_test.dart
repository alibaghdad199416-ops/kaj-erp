import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

void main() {
  group('B-4 application data change bus quality', () {
    test(
      'publishes ordered revisions with complete mutation metadata',
      () async {
        final bus = AppDataChangeBus.instance;
        final initialRevision = bus.revision;
        final received = <AppDataChangeEvent>[];
        final subscription = bus.events.listen(received.add);

        final created = bus.publish(
          'inventory',
          operation: 'created',
          entityId: 'item-100',
        );
        final updated = bus.publish(
          'accounting',
          operation: 'posted',
          entityId: 'journal-200',
        );

        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(created.revision, initialRevision + 1);
        expect(updated.revision, initialRevision + 2);
        expect(updated.revision, greaterThan(created.revision));
        expect(
          received,
          containsAllInOrder(<AppDataChangeEvent>[created, updated]),
        );
        expect(created.source, 'inventory');
        expect(created.operation, 'created');
        expect(created.entityId, 'item-100');
        expect(updated.source, 'accounting');
        expect(updated.operation, 'posted');
        expect(updated.entityId, 'journal-200');
        expect(created.occurredAt.isAfter(DateTime.now()), isFalse);
      },
    );

    test('broadcast listeners receive the same committed mutation', () async {
      final bus = AppDataChangeBus.instance;
      AppDataChangeEvent? first;
      AppDataChangeEvent? second;
      final firstSubscription = bus.events.listen((event) => first = event);
      final secondSubscription = bus.events.listen((event) => second = event);

      final event = bus.publish(
        'maintenance',
        operation: 'status_changed',
        entityId: 'order-300',
      );
      await Future<void>.delayed(Duration.zero);

      await firstSubscription.cancel();
      await secondSubscription.cancel();
      expect(first, same(event));
      expect(second, same(event));
    });
  });
}
