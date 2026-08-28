import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/services/report_field_localizer.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';

/// Report customization surface backed by the same query state used by ERP lists.
/// Presentation-only controls (columns, section visibility and row limit) are
/// projected into [ReportExportOptions] when the dialog is submitted.
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
  late final Map<String, UnifiedQueryController> _queries;
  late final Map<String, Set<String>> _selectedColumns;
  late final Map<String, TextEditingController> _rowLimits;
  late final Map<String, bool> _sectionEnabled;

  @override
  void initState() {
    super.initState();
    _queries = {
      for (final section in widget.sections)
        section.key: UnifiedQueryController(
          UnifiedQueryState(
            search: widget.initialOptions.sectionQueries[section.key] ?? '',
            filters:
                widget.initialOptions.sectionFilters[section.key] ?? const [],
            sorts: _initialSorts(section.key),
          ),
        ),
    };
    _selectedColumns = {
      for (final section in widget.sections)
        section.key:
            (widget.initialOptions.selectedColumns[section.key] ??
                    section.columns)
                .toSet(),
    };
    _rowLimits = {
      for (final section in widget.sections)
        section.key: TextEditingController(
          text: '${widget.initialOptions.sectionRowLimits[section.key] ?? 0}',
        ),
    };
    _sectionEnabled = {
      for (final section in widget.sections)
        section.key: widget.initialOptions.sectionEnabled[section.key] ?? true,
    };
  }

  List<UnifiedSortRule> _initialSorts(String key) {
    final field = widget.initialOptions.sortColumns[key];
    if (field == null || field.isEmpty) return const [];
    return [
      UnifiedSortRule(
        field: field,
        label: field,
        descending: widget.initialOptions.sortAscending[key] == false,
      ),
    ];
  }

  bool _isInternalColumn(String column) {
    final normalized = column
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    return normalized == 'id' ||
        normalized.endsWith('id') ||
        normalized.contains('uuid') ||
        normalized.contains('payload') ||
        normalized.contains('rawdata');
  }

  List<UnifiedQueryFilterOption> _filterOptions(
    BuildContext context,
    ContextualReportSection section,
  ) {
    final options = <UnifiedQueryFilterOption>[];
    for (
      var columnIndex = 0;
      columnIndex < section.columns.length;
      columnIndex++
    ) {
      final column = section.columns[columnIndex];
      if (column.trim().isEmpty || _isInternalColumn(column)) continue;
      final values = <String>{};
      for (final row in section.rows) {
        if (columnIndex >= row.length) continue;
        final value = row[columnIndex].trim();
        if (value.isNotEmpty) values.add(value);
        if (values.length >= 20) break;
      }
      for (final value in values.take(20)) {
        options.add(
          UnifiedQueryFilterOption(
            token: UnifiedFilterToken(
              key: column,
              label: _label(context, column),
              value: value,
              valueLabel: value,
            ),
            icon: Icons.filter_alt_outlined,
          ),
        );
      }
    }
    return options;
  }

  ReportExportOptions _result() {
    final sortColumns = <String, String>{};
    final sortAscending = <String, bool>{};
    final sectionQueries = <String, String>{};
    final sectionFilters = <String, List<UnifiedFilterToken>>{};

    for (final section in widget.sections) {
      final query = _queries[section.key]!.state;
      if (query.search.trim().isNotEmpty) {
        sectionQueries[section.key] = query.search.trim();
      }
      if (query.filters.isNotEmpty) {
        sectionFilters[section.key] = List<UnifiedFilterToken>.unmodifiable(
          query.filters,
        );
      }
      if (query.sorts.isNotEmpty) {
        final sort = query.sorts.first;
        sortColumns[section.key] = sort.field;
        sortAscending[section.key] = !sort.descending;
      }
    }

    return widget.initialOptions.copyWith(
      selectedColumns: {
        for (final section in widget.sections)
          section.key: section.columns
              .where(_selectedColumns[section.key]!.contains)
              .toList(growable: false),
      },
      sectionQueries: sectionQueries,
      sectionFilters: sectionFilters,
      sortColumns: sortColumns,
      sortAscending: sortAscending,
      sectionEnabled: Map<String, bool>.from(_sectionEnabled),
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

  String _label(BuildContext context, String value) =>
      ReportFieldLocalizer.localize(value, context.l10n.isArabic ? 'ar' : 'en');

  List<UnifiedQuerySortOption> _sortOptions(
    BuildContext context,
    ContextualReportSection section,
  ) => [
    for (final column in section.columns)
      if (!_isInternalColumn(column))
        UnifiedQuerySortOption(
          rule: UnifiedSortRule(field: column, label: _label(context, column)),
          icon: Icons.sort,
        ),
  ];

  @override
  void dispose() {
    for (final controller in _rowLimits.values) {
      controller.dispose();
    }
    for (final controller in _queries.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: AppText(
        _bi(context, 'تخصيص بيانات التقرير', 'Customize report data'),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, 900),
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
                  final controller = _queries[section.key]!;
                  final selected = _selectedColumns[section.key]!;
                  final enabled = _sectionEnabled[section.key] ?? true;
                  return AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => Opacity(
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
                              _label(context, section.title),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
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
                                UnifiedQueryToolbar(
                                  controller: controller,
                                  searchHint: _bi(
                                    context,
                                    'بحث في بيانات القسم',
                                    'Search section data',
                                  ),
                                  filters: _filterOptions(context, section),
                                  sorts: _sortOptions(context, section),
                                  compact: true,
                                  padding: EdgeInsets.zero,
                                  filterButtonLabel: _bi(
                                    context,
                                    'فلترة',
                                    'Filter',
                                  ),
                                  sortButtonLabel: _bi(context, 'فرز', 'Sort'),
                                  clearAllLabel: _bi(
                                    context,
                                    'مسح البحث والفرز والفلترة',
                                    'Clear query',
                                  ),
                                  clearSearchTooltip: _bi(
                                    context,
                                    'مسح البحث',
                                    'Clear search',
                                  ),
                                  ascendingLabel: _bi(
                                    context,
                                    'تصاعدي',
                                    'Ascending',
                                  ),
                                  descendingLabel: _bi(
                                    context,
                                    'تنازلي',
                                    'Descending',
                                  ),
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
                                        _bi(
                                          context,
                                          'اختيار الكل',
                                          'Select all',
                                        ),
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
                                          'إبقاء حقل واحد',
                                          'Keep one field',
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    SizedBox(
                                      width: 180,
                                      child: TextField(
                                        controller: _rowLimits[section.key],
                                        keyboardType: TextInputType.number,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: _bi(
                                            context,
                                            'حد الصفوف (0 = الكل)',
                                            'Row limit (0 = all)',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: section.columns
                                      .map(
                                        (column) => FilterChip(
                                          label: AppText(
                                            _label(context, column),
                                          ),
                                          selected: selected.contains(column),
                                          onSelected: (value) => setState(() {
                                            if (value) {
                                              selected.add(column);
                                            } else if (selected.length > 1) {
                                              selected.remove(column);
                                            }
                                          }),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
