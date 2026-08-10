import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/reports/services/report_field_localizer.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class ReportSectionCustomizationDialog extends StatefulWidget {
  const ReportSectionCustomizationDialog({
    super.key,
    required this.sections,
    required this.initialOptions,
  });

  final List<ContextualReportSection> sections;
  final ReportExportOptions initialOptions;

  @override
  State<ReportSectionCustomizationDialog> createState() =>
      _ReportSectionCustomizationDialogState();
}

class _ReportSectionCustomizationDialogState
    extends State<ReportSectionCustomizationDialog> {
  late final Map<String, Set<String>> _selectedColumns;
  late final Map<String, TextEditingController> _queries;
  late final Map<String, TextEditingController> _rowLimits;
  late final Map<String, String> _sortColumns;
  late final Map<String, bool> _sortAscending;
  late final Map<String, bool> _sectionEnabled;

  @override
  void initState() {
    super.initState();
    _selectedColumns = {
      for (final section in widget.sections)
        section.key:
            (widget.initialOptions.selectedColumns[section.key] ??
                    section.columns)
                .toSet(),
    };
    _queries = {
      for (final section in widget.sections)
        section.key: TextEditingController(
          text: widget.initialOptions.sectionQueries[section.key] ?? '',
        ),
    };
    _rowLimits = {
      for (final section in widget.sections)
        section.key: TextEditingController(
          text: '${widget.initialOptions.sectionRowLimits[section.key] ?? 0}',
        ),
    };
    _sortColumns = Map<String, String>.from(widget.initialOptions.sortColumns);
    _sortAscending = Map<String, bool>.from(
      widget.initialOptions.sortAscending,
    );
    _sectionEnabled = {
      for (final section in widget.sections)
        section.key: widget.initialOptions.sectionEnabled[section.key] ?? true,
    };
  }

  @override
  void dispose() {
    for (final controller in [..._queries.values, ..._rowLimits.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  ReportExportOptions _result() {
    return widget.initialOptions.copyWith(
      selectedColumns: {
        for (final section in widget.sections)
          section.key: section.columns
              .where(_selectedColumns[section.key]!.contains)
              .toList(growable: false),
      },
      sectionQueries: {
        for (final entry in _queries.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
      sortColumns: _sortColumns,
      sortAscending: _sortAscending,
      sectionEnabled: _sectionEnabled,
      sectionRowLimits: {
        for (final entry in _rowLimits.entries)
          entry.key: (int.tryParse(entry.value.text.trim()) ?? 0)
              .clamp(0, 1000000)
              .toInt(),
      },
    );
  }

  String _bi(BuildContext context, String ar, String en) =>
      context.l10n.isArabic ? ar : en;

  String _localizedLabel(BuildContext context, String value) =>
      ReportFieldLocalizer.localize(value, context.l10n.isArabic ? 'ar' : 'en');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: AppText(
        _bi(context, 'تخصيص بيانات التقرير', 'Customize report data'),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, 820),
        child: widget.sections.isEmpty
            ? AppText(
                _bi(
                  context,
                  'لا توجد أقسام بيانات قابلة للتخصيص حاليًا.',
                  'There are no customizable data sections.',
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: widget.sections.length,
                separatorBuilder: (_, _) => const Divider(height: 28),
                itemBuilder: (context, index) {
                  final section = widget.sections[index];
                  final selected = _selectedColumns[section.key]!;
                  final enabled = _sectionEnabled[section.key] ?? true;
                  return Opacity(
                    opacity: enabled ? 1 : .58,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: enabled,
                          onChanged: (value) => setState(
                            () => _sectionEnabled[section.key] = value,
                          ),
                          title: AppText(
                            _localizedLabel(context, section.title),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: AppText(
                            _bi(
                              context,
                              '${section.rows.length} صف • ${section.columns.length} حقل',
                              '${section.rows.length} rows • ${section.columns.length} fields',
                            ),
                          ),
                        ),
                        IgnorePointer(
                          ignoring: !enabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _queries[section.key],
                                      decoration: InputDecoration(
                                        labelText: _bi(
                                          context,
                                          'بحث أو تصفية صفوف القسم',
                                          'Search or filter section rows',
                                        ),
                                        prefixIcon: const Icon(Icons.search),
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _rowLimits[section.key],
                                      keyboardType: TextInputType.number,
                                      inputFormatters: <TextInputFormatter>[
                                        ThousandsInputFormatter(
                                          decimalDigits: 2,
                                        ),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: _bi(
                                          context,
                                          'حد الصفوف (0 = الكل)',
                                          'Row limit (0 = all)',
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.table_rows,
                                        ),
                                        border: const OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => setState(
                                      () => selected
                                        ..clear()
                                        ..addAll(section.columns),
                                    ),
                                    icon: const Icon(Icons.select_all),
                                    label: AppText(
                                      _bi(context, 'اختيار الكل', 'Select all'),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: selected.length <= 1
                                        ? null
                                        : () => setState(() {
                                            final keep = selected.first;
                                            selected
                                              ..clear()
                                              ..add(keep);
                                          }),
                                    icon: const Icon(Icons.filter_alt_off),
                                    label: AppText(
                                      _bi(
                                        context,
                                        'إلغاء الاختيار مع إبقاء حقل',
                                        'Clear except one field',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: section.columns
                                    .map(
                                      (column) => FilterChip(
                                        label: AppText(
                                          _localizedLabel(context, column),
                                        ),
                                        selected: selected.contains(column),
                                        onSelected: (value) {
                                          setState(() {
                                            if (value) {
                                              selected.add(column);
                                            } else if (selected.length > 1) {
                                              selected.remove(column);
                                            }
                                          });
                                        },
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String?>(
                                      isExpanded: true,
                                      initialValue: _sortColumns[section.key],
                                      decoration: InputDecoration(
                                        labelText: _bi(
                                          context,
                                          'الفرز حسب',
                                          'Sort by',
                                        ),
                                        border: const OutlineInputBorder(),
                                      ),
                                      items: [
                                        DropdownMenuItem<String?>(
                                          value: null,
                                          child: AppText(
                                            _bi(
                                              context,
                                              'بدون فرز',
                                              'No sorting',
                                            ),
                                          ),
                                        ),
                                        ...section.columns.map(
                                          (column) => DropdownMenuItem<String?>(
                                            value: column,
                                            child: AppText(
                                              _localizedLabel(context, column),
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (value) => setState(() {
                                        if (value == null) {
                                          _sortColumns.remove(section.key);
                                        } else {
                                          _sortColumns[section.key] = value;
                                        }
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SegmentedButton<bool>(
                                    segments: [
                                      ButtonSegment(
                                        value: true,
                                        icon: const Icon(Icons.arrow_upward),
                                        label: AppText(
                                          _bi(context, 'تصاعدي', 'Ascending'),
                                        ),
                                      ),
                                      ButtonSegment(
                                        value: false,
                                        icon: const Icon(Icons.arrow_downward),
                                        label: AppText(
                                          _bi(context, 'تنازلي', 'Descending'),
                                        ),
                                      ),
                                    ],
                                    selected: {
                                      _sortAscending[section.key] ?? true,
                                    },
                                    onSelectionChanged: (value) => setState(
                                      () => _sortAscending[section.key] =
                                          value.first,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: AppText(_bi(context, 'إلغاء', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _result()),
          icon: const Icon(Icons.check),
          label: AppText(_bi(context, 'تطبيق التخصيص', 'Apply customization')),
        ),
      ],
    );
  }
}
