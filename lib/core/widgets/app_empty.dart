import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';

class AppEmpty extends StatelessWidget {
  const AppEmpty({
    super.key,
    this.title = 'لا توجد بيانات',
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 10),
          AppText(
            AppTranslation.translate(title),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            AppText(
              AppTranslation.translate(message!),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    ),
  );
}
