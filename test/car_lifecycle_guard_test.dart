import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/inventory/cars/domain/car_lifecycle_guard.dart';

void main() {
  group('CarLifecycleGuard', () {
    test('allows the enterprise vehicle lifecycle', () {
      expect(CarLifecycleGuard.canTransition('معرفة', 'قيد الشراء'), isTrue);
      expect(CarLifecycleGuard.canTransition('قيد الشراء', 'متوفرة'), isTrue);
      expect(CarLifecycleGuard.canTransition('متوفرة', 'قيد البيع'), isTrue);
      expect(CarLifecycleGuard.canTransition('قيد البيع', 'مباعة'), isTrue);
    });

    test('allows controlled rollback transitions', () {
      expect(CarLifecycleGuard.canTransition('قيد الشراء', 'معرفة'), isTrue);
      expect(CarLifecycleGuard.canTransition('قيد البيع', 'متوفرة'), isTrue);
    });

    test('rejects contradictory transitions', () {
      expect(CarLifecycleGuard.canTransition('معرفة', 'مباعة'), isFalse);
      expect(
        () => CarLifecycleGuard.ensureTransition('معرفة', 'مباعة'),
        throwsStateError,
      );
    });

    test('rejects unknown statuses', () {
      expect(
        () => CarLifecycleGuard.validateStatus('غير معروفة'),
        throwsArgumentError,
      );
    });
  });
}
