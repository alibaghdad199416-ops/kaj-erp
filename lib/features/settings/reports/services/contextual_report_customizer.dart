import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';

/// Applies report projection, filtering, sorting and row limits through the
/// same unified filtering engine used by ERP module screens.
class ContextualReportCustomizer {
  const ContextualReportCustomizer();

  List<ContextualReportSection> apply(
    List<ContextualReportSection> sections,
    ReportExportOptions options,
  ) => sections
      .where((section) => options.sectionEnabled[section.key] ?? true)
      .map((section) => _applySection(section, options))
      .toList(growable: false);

  ContextualReportSection _applySection(
    ContextualReportSection section,
    ReportExportOptions options,
  ) {
    final requested = options.selectedColumns[section.key] ?? const <String>[];
    final indexes = requested.isEmpty
        ? List<int>.generate(section.columns.length, (index) => index)
        : requested
              .map(section.columns.indexOf)
              .where((index) => index >= 0)
              .toList(growable: false);
    final candidateIndexes = indexes.isEmpty
        ? List<int>.generate(section.columns.length, (index) => index)
        : indexes;
    final safeIndexes = candidateIndexes
        .where((index) => !_isHiddenColumn(section, section.columns[index]))
        .toList(growable: false);
    final visibleIndexes = safeIndexes.isEmpty
        ? List<int>.generate(section.columns.length, (index) => index)
              .where(
                (index) => !_isHiddenColumn(section, section.columns[index]),
              )
              .toList(growable: false)
        : safeIndexes;

    final query = (options.sectionQueries[section.key] ?? '').trim();
    final persistedRules = options.sortRules[section.key];
    final rules = persistedRules == null || persistedRules.isEmpty
        ? _legacySortRules(options, section.key)
        : persistedRules;
    final sorts = <UnifiedSortCriterion<List<String>>>[
      for (final rule in rules)
        if (section.columns.contains(rule.field))
          UnifiedSortCriterion<List<String>>(
            key: rule.field,
            direction: rule.descending
                ? UnifiedSortDirection.descending
                : UnifiedSortDirection.ascending,
            value: (row) => _sortableValue(
              row,
              section.columns.indexOf(rule.field),
            ),
          ),
    ];

    final filterTokens = options.sectionFilters[section.key] ?? const [];
    final fieldFilters = <String, Set<String>>{};
    for (final token in filterTokens) {
      fieldFilters.putIfAbsent(token.key, () => <String>{}).add(
        token.value.toString(),
      );
    }

    final fieldGetters = <String, Object? Function(List<String>)>{};
    for (final token in filterTokens) {
      final index = section.columns.indexOf(token.key);
      if (index >= 0) {
        fieldGetters[token.key] = (row) => index < row.length ? row[index] : '';
      }
    }

    final filteredAndSorted = UnifiedFilterEngine.apply<List<String>>(
      section.rows,
      criteria: UnifiedFilterCriteria(
        searchText: query,
        fieldValues: fieldFilters,
      ),
      adapter: UnifiedFilterAdapter<List<String>>(
        searchableText: _searchableRow,
        fieldValues: fieldGetters,
      ),
      sorts: sorts,
    );

    final rowLimit = options.sectionRowLimits[section.key] ?? 0;
    final rows = rowLimit > 0 && filteredAndSorted.length > rowLimit
        ? filteredAndSorted.take(rowLimit).toList(growable: false)
        : filteredAndSorted;

    return ContextualReportSection(
      key: section.key,
      title: section.title,
      columns: visibleIndexes
          .map((index) => section.columns[index])
          .toList(growable: false),
      rows: rows
          .map(
            (row) => visibleIndexes
                .map((index) => index < row.length ? row[index] : '')
                .toList(growable: false),
          )
          .toList(growable: false),
    );
  }

  static List<UnifiedSortRule> _legacySortRules(
    ReportExportOptions options,
    String key,
  ) {
    final field = options.sortColumns[key];
    if (field == null || field.isEmpty) return const [];
    return [
      UnifiedSortRule(
        field: field,
        label: field,
        descending: options.sortAscending[key] == false,
      ),
    ];
  }

  static Iterable<Object?> _searchableRow(List<String> row) => row;

  static Comparable<dynamic> _sortableValue(List<String> row, int index) {
    final value = index < row.length ? row[index] : '';
    final numeric = num.tryParse(value.replaceAll(',', '').trim());
    return numeric ?? UnifiedFilterEngine.normalize(value);
  }

  static bool _isHiddenColumn(ContextualReportSection section, String column) {
    final normalized = column
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    if (normalized == 'id') return true;
    return normalized.endsWith('id') ||
        normalized.contains('uuid') ||
        normalized.contains('payload') ||
        normalized.contains('rawdata') ||
        normalized.contains('verification');
  }
}
