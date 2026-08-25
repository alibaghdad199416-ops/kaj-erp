import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';

void main() {
  test('data change bus broadcasts committed mutation metadata', () async {
    final eventFuture = AppDataChangeBus.instance.events.first;

    AppDataChangeBus.instance.publish('cars', operation: 'update');

    final event = await eventFuture;
    expect(event.source, 'cars');
    expect(event.operation, 'update');
    expect(
      event.occurredAt.isAfter(
        DateTime.now().subtract(const Duration(seconds: 2)),
      ),
      isTrue,
    );
  });
}
