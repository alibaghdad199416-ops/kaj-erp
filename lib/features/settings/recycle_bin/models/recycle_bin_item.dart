class RecycleBinItem {
  const RecycleBinItem({
    required this.archiveId,
    required this.entityType,
    required this.recordId,
    required this.title,
    required this.deletedAt,
    required this.payload,
    this.deletedBy,
    this.sourceTable = '',
    this.deletionMode = 'soft',
    this.deletionBatchId,
    this.rootSourceTable,
    this.rootRecordId,
    this.deleteReason,
    this.relatedCount = 1,
  });

  final String? archiveId;
  final String entityType;
  final String recordId;
  final String title;
  final DateTime? deletedAt;
  final String? deletedBy;
  final Map<String, dynamic> payload;
  final String sourceTable;
  final String deletionMode;
  final String? deletionBatchId;
  final String? rootSourceTable;
  final String? rootRecordId;
  final String? deleteReason;
  final int relatedCount;

  bool get isBatch => relatedCount > 1 || deletionBatchId != null;

  factory RecycleBinItem.fromMap(Map<String, dynamic> map) {
    final payload = Map<String, dynamic>.from(
      map['payload'] as Map? ?? const {},
    );
    String firstText(Iterable<String> keys) {
      for (final key in keys) {
        final value = payload[key]?.toString().trim() ?? '';
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return '';
    }

    final title = firstText(const [
      'nameAr',
      'name',
      'title',
      'order_number',
      'orderNumber',
      'document_number',
      'documentNumber',
      'invoice_number',
      'invoiceNumber',
      'number',
      'code',
      'fullName',
      'model',
      'sku',
      'chassisNumber',
    ]);
    return RecycleBinItem(
      archiveId: _nullableText(map['archive_id']),
      entityType: map['entity_type']?.toString() ?? '',
      recordId: map['record_id']?.toString() ?? '',
      title: title.isEmpty ? map['record_id']?.toString() ?? '' : title,
      deletedAt: DateTime.tryParse(map['deleted_at']?.toString() ?? ''),
      deletedBy: map['deleted_by']?.toString(),
      payload: payload,
      sourceTable: map['source_table']?.toString() ?? '',
      deletionMode: map['deletion_mode']?.toString() ?? 'soft',
      deletionBatchId: _nullableText(map['deletion_batch_id']),
      rootSourceTable: _nullableText(map['root_source_table']),
      rootRecordId: _nullableText(map['root_record_id']),
      deleteReason: _nullableText(map['delete_reason']),
      relatedCount: (map['related_count'] as num?)?.toInt() ?? 1,
    );
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
  }
}
