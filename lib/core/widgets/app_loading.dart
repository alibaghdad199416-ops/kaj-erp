import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label = 'جارٍ التحميل...'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
        const SizedBox(height: 12),
        AppText(
          AppTranslation.translate(label),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}
