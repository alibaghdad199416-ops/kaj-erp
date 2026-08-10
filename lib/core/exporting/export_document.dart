/// A transport-neutral document used by PDF, Excel, CSV and print exporters.
class ExportDocument {
  const ExportDocument({
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.metadata = const {},
    this.language = 'ar',
    this.currency,
    this.generatedAt,
  });

  final String title;
  final String? subtitle;
  final List<ExportColumn> columns;
  final List<List<Object?>> rows;
  final Map<String, Object?> metadata;
  final String language;
  final String? currency;
  final DateTime? generatedAt;

  bool get isArabic => language.toLowerCase().startsWith('ar');

  void validate() {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Document title is required.');
    }
    if (columns.isEmpty) {
      throw StateError('At least one export column is required.');
    }
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].length != columns.length) {
        throw StateError(
          'Row $index contains ${rows[index].length} values; '
          '${columns.length} values were expected.',
        );
      }
    }
  }
}

class ExportColumn {
  const ExportColumn({
    required this.key,
    required this.label,
    this.type = ExportValueType.text,
    this.width = 1,
  });

  final String key;
  final String label;
  final ExportValueType type;
  final double width;
}

enum ExportValueType { text, integer, decimal, money, date, dateTime, boolean }

enum ExportPageFormat { a4Portrait, a4Landscape, receipt80mm }

class ExportProgress {
  const ExportProgress(this.value, this.message);
  final double value;
  final String message;
}
