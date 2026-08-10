import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/features/notifications/repositories/notification_center_repository.dart';
import 'cloud_tenant_context.dart';

enum CloudRealtimeState { stopped, connecting, connected, degraded }

/// Connects tenant-scoped Supabase Realtime changes to the application's
/// existing invalidation bus.
///
/// PostgreSQL remains authoritative. Incoming bursts are coalesced per source
/// before controllers are asked to reload, preventing multiple expensive
/// refreshes when one database transaction touches several related rows.
class CloudRealtimeBridge {
  CloudRealtimeBridge._();

  static final CloudRealtimeBridge instance = CloudRealtimeBridge._();

  final List<RealtimeChannel> _channels = <RealtimeChannel>[];
  final Map<String, Timer> _sourceTimers = <String, Timer>{};
  final ValueNotifier<CloudRealtimeState> state =
      ValueNotifier<CloudRealtimeState>(CloudRealtimeState.stopped);

  String? _companyId;
  int _generation = 0;
  Timer? _notificationTimer;

  bool get isRunning =>
      state.value == CloudRealtimeState.connected &&
      _channels.isNotEmpty &&
      _companyId != null;

  Future<void> start() async {
    final companyId = CloudTenantContext.instance.companyUuid?.trim() ?? '';
    final companySlug = CloudTenantContext.instance.companyId.trim();
    if (companyId.isEmpty ||
        Supabase.instance.client.auth.currentUser == null) {
      throw StateError(
        'لا يمكن تشغيل التحديث اللحظي قبل تفعيل الشركة والجلسة.',
      );
    }
    if (_companyId == companyId && isRunning) return;

    await stop();
    state.value = CloudRealtimeState.connecting;
    _companyId = companyId;
    final generation = ++_generation;

    var channel = Supabase.instance.client.channel(
      'erp:runtime:$companyId:$generation',
    );
    for (final binding in _bindings) {
      final tenantValue = binding.usesCompanySlug ? companySlug : companyId;
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: binding.table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: binding.tenantColumn,
          value: tenantValue,
        ),
        callback: (payload) {
          if (_generation != generation || _companyId != companyId) return;
          final entityId = _entityId(payload);
          for (final source in binding.sources) {
            _publishCoalesced(source, entityId: entityId);
          }
          if (binding.refreshesUnreadNotifications) {
            _refreshUnreadCount();
          }
        },
      );
    }
    channel.subscribe((status, error) {
      if (_generation != generation || _companyId != companyId) return;
      if (error != null) {
        state.value = CloudRealtimeState.degraded;
        AppLogger.debug('Supabase ERP realtime subscription error: $error');
        return;
      }
      final normalized = status.toString().toLowerCase();
      if (normalized.contains('subscribed')) {
        state.value = CloudRealtimeState.connected;
      } else if (normalized.contains('channelerror') ||
          normalized.contains('timedout') ||
          normalized.contains('closed')) {
        state.value = CloudRealtimeState.degraded;
      }
    });
    _channels.add(channel);
  }

  void _publishCoalesced(String source, {String? entityId}) {
    _sourceTimers.remove(source)?.cancel();
    _sourceTimers[source] = Timer(const Duration(milliseconds: 180), () {
      _sourceTimers.remove(source);
      AppDataChangeBus.instance.publish(
        source,
        operation: 'cloud-realtime',
        entityId: entityId,
      );
    });
  }

  void _refreshUnreadCount() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        await NotificationCenterRepository().unreadCount();
      } catch (error) {
        AppLogger.debug('Realtime unread notification refresh skipped: $error');
      }
    });
  }

  String? _entityId(PostgresChangePayload payload) {
    final record = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;
    final value = record['id'];
    return value?.toString();
  }

  Future<void> stop() async {
    _generation += 1;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    for (final timer in _sourceTimers.values) {
      timer.cancel();
    }
    _sourceTimers.clear();
    final channels = List<RealtimeChannel>.from(_channels);
    _channels.clear();
    _companyId = null;
    state.value = CloudRealtimeState.stopped;
    for (final channel in channels) {
      try {
        await Supabase.instance.client.removeChannel(channel);
      } catch (error) {
        AppLogger.debug('Supabase Realtime channel cleanup skipped: $error');
      }
    }
  }

  static const List<_RealtimeBinding> _bindings = <_RealtimeBinding>[
    _RealtimeBinding('erp_cars', {'cars', 'inventory'}),
    _RealtimeBinding('erp_car_images', {'car_images', 'cars'}),
    _RealtimeBinding('erp_warehouses', {'inventory', 'cars'}),
    _RealtimeBinding('erp_car_warehouse_transfers', {'cars', 'inventory'}),
    _RealtimeBinding('erp_inventory', {'inventory'}),
    _RealtimeBinding('erp_inventory_groups', {'inventory'}),
    _RealtimeBinding('erp_warehouse_stock', {'inventory'}),
    _RealtimeBinding('erp_inventory_movements', {'inventory'}),
    _RealtimeBinding('erp_inventory_receipts', {'inventory', 'purchases'}),
    _RealtimeBinding('erp_inventory_product_sales', {'inventory', 'sales'}),
    _RealtimeBinding('erp_customers', {'customers', 'business_partners'}),
    _RealtimeBinding('erp_suppliers', {'suppliers', 'business_partners'}),
    _RealtimeBinding('erp_sales', {'sales'}),
    _RealtimeBinding('erp_installments', {'installments', 'sales'}),
    _RealtimeBinding('erp_purchases', {'purchases'}),
    _RealtimeBinding('erp_purchase_items', {'purchases'}),
    _RealtimeBinding('erp_sales_orders_cloud', {'sales'}),
    _RealtimeBinding('erp_sales_order_items_cloud', {'sales'}),
    _RealtimeBinding('erp_purchase_orders_cloud', {'purchases'}),
    _RealtimeBinding('erp_purchase_order_items_cloud', {'purchases'}),
    _RealtimeBinding('erp_commercial_workflow_documents', {
      'sales',
      'purchases',
      'inventory',
      'cashbox',
      'accounting',
    }),
    _RealtimeBinding('erp_commercial_workflow_audit', {
      'sales',
      'purchases',
      'accounting',
    }),
    _RealtimeBinding('erp_cash_accounts', {'cashbox', 'accounting'}),
    _RealtimeBinding('erp_cash_transactions', {'cashbox', 'accounting'}),
    _RealtimeBinding('erp_journal_entries', {'accounting'}),
    _RealtimeBinding('erp_journal_lines', {'accounting'}),
    _RealtimeBinding('erp_expenses', {'expenses', 'accounting', 'cashbox'}),
    _RealtimeBinding('erp_maintenance_orders', {
      'maintenance',
      'inventory',
      'accounting',
      'cashbox',
    }),
    _RealtimeBinding('erp_maintenance_parts', {'maintenance', 'inventory'}),
    _RealtimeBinding('erp_maintenance_payments', {
      'maintenance',
      'accounting',
      'cashbox',
    }),
    _RealtimeBinding('erp_fixed_assets', {'accounting'}),
    _RealtimeBinding('erp_fiscal_periods', {'accounting', 'settings'}),
    _RealtimeBinding('erp_reservations', {'inventory', 'sales', 'cars'}),
    _RealtimeBinding('erp_enterprise_notifications', {
      'notifications',
    }, refreshesUnreadNotifications: true),
    _RealtimeBinding('erp_records', {
      'users',
      'access',
      'settings',
      'opportunities',
    }, usesCompanySlug: true),
    _RealtimeBinding('erp_permission_roles', {'users', 'access', 'settings'}),
    _RealtimeBinding('erp_role_permission_grants', {
      'users',
      'access',
      'settings',
    }),
    _RealtimeBinding('erp_user_role_assignments', {
      'users',
      'access',
      'settings',
    }),
    _RealtimeBinding('company_memberships', {'users', 'access', 'settings'}),
    _RealtimeBinding('branches', {'settings', 'access'}),
    _RealtimeBinding('erp_accounts', {
      'accounting',
    }, tenantColumn: 'organization_id'),
  ];
}

class _RealtimeBinding {
  const _RealtimeBinding(
    this.table,
    this.sources, {
    this.tenantColumn = 'company_id',
    this.usesCompanySlug = false,
    this.refreshesUnreadNotifications = false,
  });

  final String table;
  final Set<String> sources;
  final String tenantColumn;
  final bool usesCompanySlug;
  final bool refreshesUnreadNotifications;
}
