import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/core/cloud/supabase_config.dart';
import 'package:quality_line_erp/core/release/production_readiness_service.dart';
import 'package:quality_line_erp/design_system/kaj_admin_stage8_components.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/system_monitor/controllers/system_monitor_controller.dart';
import 'package:quality_line_erp/features/settings/system_monitor/models/system_health_snapshot.dart';

class SystemMonitorPage extends StatefulWidget {
  const SystemMonitorPage({super.key});

  @override
  State<SystemMonitorPage> createState() => _SystemMonitorPageState();
}

class _SystemMonitorPageState extends State<SystemMonitorPage> {
  late final SystemMonitorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SystemMonitorController()..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.refresh());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _controller.snapshot;
    Widget field(String field, Widget child) => FieldPermissionVisibility(
      resource: 'settings',
      field: field,
      viewPermission: 'settings.view',
      child: child,
    );
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _controller.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          children: [
            field(
              'systemHealth',
              KajAdminWorkspace(
                title: context.l10n.isArabic
                    ? 'مراقبة النظام'
                    : 'System Monitoring',
                subtitle: context.l10n.isArabic
                    ? 'مراقبة الاتصال والمزامنة والنسخ الاحتياطية وجاهزية الإنتاج.'
                    : 'Monitor connectivity, synchronization, backups and production readiness.',
                icon: Icons.monitor_heart_outlined,
                metrics: <KajAdminMetricData>[
                  KajAdminMetricData(
                    label: context.l10n.isArabic ? 'الحالة' : 'Status',
                    value: snapshot == null
                        ? '—'
                        : (context.l10n.isArabic ? 'متصل' : 'Online'),
                    icon: Icons.cloud_done_outlined,
                  ),
                  KajAdminMetricData(
                    label: context.l10n.isArabic
                        ? 'المزامنة المعلقة'
                        : 'Pending sync',
                    value: snapshot?.pendingSyncOperations.toString() ?? '—',
                    icon: Icons.sync_outlined,
                  ),
                  KajAdminMetricData(
                    label: context.l10n.isArabic ? 'التحديث' : 'Refresh',
                    value: '15s',
                    icon: Icons.timer_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_controller.errorMessage != null)
              _ErrorBanner(message: _controller.errorMessage!),
            if (snapshot == null && _controller.isLoading)
              KajAdminState(
                kind: KajAdminStateKind.loading,
                title: context.l10n.isArabic
                    ? 'جاري فحص النظام'
                    : 'Checking system health',
                message: context.l10n.isArabic
                    ? 'يتم التحقق من الاتصال والمزامنة والنسخ الاحتياطية.'
                    : 'Checking connectivity, synchronization and backup status.',
              )
            else if (snapshot != null) ...[
              field(
                'systemHealth',
                _StatusOverview(controller: _controller, snapshot: snapshot),
              ),
              const SizedBox(height: 20),
              field('systemMetrics', _MetricGrid(snapshot: snapshot)),
              const SizedBox(height: 20),
              field(
                'systemSyncDetails',
                _SyncDetails(controller: _controller, snapshot: snapshot),
              ),
              const SizedBox(height: 20),
              if (_controller.productionReadiness != null) ...[
                field(
                  'productionReadiness',
                  _ProductionReadinessCard(
                    readiness: _controller.productionReadiness!,
                  ),
                ),
                const SizedBox(height: 20),
              ],
              field(
                'systemHealth',
                _MaintenanceRecommendations(
                  controller: _controller,
                  snapshot: snapshot,
                ),
              ),
              const SizedBox(height: 12),
              AppText(
                context.l10n.isArabic
                    ? 'آخر تحديث: ${_formatDate(snapshot.generatedAt)} — يتم التحديث تلقائياً كل 15 ثانية'
                    : 'Last update: ${_formatDate(snapshot.generatedAt)} — automatically refreshed every 15 seconds',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusOverview extends StatelessWidget {
  const _StatusOverview({required this.controller, required this.snapshot});
  final SystemMonitorController controller;
  final SystemHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final configValid = SupabaseConfig.validate() == null;
    final lastResult = controller.sync.lastResult;
    final cloudHealthy = configValid && lastResult?.success != false;
    final queueHealthy = snapshot.pendingSyncOperations == 0;
    final backupHealthy =
        snapshot.lastBackupAt != null &&
        DateTime.now().difference(snapshot.lastBackupAt!).inDays <= 7;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatusCard(
          title: 'الاتصال السحابي',
          value: cloudHealthy ? 'سليم' : 'يحتاج مراجعة',
          icon: cloudHealthy
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          healthy: cloudHealthy,
        ),
        _StatusCard(
          title: 'التحديث الفوري',
          value: controller.sync.realtimeStatus,
          icon: Icons.bolt_outlined,
          healthy: controller.sync.realtimeStatus == 'cloud-direct',
        ),
        _StatusCard(
          title: 'طابور المزامنة',
          value: queueHealthy
              ? 'فارغ'
              : '${snapshot.pendingSyncOperations} معلقة',
          icon: Icons.sync_problem_outlined,
          healthy: queueHealthy,
        ),
        _StatusCard(
          title: 'آخر نسخة احتياطية',
          value: snapshot.lastBackupAt == null
              ? 'غير متوفرة'
              : _formatDate(snapshot.lastBackupAt!),
          icon: Icons.backup_outlined,
          healthy: backupHealthy,
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.healthy,
  });
  final String title;
  final String value;
  final IconData icon;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = healthy ? Colors.green : scheme.error;
    return SizedBox(
      width: 250,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .12),
                foregroundColor: color,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      title,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    AppText(
                      value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.snapshot});
  final SystemHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('السجلات المحلية', snapshot.totalLocalRecords, Icons.storage_outlined),
      (
        'جداول قاعدة البيانات',
        snapshot.databaseTableCount,
        Icons.table_chart_outlined,
      ),
      ('سجل التدقيق', snapshot.auditLogCount, Icons.fact_check_outlined),
      ('الجلسات النشطة', snapshot.activeSessions, Icons.devices_outlined),
      ('النسخ الاحتياطية', snapshot.backupCount, Icons.inventory_2_outlined),
      (
        'عمليات معلقة',
        snapshot.pendingSyncOperations,
        Icons.hourglass_bottom_outlined,
      ),
      ('عمليات فاشلة', snapshot.failedSyncOperations, Icons.error_outline),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: Card(
                    child: ListTile(
                      leading: Icon(metric.$3),
                      title: AppText(
                        '${metric.$2}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      subtitle: AppText(metric.$1),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SyncDetails extends StatelessWidget {
  const _SyncDetails({required this.controller, required this.snapshot});
  final SystemMonitorController controller;
  final SystemHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final result = controller.sync.lastResult;
    final resultMessage = result?.message;
    final rows = <(String, String)>[
      ('معمارية البيانات', 'Supabase cloud-direct'),
      ('الكتابة السحابية المباشرة', 'مفعلة'),
      ('حالة التهيئة', controller.sync.isInitialized ? 'مهيأ' : 'غير مهيأ'),
      (
        'آخر بدء لفحص السحابة',
        _formatNullable(controller.sync.lastOperationStartedAt),
      ),
      (
        'آخر اكتمال للمزامنة',
        _formatNullable(controller.sync.lastOperationCompletedAt),
      ),
      (
        'آخر نتيجة',
        result == null
            ? 'لم تُنفذ بعد'
            : result.success
            ? 'نجحت'
            : 'فشلت',
      ),
      ('كتابة محلية معلقة', '0'),
      ('تنزيل كاش محلي', 'غير مستخدم'),
      ('أقدم عملية معلقة', _formatNullable(snapshot.oldestPendingAt)),
      ('حالة آخر نسخة', snapshot.lastBackupStatus ?? 'غير متوفرة'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              'تفاصيل التشغيل',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(child: AppText(row.$1)),
                    const SizedBox(width: 12),
                    Flexible(child: AppText(row.$2, textAlign: TextAlign.end)),
                  ],
                ),
              ),
            ),
            if (snapshot.failedSyncOperations > 0) ...[
              const Divider(),
              FieldPermissionControl(
                resource: 'settings',
                field: 'retryFailedJobs',
                viewPermission: 'settings.view',
                writePermission: 'settings.view',
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    onPressed: controller.isRetryingFailed
                        ? null
                        : () async {
                            final changed = await controller
                                .retryFailedOperations();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: AppText(
                                  changed > 0
                                      ? 'تمت إعادة جدولة $changed عملية فاشلة.'
                                      : 'لا توجد عمليات فاشلة لإعادة المحاولة.',
                                ),
                              ),
                            );
                          },
                    icon: controller.isRetryingFailed
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.replay_outlined),
                    label: const AppText('إعادة محاولة العمليات الفاشلة'),
                  ),
                ),
              ),
            ],
            if (resultMessage != null) ...[
              const Divider(),
              AppSelectableText(
                resultMessage,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductionReadinessCard extends StatelessWidget {
  const _ProductionReadinessCard({required this.readiness});

  final ProductionReadinessSnapshot readiness;

  @override
  Widget build(BuildContext context) {
    final ready = readiness.readyForProduction;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ready
                      ? Icons.verified_outlined
                      : Icons.warning_amber_outlined,
                  color: ready ? Colors.green : scheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppText(
                    ready
                        ? 'بوابات الإنتاج مستوفاة'
                        : 'بوابات الإنتاج تحتاج معالجة',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                AppText(
                  '${readiness.checks.where((check) => check.passed).length}/${readiness.checks.length}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...readiness.checks.map(
              (check) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  check.passed
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: check.passed ? Colors.green : scheme.error,
                ),
                title: AppText(check.title),
                subtitle: AppText(check.details),
                trailing: check.mandatory
                    ? const AppText('إلزامي')
                    : const AppText('إرشادي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaintenanceRecommendations extends StatelessWidget {
  const _MaintenanceRecommendations({
    required this.controller,
    required this.snapshot,
  });
  final SystemMonitorController controller;
  final SystemHealthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (snapshot.pendingSyncOperations > 0) {
      items.add('شغّل المزامنة الآن وتحقق من الاتصال إذا بقيت العمليات معلقة.');
    }
    if (snapshot.lastBackupAt == null) {
      items.add('أنشئ أول نسخة احتياطية من تبويب النسخ الاحتياطي.');
    } else if (DateTime.now().difference(snapshot.lastBackupAt!).inDays > 7) {
      items.add('آخر نسخة احتياطية أقدم من سبعة أيام؛ أنشئ نسخة جديدة.');
    }
    if (controller.sync.lastResult?.success == false) {
      items.add('راجع رسالة آخر خطأ وانسخ تقرير التشخيص عند طلب الدعم.');
    }
    if (items.isEmpty) items.add('لا توجد إجراءات صيانة عاجلة حالياً.');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              'توصيات الصيانة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            ...items.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: AppText(item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: AppSelectableText(message)),
        ],
      ),
    ),
  );
}

String _formatDate(DateTime value) =>
    DateFormat('yyyy/MM/dd HH:mm').format(value.toLocal());
String _formatNullable(DateTime? value) =>
    value == null ? 'غير متوفر' : _formatDate(value);
