import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

class AppSearch extends StatelessWidget {
  const AppSearch({
    super.key,
    this.controller,
    this.onChanged,
    this.hintText = 'بحث',
    this.autofocus = false,
  });
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: AppTranslation.translate(hintText),
      prefixIcon: const Icon(Icons.search_rounded, size: 19),
      suffixIcon: controller == null
          ? null
          : IconButton(
              tooltip: AppTranslation.translate('مسح'),
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () {
                controller!.clear();
                onChanged?.call('');
              },
            ),
    ),
  );
}
