import 'package:flutter/material.dart';

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.permission,
    required this.icon,
    this.status,
    this.amount,
    this.currency,
    this.date,
  });

  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String route;
  final String permission;
  final IconData icon;
  final String? status;
  final double? amount;
  final String? currency;
  final String? date;
}
