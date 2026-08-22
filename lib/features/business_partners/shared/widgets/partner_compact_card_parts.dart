import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

class PartnerCompactValue extends StatelessWidget {
  const PartnerCompactValue(this.label, this.value, {super.key});
  final String label;
  final String? value;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = value?.trim() ?? '';
    return Container(
      constraints: const BoxConstraints(maxWidth: 100),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(7),
      ),
      child: AppText(
        '$label: ${text.isEmpty ? '—' : text}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class PartnerCompactAction extends StatelessWidget {
  const PartnerCompactAction(
    this.icon,
    this.label,
    this.onPressed, {
    super.key,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final color = destructive ? s.error : s.primary;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: .35)),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
        ),
      ),
    );
  }
}

class PartnerStatusBadge extends StatelessWidget {
  const PartnerStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: AppText(
      label,
      style: TextStyle(
        color: color,
        fontSize: 8.5,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}
