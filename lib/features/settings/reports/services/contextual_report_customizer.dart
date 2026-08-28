import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';

/// Applies report projection, filtering, sorting and row limits through the
/// same unified filtering engine used by ERP module screens.
///
/// Persisted ReportExportOptions remains backward compatible. New section
/// filters use the generic field dimensions of the unified filter engine.
class ContextualReportCustomizer {
  const ContextualReportCustomizer();

  List<ContextualReportSection> apply(
    List<ContextualReportSection> sections,
    ReportExportOptions options,
  ) {
    return sections
        .where((section) => options.sectionEnabled[section.key] ?? true)
        .map((section) => _applySection(section, options))
        .toList(growable: false);
  }

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
    // A preset may have been saved before an internal column was retired or
    // hidden. Never emit a section with zero visible columns: fall back to the
    // current public projection while preserving the user's query/sort state.
    final visibleIndexes = safeIndexes.isEmpty
        ? List<int>.generate(section.columns.length, (index) => index)
              .where(
                (index) => !_isHiddenColumn(section, section.columns[index]),
              )
              .toList(growable: false)
        : safeIndexes;

    final query = (options.sectionQueries[section.key] ?? '').trim();
    final sortField = options.sortColumns[section.key];
    final sortAscending = options.sortAscending[section.key] ?? true;
    final sorts = <UnifiedSortCriterion<List<String>>>[
      if (sortField != null && sortField.isNotEmpty)
        if (section.columns.contains(sortField))
          UnifiedSortCriterion<List<String>>(
            key: sortField,
            direction: sortAscending
                ? UnifiedSortDirection.ascending
                : UnifiedSortDirection.descending,
            value: (row) =>
                _sortableValue(row, section.columns.indexOf(sortField)),
          ),
    ];

    final filterTokens = options.sectionFilters[section.key] ?? const [];
    final fieldFilters = <String, Set<String>>{};
    for (final token in filterTokens) {
      final values = fieldFilters.putIfAbsent(token.key, () => <String>{});
      values.add(token.value.toString());
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
    // Business-facing product references and descriptions are report data.
    // Only technical identifiers/raw payload columns are suppressed.
    return normalized == 'id' ||
        normalized.endsWith('id') ||
        normalized.contains('uuid') ||
        normalized.contains('payload') ||
        normalized.contains('rawdata') ||
        normalized.contains('verification');
  }
}
