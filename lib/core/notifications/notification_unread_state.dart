import 'package:flutter/foundation.dart';

/// Shared unread-notification count used by the navigation badge.
class NotificationUnreadState {
  NotificationUnreadState._();

  static final ValueNotifier<int> count = ValueNotifier<int>(0);

  static void update(int value) {
    count.value = value < 0 ? 0 : value;
  }
}
