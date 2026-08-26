import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_codes.dart';

import 'package:quality_line_erp/features/settings/models/backup_model.dart';
import 'package:quality_line_erp/features/settings/models/branch_model.dart';
import 'package:quality_line_erp/features/settings/models/company_settings_model.dart';
import 'package:quality_line_erp/features/settings/models/currency_model.dart';
import 'package:quality_line_erp/features/settings/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    SettingsRepository? repository,
    AccessController? accessController,
  }) : _repository = repository ?? SettingsRepository(),
       // A private initializing formal would break the public accessController API.
       // ignore: prefer_initializing_formals
       _accessController = accessController;

  final SettingsRepository _repository;
  final AccessController? _accessController;

  CompanySettingsModel company = CompanySettingsModel.defaults();
  List<BranchModel> branches = [];
  List<CurrencyModel> currencies = [];
  List<BackupModel> backups = [];
  bool isLoading = false;
  String? errorMessage;

  Future<void> loadSettings() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final values = await Future.wait<dynamic>([
        _repository.getCompanySettings(),
        _repository.getBranches(),
        _repository.getCurrencies(),
        _repository.getBackups(),
      ]);
      company = values[0] as CompanySettingsModel;
      branches = values[1] as List<BranchModel>;
      currencies = values[2] as List<CurrencyModel>;
      backups = values[3] as List<BackupModel>;
    } catch (error) {
      AppLogger.debug('SettingsController.load failed: $error');
      errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل الإعدادات.',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveCompany(CompanySettingsModel value) async {
    await _requirePermission(PermissionCodes.settingsView);
    await _run(() async {
      await _repository.saveCompanySettings(value);
      company = value;
      _publishSettingsChange('company-save');
    });
  }

  Future<void> saveBranch(BranchModel value) async {
    await _requirePermission(PermissionCodes.settingsView);
    await _run(() async {
      await _repository.saveBranch(value);
      branches = await _repository.getBranches();
      _publishSettingsChange('branch-save', entityId: value.id);
    });
  }

  Future<void> deleteBranch(String id) async {
    await _requirePermission(PermissionCodes.settingsView);
    await _run(() async {
      await _repository.deleteBranch(id);
      branches = await _repository.getBranches();
      _publishSettingsChange('branch-delete', entityId: id);
    });
  }

  Future<void> saveCurrency(CurrencyModel value) async {
    await _requirePermission(PermissionCodes.settingsView);
    await _run(() async {
      await _repository.saveCurrency(value);
      currencies = await _repository.getCurrencies();
      _publishSettingsChange('currency-save', entityId: value.code);
    });
  }

  Future<void> deleteCurrency(String code) async {
    await _requirePermission(PermissionCodes.settingsView);
    await _run(() async {
      await _repository.deleteCurrency(code);
      currencies = await _repository.getCurrencies();
      _publishSettingsChange('currency-delete', entityId: code);
    });
  }

  Future<void> createBackup() async {
    await _requirePermission(PermissionCodes.settingsBackup);
    await _run(() async {
      await _repository.createBackup();
      backups = await _repository.getBackups();
      _publishSettingsChange('backup-create');
    });
  }

  Future<BackupExportData> exportBackup(String id) async {
    await _requirePermission(PermissionCodes.settingsBackup);
    late BackupExportData result;
    await _run(() async {
      result = await _repository.exportBackup(id);
    });
    return result;
  }

  Future<String> importBackup({
    required Uint8List bytes,
    required String sourceName,
  }) async {
    await _requirePermission(PermissionCodes.settingsBackup);
    late String id;
    await _run(() async {
      id = await _repository.importBackup(bytes: bytes, sourceName: sourceName);
      backups = await _repository.getBackups();
      _publishSettingsChange('backup-import', entityId: id);
    });
    return id;
  }

  Future<bool> verifyBackup(String id) async {
    await _requirePermission(PermissionCodes.settingsBackup);
    var result = false;
    await _run(() async {
      result = await _repository.verifyBackup(id);
      backups = await _repository.getBackups();
      _publishSettingsChange('backup-verify', entityId: id);
    });
    return result;
  }

  Future<void> restoreBackup(String id) async {
    await _requirePermission(PermissionCodes.settingsRestore);
    await _run(() async {
      await _repository.restoreBackup(id);
      await loadSettings();
      AppDataChangeBus.instance.publish(
        'all',
        operation: 'backup-restore',
        entityId: id,
      );
    });
  }

  Future<void> deleteBackup(String id) async {
    await _requirePermission(PermissionCodes.settingsBackup);
    await _run(() async {
      await _repository.deleteBackup(id);
      backups = await _repository.getBackups();
      _publishSettingsChange('backup-delete', entityId: id);
    });
  }

  void _publishSettingsChange(String operation, {String? entityId}) {
    AppDataChangeBus.instance.publish(
      'settings',
      operation: operation,
      entityId: entityId,
    );
  }

  Future<void> _requirePermission(String code) async {
    final accessController = _accessController;
    if (accessController == null) {
      return;
    }
    await accessController.requirePermission(code);
  }

  Future<void> _run(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error, stackTrace) {
      AppLogger.debug('Settings operation failed: $error\n$stackTrace');
      errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر حفظ الإعدادات. راجع البيانات ثم أعد المحاولة.',
        englishFallback:
            'Unable to save settings. Review the data and try again.',
      );
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
