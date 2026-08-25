import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

class StatusFilter extends StatelessWidget {
  const StatusFilter({
    super.key,
    required this.selectedStatus,
    required this.onChanged,
  });

  final String selectedStatus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const statuses = [
      'الكل',
      'معرفة',
      'قيد الشراء',
      'متوفرة',
      'قيد البيع',
      'مباعة',
    ];
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: selectedStatus,
      isDense: true,
      decoration: InputDecoration(
        labelText: AppTranslation.translate('الحالة'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: statuses
          .map(
            (status) => DropdownMenuItem(value: status, child: AppText(status)),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
