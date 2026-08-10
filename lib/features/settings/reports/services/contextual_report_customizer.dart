import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';

/// Applies user-defined report projection, filtering, sorting and row limits
/// without mutating the complete source data returned by Supabase.
class ContextualReportCustomizer {
  const ContextualReportCustomizer();

  List<ContextualReportSection> apply(
    List<ContextualReportSection> sections,
    ReportExportOptions options,
  ) {
    return sections
        .where((section) => options.sectionEnabled[section.key] ?? true)
        .map((section) {
          final requested =
              options.selectedColumns[section.key] ?? const <String>[];
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
              .where(
                (index) => !_isHiddenColumn(section, section.columns[index]),
              )
              .toList(growable: false);

          final query = (options.sectionQueries[section.key] ?? '')
              .trim()
              .toLowerCase();
          var rows = section.rows
              .where((row) {
                if (query.isEmpty) return true;
                return row.any((value) => value.toLowerCase().contains(query));
              })
              .toList(growable: false);

          final sortColumn = options.sortColumns[section.key];
          final sortIndex = sortColumn == null
              ? -1
              : section.columns.indexOf(sortColumn);
          if (sortIndex >= 0) {
            final ascending = options.sortAscending[section.key] ?? true;
            rows = [...rows]
              ..sort((left, right) {
                final a = sortIndex < left.length ? left[sortIndex] : '';
                final b = sortIndex < right.length ? right[sortIndex] : '';
                final numericA = num.tryParse(a.replaceAll(',', ''));
                final numericB = num.tryParse(b.replaceAll(',', ''));
                final result = numericA != null && numericB != null
                    ? numericA.compareTo(numericB)
                    : a.toLowerCase().compareTo(b.toLowerCase());
                return ascending ? result : -result;
              });
          }

          final rowLimit = options.sectionRowLimits[section.key] ?? 0;
          if (rowLimit > 0 && rows.length > rowLimit) {
            rows = rows.take(rowLimit).toList(growable: false);
          }

          return ContextualReportSection(
            key: section.key,
            title: section.title,
            columns: safeIndexes
                .map((index) => section.columns[index])
                .toList(growable: false),
            rows: rows
                .map(
                  (row) => safeIndexes
                      .map((index) => index < row.length ? row[index] : '')
                      .toList(growable: false),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  static bool _isHiddenColumn(ContextualReportSection section, String column) {
    final normalized = column
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    if (normalized == 'id') return true;
    const retiredCatalogFields = <String>{
      'productcode',
      'sku',
      'internalcode',
      'serialnumber',
      'nameen',
      'englishname',
    };
    final sectionToken = '${section.key} ${section.title}'.toLowerCase();
    final productSection =
        sectionToken.contains('product') ||
        sectionToken.contains('منتج') ||
        sectionToken.contains('مادة');
    if (productSection &&
        const {'description', 'الوصف'}.contains(column.trim().toLowerCase())) {
      return true;
    }
    return normalized.endsWith('id') ||
        normalized.contains('uuid') ||
        normalized.contains('payload') ||
        normalized.contains('rawdata') ||
        normalized.contains('verification') ||
        retiredCatalogFields.contains(normalized);
  }
}
