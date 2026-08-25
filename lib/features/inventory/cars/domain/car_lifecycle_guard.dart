/// Central guard for vehicle lifecycle states driven by business documents.
class CarLifecycleGuard {
  const CarLifecycleGuard._();

  static const String defined = 'معرفة';
  static const String purchasing = 'قيد الشراء';
  static const String available = 'متوفرة';
  static const String selling = 'قيد البيع';
  static const String sold = 'مباعة';

  static const Set<String> supportedStatuses = {
    defined,
    purchasing,
    available,
    selling,
    sold,
  };

  static const Map<String, Set<String>> _allowedTransitions = {
    defined: {purchasing},
    purchasing: {defined, available},
    available: {selling},
    selling: {available, sold},
    sold: {available},
  };

  static void validateStatus(String status) {
    if (!supportedStatuses.contains(status)) {
      throw ArgumentError('حالة السيارة غير معتمدة: $status');
    }
  }

  static bool canTransition(String from, String to) {
    validateStatus(from);
    validateStatus(to);
    if (from == to) return true;
    return _allowedTransitions[from]?.contains(to) ?? false;
  }

  static void ensureTransition(String from, String to) {
    if (!canTransition(from, to)) {
      throw StateError('لا يمكن تغيير حالة السيارة من "$from" إلى "$to".');
    }
  }
}
