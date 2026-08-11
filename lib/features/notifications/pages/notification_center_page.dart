import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_top_navigation.dart';
import 'package:quality_line_erp/design_system/kaj_signature_components.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_entry_components.dart';
import 'package:quality_line_erp/features/notifications/models/notification_alert.dart';
import 'package:quality_line_erp/features/notifications/repositories/notification_center_repository.dart';

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final NotificationCenterRepository _repository =
      NotificationCenterRepository();
  late final StreamSubscription<AppDataChangeEvent> _subscription;
  Timer? _refreshDebounce;
  List<NotificationAlert> _alerts = const [];
  List<Map<String, Object?>> _persistentNotifications = const [];
  NotificationSeverity? _filter;
  int _unreadCount = 0;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _subscription = AppDataChangeBus.instance.events.listen((event) {
      const relevantSources = <String>{
        'notifications',
        'sales',
        'purchases',
        'maintenance',
        'inventory',
        'cars',
        'customers',
        'suppliers',
        'opportunities',
        'accounting',
        'cashbox',
        'expenses',
      };
      if (!relevantSources.contains(event.source)) return;
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 700),
        () => unawaited(_load()),
      );
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Generated operational alerts are supplementary. A deployment that has
      // not exposed the legacy aggregation RPC must not make the authoritative
      // persistent notification inbox unusable.
      final alertsFuture = _repository.loadAlerts().catchError((error, stack) {
        AppLogger.debug(
          'Supplementary notification alerts failed: $error\n$stack',
        );
        return <NotificationAlert>[];
      });
      final results = await Future.wait<Object?>([
        alertsFuture,
        _repository.loadPersistentNotifications(),
        _repository.unreadCount(),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _alerts = results[0]! as List<NotificationAlert>;
        _persistentNotifications = results[1]! as List<Map<String, Object?>>;
        _unreadCount = results[2]! as int;
      });
    } catch (error, stackTrace) {
      AppLogger.debug('Notification center load failed: $error\n$stackTrace');
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _error = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر تحميل مركز الإشعارات. أعد المحاولة.',
          englishFallback: 'Unable to load notifications. Try again.',
        ),
      );
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await _repository.markAsRead(id);
      if (!mounted) return;
      await _load();
    } catch (error, stackTrace) {
      AppLogger.debug('Mark notification read failed: $error\n$stackTrace');
      if (!mounted) return;
      _showError(
        userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر تعليم الإشعار كمقروء.',
          englishFallback: 'Unable to mark the notification as read.',
        ),
      );
    }
  }

  Future<void> _archive(String id) async {
    try {
      await _repository.archiveNotification(id);
      if (!mounted) return;
      await _load();
    } catch (error, stackTrace) {
      AppLogger.debug('Archive notification failed: $error\n$stackTrace');
      if (!mounted) return;
      _showError(
        userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر أرشفة الإشعار.',
          englishFallback: 'Unable to archive the notification.',
        ),
      );
    }
  }

  Future<void> _openPersistentNotification(
    Map<String, Object?> notification,
  ) async {
    final id = '${notification['id'] ?? ''}'.trim();
    if (id.isNotEmpty && !_asBool(notification['isRead'])) {
      try {
        await _repository.markAsRead(id);
      } catch (_) {
        // Opening the linked record must remain possible even if read-state
        // synchronization is temporarily unavailable.
      }
    }
    if (!mounted) return;
    AppModuleNavigation.open(
      context,
      _routeForReference('${notification['referenceType'] ?? ''}'),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: AppText(message)));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == null
        ? _alerts
        : _alerts.where((alert) => alert.severity == _filter).toList();
    final critical = _alerts
        .where((e) => e.severity == NotificationSeverity.critical)
        .length;
    final warning = _alerts
        .where((e) => e.severity == NotificationSeverity.warning)
        .length;
    final info = _alerts
        .where((e) => e.severity == NotificationSeverity.info)
        .length;

    final ar = context.l10n.isArabic;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          children: [
            KajSignaturePageHero(
              eyebrow: ar ? 'الوعي التشغيلي' : 'OPERATIONAL AWARENESS',
              title: context.l10n.text('notifications'),
              subtitle: ar
                  ? 'مركز موحد للتنبيهات المهمة والإشعارات المحفوظة والإجراءات التي تحتاج إلى اهتمامك.'
                  : 'A unified center for critical alerts, saved notifications and actions that require your attention.',
              icon: Icons.notifications_active_outlined,
              metrics: <KajSignatureMetricData>[
                KajSignatureMetricData(
                  label: ar ? 'غير مقروء' : 'UNREAD',
                  value: '$_unreadCount',
                  icon: Icons.mark_email_unread_outlined,
                ),
                KajSignatureMetricData(
                  label: ar ? 'حرج' : 'CRITICAL',
                  value: '$critical',
                  icon: Icons.crisis_alert_rounded,
                  accent: KajDesignTokens.danger,
                ),
                KajSignatureMetricData(
                  label: ar ? 'تحذيرات' : 'WARNINGS',
                  value: '$warning',
                  icon: Icons.warning_amber_rounded,
                  accent: KajDesignTokens.warning,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading)
              const KajActivitySkeleton(rows: 6)
            else if (_error != null)
              _StateCard(
                icon: Icons.error_outline,
                title: ar ? 'حدث خطأ' : 'Something went wrong',
                message: _error!,
                actionLabel: ar ? 'إعادة المحاولة' : 'Try again',
                onAction: _load,
              )
            else ...[
              if (_persistentNotifications.isNotEmpty) ...[
                _SectionHeader(
                  title: ar ? 'الإشعارات المحفوظة' : 'Saved notifications',
                  subtitle: ar
                      ? 'غير المقروء: $_unreadCount'
                      : 'Unread: $_unreadCount',
                ),
                const SizedBox(height: 10),
                ..._persistentNotifications.map(
                  (notification) => _PersistentNotificationCard(
                    notification: notification,
                    onOpen: () =>
                        unawaited(_openPersistentNotification(notification)),
                    onMarkRead: () =>
                        unawaited(_markAsRead('${notification['id'] ?? ''}')),
                    onArchive: () =>
                        unawaited(_archive('${notification['id'] ?? ''}')),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              _SectionHeader(
                title: ar ? 'التنبيهات التشغيلية' : 'Operational alerts',
                subtitle: ar
                    ? 'تُحدّث مباشرة من بيانات النظام الحالية'
                    : 'Updated directly from live system data',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _FilterChip(
                    label: ar ? 'الكل' : 'All',
                    count: _alerts.length,
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  _FilterChip(
                    label: ar ? 'حرجة' : 'Critical',
                    count: critical,
                    selected: _filter == NotificationSeverity.critical,
                    onTap: () =>
                        setState(() => _filter = NotificationSeverity.critical),
                  ),
                  _FilterChip(
                    label: ar ? 'تحذيرات' : 'Warnings',
                    count: warning,
                    selected: _filter == NotificationSeverity.warning,
                    onTap: () =>
                        setState(() => _filter = NotificationSeverity.warning),
                  ),
                  _FilterChip(
                    label: ar ? 'معلومات' : 'Information',
                    count: info,
                    selected: _filter == NotificationSeverity.info,
                    onTap: () =>
                        setState(() => _filter = NotificationSeverity.info),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (visible.isEmpty && _persistentNotifications.isEmpty)
                const _StateCard(
                  icon: Icons.notifications_none_rounded,
                  title: 'لا توجد تنبيهات',
                  message: 'لا توجد حالات تحتاج إلى متابعة ضمن هذا التصنيف.',
                )
              else if (visible.isEmpty)
                const _StateCard(
                  icon: Icons.notifications_none_rounded,
                  title: 'لا توجد تنبيهات تشغيلية',
                  message: 'لا توجد حالات تحتاج إلى متابعة ضمن هذا التصنيف.',
                )
              else
                ...visible.map((alert) => _AlertCard(alert: alert)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        AppText(
          subtitle,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }
}

class _PersistentNotificationCard extends StatelessWidget {
  const _PersistentNotificationCard({
    required this.notification,
    required this.onOpen,
    required this.onMarkRead,
    required this.onArchive,
  });

  final Map<String, Object?> notification;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final isArabic = AppTranslation.isArabic;
    final isRead = _asBool(notification['isRead']);
    final title = _localizedValue(
      notification,
      isArabic ? 'titleAr' : 'titleEn',
      isArabic ? 'titleEn' : 'titleAr',
      fallback: 'إشعار',
    );
    final body = _localizedValue(
      notification,
      isArabic ? 'bodyAr' : 'bodyEn',
      isArabic ? 'bodyEn' : 'bodyAr',
    );
    final type = '${notification['type'] ?? 'info'}'.toLowerCase();
    final tone = switch (type) {
      'critical' || 'error' => Theme.of(context).colorScheme.error,
      'warning' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    final createdAt = DateTime.tryParse(
      '${notification['createdAt'] ?? notification['created_at'] ?? ''}',
    )?.toLocal();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isRead ? 0 : 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.notifications_outlined, color: tone),
                  ),
                  if (!isRead)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppText(
                          title,
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.w700
                                : FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                          label: AppText(
                            context.l10n.isArabic
                                ? (isRead ? 'مقروء' : 'غير مقروء')
                                : (isRead ? 'Read' : 'Unread'),
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      AppText(body),
                    ],
                    if (createdAt != null) ...[
                      const SizedBox(height: 7),
                      AppText(
                        DateFormat('yyyy-MM-dd HH:mm').format(createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 4,
                children: [
                  if (!isRead)
                    IconButton(
                      tooltip: AppTranslation.translate('تعليم كمقروء'),
                      onPressed: onMarkRead,
                      icon: const Icon(Icons.mark_email_read_outlined),
                    ),
                  IconButton(
                    tooltip: AppTranslation.translate('أرشفة الإشعار'),
                    onPressed: onArchive,
                    icon: const Icon(Icons.archive_outlined),
                  ),
                  IconButton(
                    tooltip: AppTranslation.translate('فتح السجل المرتبط'),
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final NotificationAlert alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = switch (alert.severity) {
      NotificationSeverity.critical => scheme.error,
      NotificationSeverity.warning => Colors.orange,
      NotificationSeverity.info => scheme.primary,
    };
    final ar = context.l10n.isArabic;
    final severityLabel = switch (alert.severity) {
      NotificationSeverity.critical => ar ? 'حرج' : 'Critical',
      NotificationSeverity.warning => ar ? 'تحذير' : 'Warning',
      NotificationSeverity.info => ar ? 'معلومة' : 'Information',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(alert.icon, color: tone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      AppText(
                        alert.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: tone.withValues(alpha: .11),
                        label: AppText(
                          severityLabel,
                          style: TextStyle(
                            color: tone,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  AppText(alert.message),
                  if (alert.amount != null) ...[
                    const SizedBox(height: 7),
                    AppText(
                      ar
                          ? 'القيمة المرتبطة: ${NumberFormat('#,##0.##').format(alert.amount)}'
                          : 'Related value: ${NumberFormat('#,##0.##').format(alert.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: () => AppModuleNavigation.open(context, alert.route),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: AppText(ar ? 'فتح' : 'Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      label: AppText('$label ($count)'),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 54),
        child: Column(
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            AppText(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            AppText(message, textAlign: TextAlign.center),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: AppText(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _localizedValue(
  Map<String, Object?> values,
  String primary,
  String secondary, {
  String fallback = '',
}) {
  final first = '${values[primary] ?? ''}'.trim();
  if (first.isNotEmpty) return first;
  final second = '${values[secondary] ?? ''}'.trim();
  return second.isNotEmpty ? second : fallback;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  return '${value ?? ''}'.toLowerCase() == 'true';
}

String _routeForReference(String referenceType) {
  final value = referenceType.trim().toLowerCase();
  if (value.contains('sale') ||
      value.contains('delivery') ||
      value.contains('customer_invoice')) {
    return AppRouteNames.sales;
  }
  if (value.contains('purchase') ||
      value.contains('receipt') ||
      value.contains('supplier_invoice')) {
    return AppRouteNames.purchases;
  }
  if (value.contains('maintenance')) return AppRouteNames.maintenance;
  if (value.contains('service') || value.contains('opportunity')) {
    return AppRouteNames.customerService;
  }
  if (value.contains('customer') || value.contains('supplier')) {
    return AppRouteNames.businessPartners;
  }
  if (value.contains('product')) return AppRouteNames.products;
  if (value.contains('stock') ||
      value.contains('warehouse') ||
      value.contains('car')) {
    return AppRouteNames.inventory;
  }
  if (value.contains('payment') ||
      value.contains('journal') ||
      value.contains('account') ||
      value.contains('installment')) {
    return AppRouteNames.accounting;
  }
  return AppRouteNames.dashboard;
}
