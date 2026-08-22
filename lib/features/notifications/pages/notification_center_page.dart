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
  bool _clearingAll = false;
  final Set<String> _deletingNotificationIds = <String>{};

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

  Future<void> _deleteNotification(Map<String, Object?> notification) async {
    final id = '${notification['id'] ?? ''}'.trim();
    if (id.isEmpty || _deletingNotificationIds.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          context.l10n.isArabic ? 'حذف الإشعار' : 'Delete notification',
        ),
        content: AppText(
          context.l10n.isArabic
              ? 'سيُحذف هذا الإشعار من مركز إشعاراتك فقط. لن يتأثر المستند أو الحدث المرتبط.'
              : 'This removes the notification only from your notification center. The linked document or business event is not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(context.l10n.isArabic ? 'رجوع' : 'Back'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: AppText(
              context.l10n.isArabic ? 'حذف الإشعار' : 'Delete notification',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingNotificationIds.add(id));
    try {
      final wasUnread = await _repository.deleteNotification(id);
      if (!mounted) return;
      setState(() {
        _persistentNotifications = _persistentNotifications
            .where((row) => '${row['id'] ?? ''}' != id)
            .toList(growable: false);
        if (wasUnread && _unreadCount > 0) _unreadCount--;
      });
    } catch (error, stackTrace) {
      AppLogger.debug('Delete notification failed: $error\n$stackTrace');
      if (mounted) {
        _showError(
          userFacingError(
            error,
            isArabic: context.l10n.isArabic,
            arabicFallback: 'تعذر حذف الإشعار. أعد المحاولة.',
            englishFallback: 'Unable to delete the notification. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingNotificationIds.remove(id));
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
    final deepLink = '${notification['deepLink'] ?? ''}'.trim();
    AppModuleNavigation.open(
      context,
      deepLink.startsWith('/')
          ? deepLink
          : _routeForReference('${notification['referenceType'] ?? ''}'),
      arguments: <String, Object?>{
        'referenceId': notification['referenceId'],
        'referenceType': notification['referenceType'],
        'documentReference': notification['documentReference'],
        'cashboxId': notification['cashboxId'],
        'carId': notification['carId'],
      },
    );
  }

  Future<void> _clearAllNotifications() async {
    if (_clearingAll || _persistentNotifications.isEmpty) return;
    final ar = context.l10n.isArabic;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(ar ? 'مسح جميع الإشعارات' : 'Clear All Notifications'),
        content: AppText(
          ar
              ? 'سيتم مسح جميع الإشعارات المحفوظة من مركز إشعاراتك فقط. لن تُحذف المستندات أو الأحداث التشغيلية المرتبطة.'
              : 'This clears every saved notification only from your notification center. Linked documents and business events are preserved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(ar ? 'رجوع' : 'Back'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: AppText(
              ar ? 'مسح جميع الإشعارات' : 'Clear All Notifications',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearingAll = true);
    try {
      await _repository.clearAllNotifications();
      if (!mounted) return;
      setState(() {
        _persistentNotifications = const [];
        _unreadCount = 0;
      });
      await _load();
    } catch (error, stackTrace) {
      AppLogger.debug('Clear notifications failed: $error\n$stackTrace');
      if (mounted) {
        _showError(
          userFacingError(
            error,
            isArabic: ar,
            arabicFallback: 'تعذر مسح جميع الإشعارات. أعد المحاولة.',
            englishFallback: 'Unable to clear all notifications. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
            const SizedBox(height: 12),
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
                  action: FilledButton.icon(
                    onPressed: _clearingAll ? null : _clearAllNotifications,
                    icon: _clearingAll
                        ? const SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          )
                        : const Icon(Icons.delete_sweep_outlined, size: 16),
                    label: AppText(
                      ar ? 'مسح جميع الإشعارات' : 'Clear All Notifications',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                ..._persistentNotifications.map(
                  (notification) => _PersistentNotificationCard(
                    notification: notification,
                    onOpen: () =>
                        unawaited(_openPersistentNotification(notification)),
                    onMarkRead: () =>
                        unawaited(_markAsRead('${notification['id'] ?? ''}')),
                    onArchive: () =>
                        unawaited(_archive('${notification['id'] ?? ''}')),
                    deleting: _deletingNotificationIds.contains(
                      '${notification['id'] ?? ''}',
                    ),
                    onDelete: () =>
                        unawaited(_deleteNotification(notification)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _SectionHeader(
                title: ar ? 'التنبيهات التشغيلية' : 'Operational alerts',
                subtitle: ar
                    ? 'تُحدّث مباشرة من بيانات النظام الحالية'
                    : 'Updated directly from live system data',
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 7,
                runSpacing: 7,
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
              const SizedBox(height: 10),
              if (visible.isEmpty && _persistentNotifications.isEmpty)
                _StateCard(
                  icon: Icons.notifications_none_rounded,
                  title: ar ? 'لا توجد تنبيهات' : 'No notifications',
                  message: ar
                      ? 'لا توجد حالات تحتاج إلى متابعة ضمن هذا التصنيف.'
                      : 'There are no items that need attention in this category.',
                )
              else if (visible.isEmpty)
                _StateCard(
                  icon: Icons.notifications_none_rounded,
                  title: ar
                      ? 'لا توجد تنبيهات تشغيلية'
                      : 'No operational alerts',
                  message: ar
                      ? 'لا توجد حالات تحتاج إلى متابعة ضمن هذا التصنيف.'
                      : 'There are no operational items that need attention in this category.',
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
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText(
          title,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        AppText(
          subtitle,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );

    if (action == null) return heading;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 7),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: action!,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 10),
            action!,
          ],
        );
      },
    );
  }
}

class _PersistentNotificationCard extends StatelessWidget {
  const _PersistentNotificationCard({
    required this.notification,
    required this.onOpen,
    required this.onMarkRead,
    required this.onArchive,
    required this.onDelete,
    required this.deleting,
  });

  final Map<String, Object?> notification;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    final isArabic = context.l10n.isArabic;
    final isRead = _asBool(notification['isRead']);
    final title = _localizedValue(
      notification,
      isArabic ? 'titleAr' : 'titleEn',
      isArabic ? 'titleEn' : 'titleAr',
      fallback: isArabic ? 'إشعار' : 'Notification',
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
      '${notification['dateTime'] ?? notification['createdAt'] ?? notification['created_at'] ?? ''}',
    )?.toLocal();
    final metadata = <String>[
      if ('${notification['eventType'] ?? notification['event'] ?? ''}'
          .trim()
          .isNotEmpty)
        '${isArabic ? 'الحدث' : 'Event'}: ${notification['eventType'] ?? notification['event']}',
      if ('${notification['documentReference'] ?? notification['orderReference'] ?? ''}'
          .trim()
          .isNotEmpty)
        '${isArabic ? 'المرجع' : 'Reference'}: ${notification['documentReference'] ?? notification['orderReference']}',
      if ('${notification['actorUser'] ?? ''}'.trim().isNotEmpty)
        '${isArabic ? 'المنفذ' : 'Actor'}: ${notification['actorUser']}',
      if ('${notification['targetUser'] ?? ''}'.trim().isNotEmpty)
        '${isArabic ? 'المستلم' : 'Target'}: ${notification['targetUser']}',
      if ('${notification['supplierName'] ?? notification['customerName'] ?? notification['carName'] ?? ''}'
          .trim()
          .isNotEmpty)
        '${isArabic ? 'الجهة/السيارة' : 'Party / Vehicle'}: ${notification['supplierName'] ?? notification['customerName'] ?? notification['carName']}',
      if ((notification['amount'] as num?) != null)
        '${isArabic ? 'المبلغ' : 'Amount'}: ${notification['amount']} ${notification['currency'] ?? ''}',
      if ('${notification['warehouseName'] ?? notification['cashboxName'] ?? ''}'
          .trim()
          .isNotEmpty)
        '${isArabic ? 'الموقع' : 'Location'}: ${notification['warehouseName'] ?? notification['cashboxName']}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      elevation: isRead ? 0 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 8, 9),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final leading = Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: tone,
                      size: 19,
                    ),
                  ),
                  if (!isRead)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: tone,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              );
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppText(
                        title,
                        style: TextStyle(
                          fontWeight: isRead
                              ? FontWeight.w700
                              : FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      _NotificationBadge(
                        label: isArabic
                            ? (isRead ? 'مقروء' : 'غير مقروء')
                            : (isRead ? 'Read' : 'Unread'),
                        tone: tone,
                        emphasized: !isRead,
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    AppText(
                      body,
                      style: const TextStyle(fontSize: 12.2, height: 1.3),
                    ),
                  ],
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: metadata
                          .map(
                            (value) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: .46),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: AppText(
                                value,
                                style: const TextStyle(
                                  fontSize: 10.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        AppText(
                          DateFormat('yyyy-MM-dd HH:mm').format(createdAt),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
              final actions = Wrap(
                spacing: 1,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!isRead)
                    _CompactIconAction(
                      tooltip: AppTranslation.translate('تعليم كمقروء'),
                      onPressed: onMarkRead,
                      icon: Icons.mark_email_read_outlined,
                    ),
                  _CompactIconAction(
                    tooltip: AppTranslation.translate('أرشفة الإشعار'),
                    onPressed: deleting ? null : onArchive,
                    icon: Icons.archive_outlined,
                  ),
                  _CompactIconAction(
                    tooltip: isArabic ? 'حذف الإشعار' : 'Delete notification',
                    onPressed: deleting ? null : onDelete,
                    icon: Icons.delete_outline_rounded,
                    progress: deleting,
                  ),
                  _CompactIconAction(
                    tooltip: AppTranslation.translate('فتح السجل المرتبط'),
                    onPressed: onOpen,
                    icon: Icons.open_in_new_rounded,
                  ),
                ],
              );

              if (compact) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          details,
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Expanded(child: details),
                  const SizedBox(width: 8),
                  actions,
                ],
              );
            },
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
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 9, 9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final leading = Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(alert.icon, color: tone, size: 19),
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    AppText(
                      alert.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    _NotificationBadge(label: severityLabel, tone: tone),
                  ],
                ),
                const SizedBox(height: 3),
                AppText(
                  alert.message,
                  style: const TextStyle(fontSize: 12.2, height: 1.3),
                ),
                if (alert.amount != null) ...[
                  const SizedBox(height: 4),
                  AppText(
                    ar
                        ? 'القيمة المرتبطة: ${NumberFormat('#,##0.##').format(alert.amount)}'
                        : 'Related value: ${NumberFormat('#,##0.##').format(alert.amount)}',
                    style: const TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            );
            final openButton = FilledButton.tonalIcon(
              onPressed: () => AppModuleNavigation.open(context, alert.route),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: AppText(ar ? 'فتح' : 'Open'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                textStyle: const TextStyle(fontSize: 11.5),
              ),
            );

            if (compact) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading,
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        details,
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: openButton,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(child: details),
                const SizedBox(width: 10),
                openButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge({
    required this.label,
    required this.tone,
    this.emphasized = false,
  });

  final String label;
  final Color tone;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: emphasized ? .15 : .09),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: tone.withValues(alpha: .20)),
    ),
    child: AppText(
      label,
      style: TextStyle(color: tone, fontSize: 9.5, fontWeight: FontWeight.w800),
    ),
  );
}

class _CompactIconAction extends StatelessWidget {
  const _CompactIconAction({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.progress = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool progress;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    iconSize: 17,
    icon: progress
        ? const SizedBox.square(
            dimension: 15,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          )
        : Icon(icon),
  );
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
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      label: AppText('$label ($count)', style: const TextStyle(fontSize: 11)),
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            AppText(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            AppText(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.2),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 9),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: AppText(actionLabel!),
              ),
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
  if (value.contains('report')) return AppRouteNames.reports;
  return AppRouteNames.dashboard;
}
