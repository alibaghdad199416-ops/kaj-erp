import 'package:flutter/material.dart';

class NotificationAlert {
  const NotificationAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.icon,
    required this.route,
    this.count = 0,
    this.amount,
  });

  final String id;
  final String title;
  final String message;
  final NotificationSeverity severity;
  final IconData icon;
  final String route;
  final int count;
  final double? amount;
}

enum NotificationSeverity { critical, warning, info }

/// Compatibility navigation helper used by legacy notification actions.
/// Keeping it here avoids reintroducing a dependency from route construction
/// back into feature pages.
abstract final class AppModuleNavigation {
  static Future<void> open(BuildContext context, String route) async {
    if (route.trim().isEmpty) return;
    await Navigator.of(context).pushNamed(route);
  }
}

/// Lightweight loading placeholder shared by the notification center.
class KajActivitySkeleton extends StatelessWidget {
  const KajActivitySkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      children: List.generate(
        rows,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
