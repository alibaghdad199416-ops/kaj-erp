/// Route identifiers shared by navigation widgets and feature pages.
///
/// This file intentionally imports no Flutter widgets or feature modules. It
/// keeps feature code from importing `app/routes.dart`, which owns page
/// construction and would otherwise create a large circular import graph.
abstract final class AppRouteNames {
  static const splash = '/';
  static const login = '/login';
  static const cloudAccount = '/cloud-account';

  static const dashboard = '/dashboard';
  static const globalSearch = '/global-search';
  static const notifications = '/notifications';
  static const products = '/products';
  static const inventory = '/inventory';
  static const maintenance = '/maintenance';
  static const businessPartners = '/business-partners';
  static const customerService = '/customer-service';
  static const sales = '/sales';
  static const purchases = '/purchases';
  static const accounting = '/accounting';
  static const settings = '/settings';
  static const reports = '/settings/reports';
}
