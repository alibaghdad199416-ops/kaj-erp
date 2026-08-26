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
/// Only the accepted business modules are exposed as top-level routes.
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
  static const reports = AppRouteNames.reports;

  static final Set<String> businessModuleRoutes = ErpModuleRegistry.modules
      .map((module) => module.route)
      .toSet();

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
    // Products and inventory are distinct route contracts. Products must open
    // the products tab rather than silently landing on the cars tab.
    products: (_) => _protected(
      route: products,
      permission: 'inventory.view',
      child: const StockCatalogPage(initialIndex: 2),
    ),
    inventory: (_) => _protected(
      route: inventory,
      permission: 'inventory.view',
      child: const StockCatalogPage(initialIndex: 0),
    ),
    maintenance: (_) => _protected(
      route: maintenance,
      permission: 'maintenance.view',
      child: const MaintenancePage(),
    ),
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
    sales: (_) => _protected(
      route: sales,
      permission: 'sales.view',
      child: const SalesOperationsPage(),
    ),
    purchases: (_) => _protected(
      route: purchases,
      permission: 'purchases.view',
      child: const PurchaseOperationsPage(),
    ),
    accounting: (_) => _protected(
      route: accounting,
      permission: 'accounting.view',
      child: const AccountingCenterPage(),
    ),
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
