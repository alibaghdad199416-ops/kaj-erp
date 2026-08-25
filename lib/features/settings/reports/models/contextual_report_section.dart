class ContextualReportSection {
  const ContextualReportSection({
    required this.key,
    required this.title,
    required this.columns,
    required this.rows,
  });

  final String key;
  final String title;
  final List<String> columns;
  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;
}
