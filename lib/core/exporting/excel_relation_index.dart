import 'export_document.dart';

/// Builds a human-readable relation index for every generic workbook.
///
/// Relations are inferred from stable document-number fields and explicit
/// metadata. The output intentionally contains business references rather than
/// internal UUIDs so exported workbooks remain understandable outside the ERP.
abstract final class ExcelRelationIndex {
  static List<List<Object?>> build(ExportDocument document) {
    final rows = <List<Object?>>[];
    final referenceColumns = <int>[];
    for (var index = 0; index < document.columns.length; index++) {
      final column = document.columns[index];
      final normalized = '${column.key} ${column.label}'.toLowerCase();
      if (_relationTerms.any(normalized.contains)) referenceColumns.add(index);
    }

    for (var rowIndex = 0; rowIndex < document.rows.length; rowIndex++) {
      final row = document.rows[rowIndex];
      final source = _sourceReference(document, row, rowIndex);
      for (final columnIndex in referenceColumns) {
        final value = row[columnIndex]?.toString().trim() ?? '';
        if (value.isEmpty || value.toLowerCase() == 'null') continue;
        final column = document.columns[columnIndex];
        rows.add(<Object?>[
          document.title,
          source,
          column.label,
          value,
          _linkedModule('${column.key} ${column.label}'),
        ]);
      }
    }

    for (final entry in document.metadata.entries) {
      final value = entry.value?.toString().trim() ?? '';
      if (value.isEmpty ||
          !_relationTerms.any(entry.key.toLowerCase().contains)) {
        continue;
      }
      rows.add(<Object?>[
        document.title,
        document.subtitle ?? document.title,
        entry.key,
        value,
        _linkedModule(entry.key),
      ]);
    }
    return rows;
  }

  static String _sourceReference(
    ExportDocument document,
    List<Object?> row,
    int rowIndex,
  ) {
    for (var index = 0; index < document.columns.length; index++) {
      final normalized =
          '${document.columns[index].key} ${document.columns[index].label}'
              .toLowerCase();
      if (normalized.contains('documentnumber') ||
          normalized.contains('order number') ||
          normalized.contains('رقم المستند') ||
          normalized.contains('رقم الأمر') ||
          normalized.contains('voucher') ||
          normalized.contains('رقم السند')) {
        final value = row[index]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    return '#${rowIndex + 1}';
  }

  static String _linkedModule(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('opportunity') || normalized.contains('فرص'))
      return 'CRM';
    if (normalized.contains('sales') || normalized.contains('بيع'))
      return 'Sales';
    if (normalized.contains('purchase') || normalized.contains('شراء'))
      return 'Purchases';
    if (normalized.contains('invoice') || normalized.contains('فاتورة'))
      return 'Invoicing';
    if (normalized.contains('payment') ||
        normalized.contains('voucher') ||
        normalized.contains('دفعة') ||
        normalized.contains('سند'))
      return 'Accounting';
    if (normalized.contains('movement') ||
        normalized.contains('warehouse') ||
        normalized.contains('transfer') ||
        normalized.contains('مخزن') ||
        normalized.contains('تحويل'))
      return 'Inventory';
    if (normalized.contains('vehicle') ||
        normalized.contains('chassis') ||
        normalized.contains('سيارة') ||
        normalized.contains('هيكل'))
      return 'Vehicles';
    if (normalized.contains('maintenance') || normalized.contains('صيانة'))
      return 'Maintenance';
    if (normalized.contains('journal') ||
        normalized.contains('entry') ||
        normalized.contains('قيد'))
      return 'Accounting';
    return 'Related records';
  }

  static const _relationTerms = <String>[
    'linked',
    'reference',
    'document',
    'order',
    'invoice',
    'payment',
    'voucher',
    'movement',
    'transfer',
    'opportunity',
    'sales',
    'purchase',
    'vehicle',
    'chassis',
    'maintenance',
    'journal',
    'entry',
    'مرتبط',
    'مرجع',
    'مستند',
    'أمر',
    'فاتورة',
    'دفعة',
    'سند',
    'حركة',
    'تحويل',
    'فرصة',
    'بيع',
    'شراء',
    'سيارة',
    'هيكل',
    'صيانة',
    'قيد',
  ];
}
