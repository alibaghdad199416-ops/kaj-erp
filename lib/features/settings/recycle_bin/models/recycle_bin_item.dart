class RecycleBinItem {
  const RecycleBinItem({
    required this.archiveId,
    required this.entityType,
    required this.recordId,
    required this.title,
    required this.deletedAt,
    required this.payload,
    this.deletedBy,
    this.deletedByName,
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
  final String? deletedByName;
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
      'brand',
      'model',
      'sku',
      'chassisNumber',
    ]);
    final deletedByName = _firstNonUuidText(<Object?>[
      map['deleted_by_name'],
      map['deletedByName'],
      payload['deleted_by_name'],
      payload['deletedByName'],
      payload['created_by_name'],
      payload['createdByName'],
    ]);
    final entityType = map['entity_type']?.toString() ?? '';
    final recordId = map['record_id']?.toString() ?? '';
    final titleValue = title.isEmpty
        ? '${_humanReference(entityType)}${_shortRecordSuffix(recordId)}'
        : title;

    return RecycleBinItem(
      archiveId: _nullableText(map['archive_id']),
      entityType: entityType,
      recordId: recordId,
      title: titleValue,
      deletedAt: DateTime.tryParse(map['deleted_at']?.toString() ?? ''),
      deletedBy: _nullableText(map['deleted_by']),
      deletedByName: deletedByName,
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

  static String? _firstNonUuidText(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      if (_looksLikeUuid(text)) continue;
      return text;
    }
    return null;
  }

  static String _shortRecordSuffix(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (!_looksLikeUuid(text)) return '';
    return ' — ${text.substring(0, 8)}';
  }

  static bool _looksLikeUuid(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  static String _humanReference(String entityType) {
    const labels = <String, String>{
      'cars': 'سيارة',
      'products': 'منتج',
      'customers': 'عميل',
      'suppliers': 'مورد',
      'sales': 'عملية بيع',
      'purchases': 'عملية شراء',
      'maintenanceOrders': 'أمر صيانة',
      'expenses': 'مصروف',
      'warehouseTransfers': 'نقل مخزني',
    };
    return labels[entityType] ??
        (entityType.trim().isEmpty ? 'سجل محذوف' : entityType);
  }

  static String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
  }
}
