import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_tenant_context.dart';

/// Cloud-first gateway for normalized PostgreSQL master data.
/// PostgreSQL is authoritative; protected writes use tenant-scoped RPCs.
class CloudMasterDataService {
  CloudMasterDataService._();

  static final CloudMasterDataService instance = CloudMasterDataService._();

  SupabaseClient get _client => Supabase.instance.client;

  final Map<String, int> _knownVersions = <String, int>{};
  final Map<String, Future<List<Map<String, dynamic>>>> _listInFlight =
      <String, Future<List<Map<String, dynamic>>>>{};

  String _versionKey(String table, String id) => '$_companyId::$table::$id';

  void _rememberVersion(String table, Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final version = _versionOf(row['_cloudVersion']);
    if (id.isNotEmpty && version != null) {
      _knownVersions[_versionKey(table, id)] = version;
    }
  }

  String get _companyId {
    final value = CloudTenantContext.instance.companyUuid;
    if (value == null || value.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.');
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> list(String table) {
    final companyId = _companyId;
    final key = '$companyId::$table';
    final active = _listInFlight[key];
    if (active != null) return active;
    final request = _listNow(table, companyId);
    _listInFlight[key] = request;
    return request.whenComplete(() {
      if (identical(_listInFlight[key], request)) {
        final _ = _listInFlight.remove(key);
      }
    });
  }

  Future<List<Map<String, dynamic>>> _listNow(
    String table,
    String companyId,
  ) async {
    try {
      final rows = await _client.rpc(
        'erp_r15_list_cloud_master_records',
        params: {'p_company_id': companyId, 'p_table': table},
      );
      if (rows is! List) {
        throw StateError(
          'cloud_master_list_invalid_response table=$table type=${rows.runtimeType}',
        );
      }
      final result = rows
          .whereType<Map>()
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      for (final row in result) {
        _rememberVersion(table, row);
      }
      return result;
    } on PostgrestException catch (error) {
      throw StateError(_readErrorMessage('list', table, error));
    }
  }

  Future<List<Map<String, dynamic>>> listWhere(
    String table, {
    required String field,
    required String value,
    String? orderByDataField,
  }) async {
    try {
      final rows = await _client.rpc(
        'erp_r49_list_cloud_master_where',
        params: {
          'p_company_id': _companyId,
          'p_table': table,
          'p_field': field,
          'p_value': value,
        },
      );
      if (rows is! List) {
        throw StateError(
          'cloud_master_filter_invalid_response table=$table field=$field type=${rows.runtimeType}',
        );
      }
      final filtered = rows
          .whereType<Map>()
          .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
          .toList(growable: true);
      for (final row in filtered) {
        _rememberVersion(table, row);
      }
      if (orderByDataField != null && orderByDataField.isNotEmpty) {
        filtered.sort(
          (a, b) => (a[orderByDataField]?.toString() ?? '').compareTo(
            b[orderByDataField]?.toString() ?? '',
          ),
        );
      }
      return List<Map<String, dynamic>>.unmodifiable(filtered);
    } on PostgrestException catch (error) {
      throw StateError(_readErrorMessage('filter', table, error));
    }
  }

  Future<Map<String, dynamic>?> getById(String table, String id) async {
    try {
      final row = await _client.rpc(
        'erp_r15_get_cloud_master_record',
        params: {
          'p_company_id': _companyId,
          'p_table': table,
          'p_record_id': id,
        },
      );
      if (row == null) return null;
      if (row is! Map) {
        throw StateError(
          'cloud_master_get_invalid_response table=$table id=$id type=${row.runtimeType}',
        );
      }
      final result = Map<String, dynamic>.from(row);
      _rememberVersion(table, result);
      return result;
    } on PostgrestException catch (error) {
      throw StateError(_readErrorMessage('get', table, error, recordId: id));
    }
  }

  Future<void> upsert(
    String table,
    String id,
    Map<String, dynamic> data,
  ) async {
    var expectedVersion = _versionOf(data['_cloudVersion']);
    expectedVersion ??= _knownVersions[_versionKey(table, id)];
    if (expectedVersion == null) {
      final current = await getById(table, id);
      expectedVersion = _versionOf(current?['_cloudVersion']);
    }
    try {
      final response = await _client.rpc(
        'erp_r15_upsert_cloud_master_record',
        params: {
          'p_company_id': _companyId,
          'p_table': table,
          'p_record_id': id,
          'p_data': Map<String, dynamic>.from(data)
            ..remove('_cloudVersion')
            ..remove('_cloudUpdatedAt'),
          'p_expected_version': expectedVersion,
        },
      );
      if (response is Map) {
        final version = _versionOf(response['version']);
        if (version != null) {
          _knownVersions[_versionKey(table, id)] = version;
        }
      }
    } on PostgrestException catch (error) {
      if (error.code == '40001') {
        _knownVersions.remove(_versionKey(table, id));
      }
      throw StateError(_writeErrorMessage(error));
    }
  }

  Future<void> delete(String table, String id) async {
    final current = await getById(table, id);
    if (current == null) {
      throw StateError('السجل غير موجود أو تم حذفه مسبقاً.');
    }
    try {
      await _client.rpc(
        'erp_r15_soft_delete_cloud_master_record',
        params: {
          'p_company_id': _companyId,
          'p_table': table,
          'p_record_id': id,
          'p_expected_version': _versionOf(current['_cloudVersion']),
        },
      );
    } on PostgrestException catch (error) {
      throw StateError(_writeErrorMessage(error));
    }
    _knownVersions.remove(_versionKey(table, id));
  }

  int? _versionOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String _readErrorMessage(
    String operation,
    String table,
    PostgrestException error, {
    String? recordId,
  }) {
    final parts = <String>[
      'cloud_master_$operation',
      'table=$table',
      if (recordId != null) 'id=$recordId',
      if ((error.code ?? '').isNotEmpty) 'code=${error.code}',
      'message=${error.message}',
      if ((error.details?.toString() ?? '').trim().isNotEmpty)
        'details=${error.details}',
      if ((error.hint?.toString() ?? '').trim().isNotEmpty)
        'hint=${error.hint}',
    ];
    return parts.join(' | ');
  }

  String _writeErrorMessage(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (error.code == '42501' ||
        message.contains('permission_denied') ||
        message.contains('company_membership_required')) {
      return 'لا تملك صلاحية تعديل بيانات هذه الشركة. أعد تسجيل الدخول أو راجع عضوية المستخدم.';
    }
    if (message.contains('deleted_master_record_requires_explicit_restore')) {
      return 'هذا السجل محذوف فعلياً ولا يمكن إعادته بالحفظ. استخدم الاستعادة الصريحة من سلة المحذوفات.';
    }
    if (message.contains('expected_version_required') ||
        message.contains('stale_master_record')) {
      return 'البيانات المعروضة أقدم من النسخة الحالية في Supabase. حدّث الشاشة ثم أعد المحاولة حتى لا تتم الكتابة فوق بيانات أحدث.';
    }
    if (message.contains('partner_name_required') ||
        message.contains('partner_name_and_phone_required')) {
      return 'اسم الشريك التجاري مطلوب.';
    }
    if (message.contains('warehouse_code_and_name_required')) {
      return 'رمز المخزن واسمه مطلوبان.';
    }
    if (message.contains('warehouse_branch_not_found')) {
      return 'الفرع المحدد للمخزن غير موجود أو غير فعال.';
    }
    if (message.contains('warehouse_code_already_exists')) {
      return 'رمز المخزن مستخدم مسبقاً داخل الشركة.';
    }
    if (message.contains('warehouse_has_active_inventory')) {
      return 'لا يمكن حذف مخزن مرتبط بسيارات أو أرصدة مخزون.';
    }
    if (message.contains('inventory_group_has_products')) {
      return 'لا يمكن حذف مجموعة مرتبطة بمنتجات.';
    }
    final details = '${error.details} ${error.hint}'.toLowerCase();
    if (error.code == '23505' || message.contains('duplicate key')) {
      if (details.contains('erp_cars_company_chassis_key') ||
          message.contains('erp_cars_company_chassis_key')) {
        return 'رقم الشاصي مستخدم في سيارة فعالة أخرى.';
      }
      if (details.contains('erp_cars_company_plate_key') ||
          message.contains('erp_cars_company_plate_key')) {
        return 'رقم اللوحة مستخدم في سيارة فعالة أخرى.';
      }
      if (details.contains('erp_inventory_code_uq') ||
          message.contains('erp_inventory_code_uq')) {
        return 'توجد بيانات مكررة لمنتج فعال آخر.';
      }
      if (details.contains('erp_inventory_sku_uq') ||
          message.contains('erp_inventory_sku_uq')) {
        return 'توجد بيانات مكررة لمنتج فعال آخر.';
      }
      if (details.contains('erp_inventory_barcode_uq') ||
          message.contains('erp_inventory_barcode_uq')) {
        return 'الباركود مستخدم في منتج فعال آخر.';
      }
      if (details.contains('erp_inventory_serial_uq') ||
          message.contains('erp_inventory_serial_uq')) {
        return 'توجد بيانات مكررة لمنتج فعال آخر.';
      }
      return 'توجد بيانات فعالة أخرى تحمل القيمة نفسها.';
    }
    return 'تعذر حفظ البيانات في Supabase: ${error.message}';
  }

  /// Returns authoritative cloud tombstones for cache reconciliation.
  Future<Set<String>> deletedIds(String table) async {
    try {
      final rows = await _client.rpc(
        'erp_r15_list_deleted_master_ids',
        params: {'p_company_id': _companyId, 'p_table': table},
      );
      if (rows is! List) {
        throw StateError(
          'cloud_master_tombstones_invalid_response table=$table type=${rows.runtimeType}',
        );
      }
      return rows
          .map((value) => value?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } on PostgrestException catch (error) {
      throw StateError(_readErrorMessage('tombstones', table, error));
    }
  }

  /// Creates a tombstone in the compatibility cloud store.
  Future<void> deleteLegacyRecord({
    required String entityType,
    required String recordId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _client
        .from('erp_records')
        .update({'deleted_at': now, 'updated_at': now})
        .eq('company_id', _companyId)
        .eq('entity_type', entityType)
        .eq('record_id', recordId)
        .select('record_id');
    if ((updated as List).isEmpty) {
      throw StateError(
        'Cloud child record was not found in the active company.',
      );
    }
  }

  /// Checks the compatibility cloud store for an active record that references
  /// [value] in its JSON payload. This is used while transactional modules are
  /// being migrated from `erp_records` to normalized PostgreSQL tables.
  Future<bool> hasActiveLegacyReference({
    required String entityType,
    required String field,
    required String value,
    Map<String, String> equals = const <String, String>{},
  }) async {
    dynamic query = _client
        .from('erp_records')
        .select('record_id')
        .eq('company_id', _companyId)
        .eq('entity_type', entityType)
        .isFilter('deleted_at', null)
        .eq('payload->>$field', value);
    for (final entry in equals.entries) {
      query = query.eq('payload->>${entry.key}', entry.value);
    }
    final rows = await query.limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Returns active compatibility-record IDs referencing [value].
  Future<List<String>> activeLegacyReferenceIds({
    required String entityType,
    required String field,
    required String value,
  }) async {
    final rows = await _client
        .from('erp_records')
        .select('record_id')
        .eq('company_id', _companyId)
        .eq('entity_type', entityType)
        .isFilter('deleted_at', null)
        .eq('payload->>$field', value);
    return (rows as List)
        .map((row) => (row as Map)['record_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  RealtimeChannel subscribe({
    required String table,
    required void Function() onChanged,
  }) {
    return _client
        .channel('$table-$_companyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'company_id',
            value: _companyId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }
}
