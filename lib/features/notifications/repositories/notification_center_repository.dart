import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/notifications/notification_unread_state.dart';
import 'package:quality_line_erp/features/notifications/models/notification_alert.dart';

class NotificationCenterRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _companyId =>
      CloudTenantContext.instance.companyUuid ??
      (throw StateError('لم يتم تحديد شركة سحابية للمستخدم الحالي.'));

  Future<List<NotificationAlert>> loadAlerts() async {
    final rows = await _client.rpc(
      'erp_cloud_notification_alerts',
      params: {
        'p_company_id': _companyId,
        'p_reference_day': _day(DateTime.now()),
      },
    );
    return (rows as List)
        .map((e) {
          final m = Map<String, Object?>.from(e as Map);
          return NotificationAlert(
            id: m['id']?.toString() ?? '',
            title: m['title']?.toString() ?? '',
            message: m['message']?.toString() ?? '',
            severity: _severity(m['severity']?.toString()),
            icon: _icon(m['icon']?.toString()),
            route: m['route']?.toString() ?? AppRouteNames.dashboard,
            count: (m['count'] as num?)?.toInt() ?? 0,
            amount: (m['amount'] as num?)?.toDouble(),
          );
        })
        .toList(growable: false);
  }

  Future<String> createNotification({
    String? userId,
    String? roleId,
    required String titleAr,
    String titleEn = '',
    String bodyAr = '',
    String bodyEn = '',
    String type = 'info',
    String? referenceType,
    String? referenceId,
  }) async {
    final result = await _client.rpc(
      'erp_r49_create_cloud_notification',
      params: {
        'p_company_id': _companyId,
        'p_user_id': userId,
        'p_role_id': roleId,
        'p_title_ar': titleAr.trim(),
        'p_title_en': titleEn.trim(),
        'p_body_ar': bodyAr.trim(),
        'p_body_en': bodyEn.trim(),
        'p_type': type,
        'p_reference_type': referenceType,
        'p_reference_id': referenceId,
      },
    );
    return result.toString();
  }

  Future<List<Map<String, Object?>>> loadPersistentNotifications({
    bool unreadOnly = false,
    int limit = 100,
    int offset = 0,
  }) async {
    final rows = await _client.rpc(
      'erp_r49_list_cloud_notifications',
      params: {
        'p_company_id': _companyId,
        'p_unread_only': unreadOnly,
        'p_limit': limit.clamp(1, 500),
        'p_offset': offset < 0 ? 0 : offset,
      },
    );
    return (rows as List)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList(growable: false);
  }

  Future<int> unreadCount() async {
    final result = await _client.rpc(
      'erp_r49_cloud_unread_notification_count',
      params: {'p_company_id': _companyId},
    );
    final count = (result as num?)?.toInt() ?? 0;
    NotificationUnreadState.update(count);
    return count;
  }

  Future<void> markAsRead(String id) async {
    await _client.rpc(
      'erp_r49_mark_cloud_notification_read',
      params: {'p_company_id': _companyId, 'p_notification_id': id},
    );
    NotificationUnreadState.update(NotificationUnreadState.count.value - 1);
  }

  Future<void> markAllAsRead() async {
    await _client.rpc(
      'erp_r49_mark_all_cloud_notifications_read',
      params: {'p_company_id': _companyId},
    );
    NotificationUnreadState.update(0);
  }

  Future<void> archiveNotification(String id) async {
    await _client.rpc(
      'erp_r49_archive_cloud_notification',
      params: {'p_company_id': _companyId, 'p_notification_id': id},
    );
  }

  static NotificationSeverity _severity(String? value) => switch (value) {
    'critical' => NotificationSeverity.critical,
    'warning' => NotificationSeverity.warning,
    _ => NotificationSeverity.info,
  };
  static IconData _icon(String? value) => switch (value) {
    'installment' => Icons.event_busy_outlined,
    'stock' => Icons.inventory_2_outlined,
    'car' => Icons.garage_outlined,
    'cash' => Icons.account_balance_wallet_outlined,
    _ => Icons.notifications_outlined,
  };
  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
