import 'package:intl/intl.dart';

import 'export_document.dart';

/// Centralizes values shown by every export format so PDF and Excel remain
/// consistent for dates, numbers, booleans and IQD/USD amounts.
class ReportTemplateEngine {
  const ReportTemplateEngine();

  String formatValue(Object? value, ExportColumn column, ExportDocument doc) {
    if (value == null) return '';
    final locale = doc.isArabic ? 'ar' : 'en_US';
    switch (column.type) {
      case ExportValueType.integer:
        return NumberFormat.decimalPattern(locale).format(_number(value));
      case ExportValueType.decimal:
        return NumberFormat('#,##0.00', locale).format(_number(value));
      case ExportValueType.money:
        final currency = (doc.currency ?? '').trim().toUpperCase();
        final pattern = currency.toUpperCase() == 'IQD' ? '#,##0' : '#,##0.00';
        return '${NumberFormat(pattern, locale).format(_number(value))} $currency';
      case ExportValueType.date:
        final parsed = _date(value);
        return parsed == null
            ? ''
            : DateFormat('yyyy-MM-dd', locale).format(parsed);
      case ExportValueType.dateTime:
        final parsed = _date(value);
        return parsed == null
            ? ''
            : DateFormat('yyyy-MM-dd HH:mm', locale).format(parsed);
      case ExportValueType.boolean:
        final enabled = value == true || value.toString() == '1';
        if (doc.isArabic) return enabled ? 'نعم' : 'لا';
        return enabled ? 'Yes' : 'No';
      case ExportValueType.text:
        return value.toString();
    }
  }

  String fileName(ExportDocument doc, String extension) {
    final safe = doc.title
        .trim()
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final stamp = DateFormat(
      'yyyyMMdd-HHmm',
    ).format(doc.generatedAt ?? DateTime.now());
    return '${safe.isEmpty ? 'quality-line-report' : safe}-$stamp.$extension';
  }

  num _number(Object value) =>
      value is num ? value : num.tryParse('$value') ?? 0;

  DateTime? _date(Object value) {
    if (value is DateTime) return value;
    final raw = '$value'.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
