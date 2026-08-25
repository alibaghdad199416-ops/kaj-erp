import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/cloud/cloud_operation_status.dart';
import 'package:quality_line_erp/core/cloud/supabase_config.dart';
import 'package:quality_line_erp/core/release/app_release_info.dart';
import 'package:quality_line_erp/core/release/production_readiness_service.dart';
import 'package:quality_line_erp/features/settings/system_monitor/models/system_health_snapshot.dart';

class SystemMonitorController extends ChangeNotifier {
  SystemMonitorController() {
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  final CloudFeatureCommand _cloud = CloudFeatureCommand.instance;
  Timer? _timer;
  SystemHealthSnapshot? snapshot;
  ProductionReadinessSnapshot? productionReadiness;
  final CloudRuntimeStatus sync = CloudRuntimeStatus();
  bool isLoading = false;
  bool isRunningSync = false;
  bool isRetryingFailed = false;
  String? errorMessage;

  Future<void> refresh({bool silent = false}) async {
    if (isLoading) return;
    isLoading = true;
    if (!silent) notifyListeners();
    try {
      final row = await _cloud.map('system_monitor', 'snapshot');
      snapshot = SystemHealthSnapshot(
        generatedAt: DateTime.now(),
        databaseTableCount: _asInt(row['cloud_table_count']),
        totalLocalRecords: _asInt(row['cloud_record_count']),
        pendingSyncOperations: _asInt(row['pending_sync_operations']),
        failedSyncOperations: _asInt(row['failed_sync_operations']),
        activeSessions: _asInt(row['active_sessions']),
        backupCount: _asInt(row['backup_count']),
        auditLogCount: _asInt(row['audit_log_count']),
        oldestPendingAt: _date(row['oldest_pending_at']),
        lastBackupAt: _date(row['last_backup_at']),
        lastBackupStatus: row['last_backup_status']?.toString(),
      );
      productionReadiness = await const ProductionReadinessService().evaluate();
      errorMessage = null;
    } catch (error, stackTrace) {
      AppLogger.debug('System monitor refresh failed: $error\n$stackTrace');
      errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل حالة النظام. أعد المحاولة بعد قليل.',
        englishFallback: 'Unable to load system status. Try again shortly.',
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Compatibility action for existing UI. Cloud-only mode writes directly to
  /// Supabase, so there is no local queue to upload or download.
  Future<CloudOperationResult> synchronizeNow() async {
    isRunningSync = true;
    sync.lastOperationStartedAt = DateTime.now();
    notifyListeners();
    try {
      await _cloud.call('system_monitor', 'health_check');
      await refresh(silent: true);
      const result = CloudOperationResult(
        success: true,
        uploaded: 0,
        downloaded: 0,
        message: 'البيانات سحابية مباشرة ولا توجد مزامنة محلية معلقة.',
      );
      sync.lastResult = result;
      sync.lastOperationCompletedAt = DateTime.now();
      return result;
    } finally {
      isRunningSync = false;
      notifyListeners();
    }
  }

  Future<int> retryFailedOperations() async {
    isRetryingFailed = true;
    notifyListeners();
    try {
      final row = await _cloud.map('system_monitor', 'retry_server_jobs');
      await refresh(silent: true);
      return _asInt(row['retried_jobs']);
    } finally {
      isRetryingFailed = false;
      notifyListeners();
    }
  }

  String buildDiagnosticsReport() {
    final data = snapshot;
    return const JsonEncoder.withIndent('  ').convert({
      'applicationVersion': AppReleaseInfo.displayVersion,
      'releaseChannel': AppReleaseInfo.channel,
      'architecture': 'supabase-cloud-only',
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'supabaseConfigured': SupabaseConfig.validate() == null,
      'supabaseHost': Uri.tryParse(SupabaseConfig.url)?.host,
      'cloudTableCount': data?.databaseTableCount,
      'cloudRecordCount': data?.totalLocalRecords,
      'pendingSyncOperations': 0,
      'failedSyncOperations': 0,
      'backupCount': data?.backupCount,
      'lastBackupAt': data?.lastBackupAt?.toUtc().toIso8601String(),
      'lastBackupStatus': data?.lastBackupStatus,
      'activeSessions': data?.activeSessions,
      'auditLogCount': data?.auditLogCount,
      'productionReady': productionReadiness?.readyForProduction,
    });
  }

  static int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
