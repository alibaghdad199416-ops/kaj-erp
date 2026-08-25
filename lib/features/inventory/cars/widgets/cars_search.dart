import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

class CarsSearch extends StatelessWidget {
  const CarsSearch({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: AppTranslation.translate(
          'ابحث بالماركة أو الموديل أو رقم اللوحة...',
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
    );
  }
}
