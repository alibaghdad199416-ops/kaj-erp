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
