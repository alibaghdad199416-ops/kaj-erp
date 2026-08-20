import 'package:flutter/material.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/platform/erp_module_registry.dart';
import 'package:quality_line_erp/core/widgets/app_module_shell.dart';
import 'package:quality_line_erp/features/accounting/pages/accounting_center_page.dart';
import 'package:quality_line_erp/features/auth/pages/cloud_account_page.dart';
import 'package:quality_line_erp/features/auth/pages/login_page.dart';
import 'package:quality_line_erp/features/business_partners/pages/business_partners_page.dart';
import 'package:quality_line_erp/features/customer_service/pages/customer_service_page.dart';
import 'package:quality_line_erp/features/dashboard/pages/dashboard_page.dart';
import 'package:quality_line_erp/features/global_search/pages/global_search_page.dart';
import 'package:quality_line_erp/features/inventory/pages/stock_catalog_page.dart';
import 'package:quality_line_erp/features/maintenance/pages/maintenance_page.dart';
import 'package:quality_line_erp/features/notifications/pages/notification_center_page.dart';
import 'package:quality_line_erp/features/purchases/pages/purchase_operations_page.dart';
import 'package:quality_line_erp/features/sales/pages/sales_operations_page.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_guard.dart';
import 'package:quality_line_erp/features/settings/pages/settings_hub_page.dart';
import 'package:quality_line_erp/features/splash/pages/splash_page.dart';

/// Canonical application routes.
///
/// Only the eleven accepted business modules are exposed as top-level routes.
/// Authentication routes and the reports sub-route are infrastructure/utility
/// routes and are intentionally not registered as ERP modules.
class AppRoutes {
  static const splash = AppRouteNames.splash;
  static const login = AppRouteNames.login;
  static const cloudAccount = AppRouteNames.cloudAccount;

  static const dashboard = AppRouteNames.dashboard;
  static const globalSearch = AppRouteNames.globalSearch;
  static const notifications = AppRouteNames.notifications;
  static const products = AppRouteNames.products;
  static const inventory = AppRouteNames.inventory;
  static const maintenance = AppRouteNames.maintenance;
  static const businessPartners = AppRouteNames.businessPartners;
  static const customerService = AppRouteNames.customerService;
  static const sales = AppRouteNames.sales;
  static const purchases = AppRouteNames.purchases;
  static const accounting = AppRouteNames.accounting;
  static const settings = AppRouteNames.settings;

  /// Cross-module reports live inside Settings and are not a standalone module.
  static const reports = AppRouteNames.reports;

  static final Set<String> businessModuleRoutes = ErpModuleRegistry.modules
      .map((module) => module.route)
      .toSet();

  static Map<String, Object?> _routeArguments(BuildContext context) {
    final value = ModalRoute.of(context)?.settings.arguments;
    if (value is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(value);
  }

  static Widget _protected({
    required String route,
    required String permission,
    required Widget child,
  }) {
    return PermissionGuard(
      permission: permission,
      child: AppModuleShell(route: route, child: child),
    );
  }

  static final Map<String, WidgetBuilder> routes = {
    splash: (_) => const SplashPage(),
    login: (_) => const LoginPage(),
    cloudAccount: (_) => const CloudAccountPage(),
    dashboard: (_) => _protected(
      route: dashboard,
      permission: 'dashboard.view',
      child: const DashboardPage(),
    ),
    globalSearch: (_) => _protected(
      route: globalSearch,
      permission: 'dashboard.view',
      child: const GlobalSearchPage(),
    ),
    notifications: (_) => _protected(
      route: notifications,
      permission: 'dashboard.view',
      child: const NotificationCenterPage(),
    ),
    products: (_) => _protected(
      route: inventory,
      permission: 'inventory.view',
      child: const StockCatalogPage(initialIndex: 0),
    ),
    inventory: (context) {
      final args = _routeArguments(context);
      return _protected(
        route: inventory,
        permission: 'inventory.view',
        child: StockCatalogPage(
          initialIndex: 0,
          initialCarId: (args['carId'] ?? args['referenceId'])?.toString(),
        ),
      );
    },
    maintenance: (context) {
      final args = _routeArguments(context);
      return _protected(
        route: maintenance,
        permission: 'maintenance.view',
        child: MaintenancePage(initialOrderId: args['referenceId']?.toString()),
      );
    },
    businessPartners: (_) => _protected(
      route: businessPartners,
      permission: 'customers.view',
      child: const BusinessPartnersPage(),
    ),
    customerService: (_) => _protected(
      route: customerService,
      permission: 'customer_service.view',
      child: const CustomerServicePage(),
    ),
    sales: (context) {
      final args = _routeArguments(context);
      return _protected(
        route: sales,
        permission: 'sales.view',
        child: SalesOperationsPage(
          initialOrderId: args['referenceId']?.toString(),
        ),
      );
    },
    purchases: (context) {
      final args = _routeArguments(context);
      return _protected(
        route: purchases,
        permission: 'purchases.view',
        child: PurchaseOperationsPage(
          initialOrderId: args['referenceId']?.toString(),
        ),
      );
    },
    accounting: (context) {
      final args = _routeArguments(context);
      final cashboxId = args['cashboxId']?.toString();
      return _protected(
        route: accounting,
        permission: 'accounting.view',
        child: AccountingCenterPage(
          initialSection: cashboxId == null || cashboxId.isEmpty ? 0 : 2,
          initialCashboxId: cashboxId,
        ),
      );
    },
    settings: (_) => _protected(
      route: settings,
      permission: 'settings.view',
      child: const SettingsHubPage(),
    ),
    reports: (_) => _protected(
      route: reports,
      permission: 'reports.view',
      child: const SettingsHubPage(initialIndex: 3),
    ),
  };
}
