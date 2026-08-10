import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/features/settings/models/backup_model.dart';
import 'package:quality_line_erp/features/settings/models/branch_model.dart';
import 'package:quality_line_erp/features/settings/models/company_settings_model.dart';
import 'package:quality_line_erp/features/settings/models/currency_model.dart';

class SettingsRepository {
  final CloudFeatureCommand _cloud = CloudFeatureCommand.instance;

  Future<CompanySettingsModel> getCompanySettings() async {
    final response = await Supabase.instance.client.rpc(
      'erp_get_cloud_company_settings',
    );
    final row = Map<String, dynamic>.from(response as Map);
    return CompanySettingsModel.fromSettingsMap(
      row.map((key, value) => MapEntry(key, value?.toString() ?? '')),
    );
  }

  Future<void> saveCompanySettings(CompanySettingsModel settings) =>
      Supabase.instance.client.rpc(
        'erp_save_cloud_company_settings',
        params: {'p_settings': settings.toSettingsMap()},
      );

  Future<List<BranchModel>> getBranches() async {
    final response = await Supabase.instance.client.rpc(
      'erp_list_cloud_branches',
    );
    return List<Map<String, dynamic>>.from(
      (response as List).map((row) => Map<String, dynamic>.from(row as Map)),
    ).map(BranchModel.fromMap).toList(growable: false);
  }

  Future<void> saveBranch(BranchModel branch) => Supabase.instance.client.rpc(
    'erp_save_cloud_branch',
    params: {
      'p_id': branch.id,
      'p_name': branch.name,
      'p_code': branch.code,
      'p_phone': branch.phone,
      'p_address': branch.address,
      'p_is_main': branch.isMain,
      'p_is_active': branch.isActive,
      'p_created_at': branch.createdAt.toUtc().toIso8601String(),
      'p_updated_at': (branch.updatedAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
    },
  );

  Future<void> deleteBranch(String id) => Supabase.instance.client.rpc(
    'erp_delete_cloud_branch',
    params: {'p_id': id},
  );

  Future<List<CurrencyModel>> getCurrencies() async {
    final response = await Supabase.instance.client.rpc(
      'erp_list_cloud_currencies',
    );
    return List<Map<String, dynamic>>.from(
      (response as List).map((row) => Map<String, dynamic>.from(row as Map)),
    ).map(CurrencyModel.fromMap).toList(growable: false);
  }

  Future<void> saveCurrency(CurrencyModel currency) =>
      Supabase.instance.client.rpc(
        'erp_save_cloud_currency',
        params: {
          'p_code': currency.code.trim().toUpperCase(),
          'p_name': currency.name.trim(),
          'p_symbol': currency.symbol.trim(),
          'p_exchange_rate': currency.exchangeRate,
          'p_is_base': currency.isBase,
          'p_is_active': currency.isActive,
        },
      );

  Future<void> deleteCurrency(String code) => Supabase.instance.client.rpc(
    'erp_delete_cloud_currency',
    params: {'p_code': code.trim().toUpperCase()},
  );

  Future<List<BackupModel>> getBackups() async =>
      (await _cloud.list('backup', 'list'))
          .map((row) => BackupModel.fromMap(_legacyKeys(row)))
          .toList(growable: false);

  Future<void> createBackup({String? name, String status = 'verified'}) =>
      _cloud.call(
        'backup',
        'create',
        payload: {'name': name, 'status': status},
      );

  Future<BackupExportData> exportBackup(String id) async {
    final row = await _cloud.map('backup', 'export', payload: {'id': id});
    final envelope = row['envelope'] ?? row;
    final name =
        row['file_name']?.toString() ??
        'quality_line_cloud_backup.qlbackup.json';
    return BackupExportData(
      fileName: name,
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
    );
  }

  Future<String> importBackup({
    required Uint8List bytes,
    required String sourceName,
  }) async {
    if (bytes.isEmpty) throw StateError('ملف النسخة الاحتياطية فارغ.');
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map)
      throw StateError('صيغة ملف النسخة الاحتياطية غير صالحة.');
    final row = await _cloud.map(
      'backup',
      'import',
      payload: {
        'source_name': sourceName,
        'envelope': Map<String, Object?>.from(decoded),
      },
    );
    return row['id'] as String;
  }

  Future<bool> verifyBackup(String id) async =>
      (await _cloud.map('backup', 'verify', payload: {'id': id}))['valid'] ==
      true;

  Future<void> restoreBackup(String id) =>
      _cloud.call('backup', 'restore', payload: {'id': id});

  Future<void> deleteBackup(String id) =>
      _cloud.call('backup', 'delete', payload: {'id': id});

  Map<String, Object?> _legacyKeys(Map<String, dynamic> row) => {
    'id': row['id'],
    'name': row['name'],
    'createdAt': row['createdAt'] ?? row['created_at'],
    'sizeBytes': row['sizeBytes'] ?? row['size_bytes'] ?? 0,
    'checksum': row['checksum'] ?? '',
    'schemaVersion': row['schemaVersion'] ?? row['schema_version'] ?? 0,
    'recordCount': row['recordCount'] ?? row['record_count'] ?? 0,
    'status': row['status'] ?? 'verified',
    'lastVerifiedAt': row['lastVerifiedAt'] ?? row['last_verified_at'],
  };
}

class BackupExportData {
  const BackupExportData({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;
}
