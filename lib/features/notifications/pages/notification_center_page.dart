import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_executor.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_signature_components.dart';
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
  final UnifiedQueryController _queryController = UnifiedQueryController();
  late final StreamSubscription<AppDataChangeEvent> _subscription;
  Timer? _refreshDebounce;
  List<NotificationAlert> _alerts = const [];
  List<Map<String, Object?>> _persistentNotifications = const [];
  int _unreadCount = 0;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  static const _severityKey = 'severity';

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
    _queryController.dispose();
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
      final results = await Future.wait<Object?>([
        _repository.loadAlerts(),
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
      if (mounted && generation == _loadGeneration)
        setState(() => _loading = false);
    }
  }

  Future<void> _markAsRead(String id) async {
    if (id.trim().isEmpty) return;
    try {
      await _repository.markAsRead(id);
      if (mounted) await _load();
    } catch (error, stackTrace) {
      AppLogger.debug('Mark notification read failed: $error\n$stackTrace');
      if (mounted)
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

  Future<void> _markAllAsRead() async {
    if (_unreadCount == 0) return;
    try {
      await _repository.markAllAsRead();
      if (mounted) await _load();
    } catch (error, stackTrace) {
      AppLogger.debug(
        'Mark all notifications read failed: $error\n$stackTrace',
      );
      if (mounted)
        _showError(
          userFacingError(
            error,
            isArabic: context.l10n.isArabic,
            arabicFallback: 'تعذر تعليم الإشعارات كمقروءة.',
            englishFallback: 'Unable to mark all notifications as read.',
          ),
        );
    }
  }

  Future<void> _archive(String id) async {
    if (id.trim().isEmpty) return;
    try {
      await _repository.archiveNotification(id);
      if (mounted) await _load();
    } catch (error, stackTrace) {
      AppLogger.debug('Archive notification failed: $error\n$stackTrace');
      if (mounted)
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
      } catch (error, stackTrace) {
        AppLogger.debug(
          'Notification read-state sync failed: $error\n$stackTrace',
        );
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

  UnifiedQueryState get _query => _queryController.state;

  List<NotificationAlert> _visibleAlerts() {
    final criteria = UnifiedFilterCriteria(
      searchText: _query.search,
      statuses: {
        for (final token in _query.filters.where((e) => e.key == _severityKey))
          '${token.value}',
      },
    );
    return UnifiedQueryExecutor<NotificationAlert>(
      criteriaBuilder: (_) => criteria,
      filterAdapter: UnifiedFilterAdapter<NotificationAlert>(
        searchableText: (alert) => <Object?>[
          alert.title,
          alert.message,
          alert.severity.name,
        ],
        status: (alert) => alert.severity.name,
      ),
      sort: (left, right, field) {
        if (field == 'title')
          return UnifiedFilterEngine.normalize(
            left.title,
          ).compareTo(UnifiedFilterEngine.normalize(right.title));
        if (field == 'amount')
          return (left.amount ?? 0).compareTo(right.amount ?? 0);
        return 0;
      },
    ).execute(_alerts, _query);
  }

  List<Map<String, Object?>> _visiblePersistent() {
    return UnifiedQueryExecutor<Map<String, Object?>>(
      criteriaBuilder: (state) => UnifiedFilterCriteria(
        searchText: state.search,
        statuses: {
          for (final token in state.filters.where((e) => e.key == _severityKey))
            '${token.value}',
        },
      ),
      filterAdapter: UnifiedFilterAdapter<Map<String, Object?>>(
        searchableText: (item) => <Object?>[
          item['titleAr'],
          item['titleEn'],
          item['bodyAr'],
          item['bodyEn'],
          item['type'],
          item['referenceType'],
          item['userName'],
          item['user_name'],
        ],
        status: (item) => '${item['type'] ?? 'info'}',
      ),
      sort: (left, right, field) {
        if (field == 'title') {
          final l = UnifiedFilterEngine.normalize(
            left['titleAr'] ?? left['titleEn'],
          );
          final r = UnifiedFilterEngine.normalize(
            right['titleAr'] ?? right['titleEn'],
          );
          return l.compareTo(r);
        }
        if (field == 'createdAt') {
          final l = DateTime.tryParse(
            '${left['createdAt'] ?? left['created_at'] ?? ''}',
          );
          final r = DateTime.tryParse(
            '${right['createdAt'] ?? right['created_at'] ?? ''}',
          );
          return (l ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            r ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        }
        return 0;
      },
    ).execute(_persistentNotifications, _query);
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final visibleAlerts = _visibleAlerts();
    final visiblePersistent = _visiblePersistent();
    final critical = _alerts
        .where((e) => e.severity == NotificationSeverity.critical)
        .length;
    final warning = _alerts
        .where((e) => e.severity == NotificationSeverity.warning)
        .length;

    final filterOptions = <UnifiedQueryFilterOption>[
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: _severityKey,
          label: ar ? 'النوع' : 'Type',
          value: 'critical',
          valueLabel: ar ? 'حرج' : 'Critical',
        ),
        icon: Icons.crisis_alert_rounded,
      ),
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: _severityKey,
          label: ar ? 'النوع' : 'Type',
          value: 'warning',
          valueLabel: ar ? 'تحذير' : 'Warning',
        ),
        icon: Icons.warning_amber_rounded,
      ),
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: _severityKey,
          label: ar ? 'النوع' : 'Type',
          value: 'info',
          valueLabel: ar ? 'معلومة' : 'Information',
        ),
        icon: Icons.info_outline_rounded,
      ),
    ];
    final sortOptions = <UnifiedQuerySortOption>[
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(
          field: 'createdAt',
          label: ar ? 'التاريخ' : 'Date',
          descending: true,
        ),
        icon: Icons.schedule_rounded,
      ),
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(field: 'title', label: ar ? 'العنوان' : 'Title'),
        icon: Icons.title_rounded,
      ),
    ];

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
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _unreadCount == 0
                    ? null
                    : () => unawaited(_markAllAsRead()),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: AppText(ar ? 'تعليم الكل كمقروء' : 'Mark all as read'),
              ),
            ),
            UnifiedQueryToolbar(
              controller: _queryController,
              searchHint: ar
                  ? 'ابحث في العنوان والوصف والنوع والمرجع والمستخدم...'
                  : 'Search title, message, type, reference and user...',
              filters: filterOptions,
              sorts: sortOptions,
              compact: true,
            ),
            const SizedBox(height: 14),
            if (_loading)
              const KajActivitySkeleton(rows: 5)
            else if (_error != null)
              _StateCard(
                icon: Icons.error_outline,
                title: ar ? 'حدث خطأ' : 'Something went wrong',
                message: _error!,
                actionLabel: ar ? 'إعادة المحاولة' : 'Try again',
                onAction: _load,
              )
            else ...[
              if (visiblePersistent.isNotEmpty) ...[
                _SectionHeader(
                  title: ar ? 'الإشعارات المحفوظة' : 'Saved notifications',
                  subtitle: ar
                      ? 'غير المقروء: $_unreadCount'
                      : 'Unread: $_unreadCount',
                ),
                const SizedBox(height: 8),
                ...visiblePersistent.map(
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
                const SizedBox(height: 12),
              ],
              _SectionHeader(
                title: ar ? 'التنبيهات التشغيلية' : 'Operational alerts',
                subtitle: ar
                    ? 'تُحدّث مباشرة من بيانات النظام الحالية'
                    : 'Updated directly from live system data',
              ),
              const SizedBox(height: 8),
              if (visibleAlerts.isEmpty && visiblePersistent.isEmpty)
                _StateCard(
                  icon: Icons.notifications_none_rounded,
                  title: ar ? 'لا توجد تنبيهات' : 'No notifications',
                  message: ar
                      ? 'لا توجد نتائج مطابقة للبحث أو الفلاتر الحالية.'
                      : 'No notifications match the current search or filters.',
                )
              else if (visibleAlerts.isEmpty)
                _StateCard(
                  icon: Icons.notifications_none_rounded,
                  title: ar
                      ? 'لا توجد تنبيهات تشغيلية'
                      : 'No operational alerts',
                  message: ar
                      ? 'لا توجد نتائج مطابقة للتصفية الحالية.'
                      : 'No operational alerts match the current filter.',
                )
              else
                ...visibleAlerts.map((alert) => _AlertCard(alert: alert)),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 2),
      AppText(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 12,
        ),
      ),
    ],
  );
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
      'warning' => KajDesignTokens.warning,
      _ => Theme.of(context).colorScheme.primary,
    };
    final createdAt = DateTime.tryParse(
      '${notification['createdAt'] ?? notification['created_at'] ?? ''}',
    )?.toLocal();
    final user =
        '${notification['userName'] ?? notification['user_name'] ?? ''}'.trim();
    final reference =
        '${notification['reference'] ?? notification['referenceNumber'] ?? notification['reference_number'] ?? ''}'
            .trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isRead ? 0 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final content = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: tone,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            if (!isRead)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tone.withValues(alpha: .11),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: AppText(
                                  isArabic ? 'غير مقروء' : 'Unread',
                                  style: TextStyle(
                                    color: tone,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          AppText(body, style: const TextStyle(fontSize: 12)),
                        ],
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 10,
                          runSpacing: 3,
                          children: [
                            if (createdAt != null)
                              _MetaText(
                                DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                ).format(createdAt),
                              ),
                            if (user.isNotEmpty)
                              _MetaText(
                                isArabic ? 'المستخدم: $user' : 'User: $user',
                              ),
                            if (reference.isNotEmpty)
                              _MetaText(
                                isArabic
                                    ? 'المرجع: $reference'
                                    : 'Ref: $reference',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    _NotificationActions(
                      isRead: isRead,
                      isArabic: isArabic,
                      onMarkRead: onMarkRead,
                      onArchive: onArchive,
                      onOpen: onOpen,
                    ),
                  ],
                ],
              );

              if (!compact) return content;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  content,
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _NotificationActions(
                      isRead: isRead,
                      isArabic: isArabic,
                      onMarkRead: onMarkRead,
                      onArchive: onArchive,
                      onOpen: onOpen,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NotificationActions extends StatelessWidget {
  const _NotificationActions({
    required this.isRead,
    required this.isArabic,
    required this.onMarkRead,
    required this.onArchive,
    required this.onOpen,
  });
  final bool isRead;
  final bool isArabic;
  final VoidCallback onMarkRead;
  final VoidCallback onArchive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 0,
    children: [
      if (!isRead)
        IconButton(
          tooltip: isArabic ? 'تعليم كمقروء' : 'Mark as read',
          onPressed: onMarkRead,
          icon: const Icon(Icons.mark_email_read_outlined, size: 19),
        ),
      IconButton(
        tooltip: isArabic ? 'أرشفة الإشعار' : 'Archive notification',
        onPressed: onArchive,
        icon: const Icon(Icons.archive_outlined, size: 19),
      ),
      IconButton(
        tooltip: isArabic ? 'فتح السجل المرتبط' : 'Open linked record',
        onPressed: onOpen,
        icon: const Icon(Icons.open_in_new_rounded, size: 19),
      ),
    ],
  );
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => AppText(
    text,
    style: TextStyle(
      fontSize: 10.5,
      color: Theme.of(context).colorScheme.outline,
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final NotificationAlert alert;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = switch (alert.severity) {
      NotificationSeverity.critical => scheme.error,
      NotificationSeverity.warning => KajDesignTokens.warning,
      NotificationSeverity.info => scheme.primary,
    };
    final ar = context.l10n.isArabic;
    final severityLabel = switch (alert.severity) {
      NotificationSeverity.critical => ar ? 'حرج' : 'Critical',
      NotificationSeverity.warning => ar ? 'تحذير' : 'Warning',
      NotificationSeverity.info => ar ? 'معلومة' : 'Information',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final body = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(alert.icon, color: tone, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tone.withValues(alpha: .11),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: AppText(
                              severityLabel,
                              style: TextStyle(
                                color: tone,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        alert.message,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (alert.amount != null) ...[
                        const SizedBox(height: 5),
                        AppText(
                          ar
                              ? 'القيمة المرتبطة: ${NumberFormat('#,##0.##').format(alert.amount)}'
                              : 'Related value: ${NumberFormat('#,##0.##').format(alert.amount)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        AppModuleNavigation.open(context, alert.route),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: AppText(ar ? 'فتح' : 'Open'),
                  ),
                ],
              ],
            );
            if (!compact) return body;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                body,
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        AppModuleNavigation.open(context, alert.route),
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: AppText(ar ? 'فتح' : 'Open'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      child: Column(
        children: [
          Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          AppText(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          AppText(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: AppText(actionLabel!)),
          ],
        ],
      ),
    ),
  );
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

bool _asBool(Object? value) =>
    value is bool ? value : '${value ?? ''}'.toLowerCase() == 'true';

String _routeForReference(String referenceType) {
  final value = referenceType.trim().toLowerCase();
  if (value.contains('sale') ||
      value.contains('delivery') ||
      value.contains('customer_invoice'))
    return AppRouteNames.sales;
  if (value.contains('purchase') ||
      value.contains('receipt') ||
      value.contains('supplier_invoice'))
    return AppRouteNames.purchases;
  if (value.contains('maintenance')) return AppRouteNames.maintenance;
  if (value.contains('service') || value.contains('opportunity'))
    return AppRouteNames.customerService;
  if (value.contains('customer') || value.contains('supplier'))
    return AppRouteNames.businessPartners;
  if (value.contains('product')) return AppRouteNames.products;
  if (value.contains('stock') ||
      value.contains('warehouse') ||
      value.contains('car'))
    return AppRouteNames.inventory;
  if (value.contains('payment') ||
      value.contains('journal') ||
      value.contains('account') ||
      value.contains('installment'))
    return AppRouteNames.accounting;
  return AppRouteNames.dashboard;
}
