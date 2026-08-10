import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:quality_line_erp/core/cloud/erp_runtime_capabilities_controller.dart';
import 'package:quality_line_erp/core/events/app_data_refresh_coordinator.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/features/accounting/cashbox/controllers/cashbox_controller.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/expenses/controllers/expenses_controller.dart';
import 'package:quality_line_erp/features/accounting/installments/controllers/installments_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/controllers/suppliers_controller.dart';
import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/dashboard/controllers/dashboard_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/car_images_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/maintenance/controllers/maintenance_controller.dart';
import 'package:quality_line_erp/features/purchases/controllers/purchases_controller.dart';
import 'package:quality_line_erp/features/sales/controllers/sales_controller.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/controllers/settings_controller.dart';
import 'package:quality_line_erp/features/settings/reports/controllers/reports_controller.dart';

/// Application composition root.
///
/// All long-lived controllers and cross-module refresh dependencies are
/// declared here. Adding a module no longer requires editing `main.dart` in
/// several places, which was a common source of missing providers and stale UI.
class AppDependencies {
  AppDependencies._({
    required this.runtimeCapabilities,
    required this.preferences,
    required this.cars,
    required this.carImages,
    required this.opportunities,
    required this.customers,
    required this.suppliers,
    required this.sales,
    required this.expenses,
    required this.inventory,
    required this.maintenance,
    required this.dashboard,
    required this.reports,
    required this.installments,
    required this.purchases,
    required this.cashbox,
    required this.accounting,
    required this.access,
    required this.settings,
  }) {
    refreshCoordinator = AppDataRefreshCoordinator(rules: _buildRefreshRules());
  }

  factory AppDependencies.create() {
    final access = AccessController();
    return AppDependencies._(
      runtimeCapabilities: ErpRuntimeCapabilitiesController(),
      preferences: AppPreferencesController(),
      cars: CarsController(),
      carImages: CarImagesController(),
      opportunities: OpportunitiesController(),
      customers: CustomersController(),
      suppliers: SuppliersController(),
      sales: SalesController(),
      expenses: ExpensesController(),
      inventory: InventoryController(),
      maintenance: MaintenanceController(),
      dashboard: DashboardController(),
      reports: ReportsController(),
      installments: InstallmentsController(),
      purchases: PurchasesController(),
      cashbox: CashboxController(),
      accounting: AccountingController(),
      access: access,
      settings: SettingsController(accessController: access),
    );
  }

  final ErpRuntimeCapabilitiesController runtimeCapabilities;
  final AppPreferencesController preferences;
  final CarsController cars;
  final CarImagesController carImages;
  final OpportunitiesController opportunities;
  final CustomersController customers;
  final SuppliersController suppliers;
  final SalesController sales;
  final ExpensesController expenses;
  final InventoryController inventory;
  final MaintenanceController maintenance;
  final DashboardController dashboard;
  final ReportsController reports;
  final InstallmentsController installments;
  final PurchasesController purchases;
  final CashboxController cashbox;
  final AccountingController accounting;
  final AccessController access;
  final SettingsController settings;
  late final AppDataRefreshCoordinator refreshCoordinator;

  List<SingleChildWidget> get providers => <SingleChildWidget>[
    Provider<AppDataRefreshCoordinator>.value(value: refreshCoordinator),
    ChangeNotifierProvider<ErpRuntimeCapabilitiesController>.value(
      value: runtimeCapabilities,
    ),
    ChangeNotifierProvider<AppPreferencesController>.value(value: preferences),
    ChangeNotifierProvider<CarsController>.value(value: cars),
    ChangeNotifierProvider<CarImagesController>.value(value: carImages),
    ChangeNotifierProvider<OpportunitiesController>.value(value: opportunities),
    ChangeNotifierProvider<CustomersController>.value(value: customers),
    ChangeNotifierProvider<SuppliersController>.value(value: suppliers),
    ChangeNotifierProvider<SalesController>.value(value: sales),
    ChangeNotifierProvider<ExpensesController>.value(value: expenses),
    ChangeNotifierProvider<InventoryController>.value(value: inventory),
    ChangeNotifierProvider<MaintenanceController>.value(value: maintenance),
    ChangeNotifierProvider<DashboardController>.value(value: dashboard),
    ChangeNotifierProvider<ReportsController>.value(value: reports),
    ChangeNotifierProvider<InstallmentsController>.value(value: installments),
    ChangeNotifierProvider<PurchasesController>.value(value: purchases),
    ChangeNotifierProvider<CashboxController>.value(value: cashbox),
    ChangeNotifierProvider<AccountingController>.value(value: accounting),
    ChangeNotifierProvider<AccessController>.value(value: access),
    ChangeNotifierProvider<SettingsController>.value(value: settings),
  ];

  List<AppDataRefreshRule> _buildRefreshRules() => <AppDataRefreshRule>[
    AppDataRefreshRule(
      id: 'cars',
      sources: const {'cars'},
      refresh: (_) => cars.hasLoaded ? cars.loadCars() : Future<void>.value(),
    ),
    AppDataRefreshRule(
      id: 'car-images-cache',
      sources: const {'car_images'},
      refresh: (_) async => carImages.invalidateAll(),
    ),
    AppDataRefreshRule(
      id: 'opportunities',
      sources: const {'opportunities'},
      refresh: (_) => opportunities.loadOpportunities(),
    ),
    AppDataRefreshRule(
      id: 'customers',
      sources: const {'customers', 'business_partners'},
      refresh: (_) => customers.hasLoaded
          ? customers.loadCustomers()
          : Future<void>.value(),
    ),
    AppDataRefreshRule(
      id: 'suppliers',
      sources: const {'suppliers', 'business_partners'},
      refresh: (_) => suppliers.hasLoaded
          ? suppliers.loadSuppliers()
          : Future<void>.value(),
    ),
    AppDataRefreshRule(
      id: 'sales',
      sources: const {'sales'},
      refresh: (_) =>
          sales.hasLoaded ? sales.loadSales() : Future<void>.value(),
    ),
    AppDataRefreshRule(
      id: 'purchases',
      sources: const {'purchases'},
      refresh: (_) => purchases.hasLoaded
          ? purchases.loadPurchases()
          : Future<void>.value(),
    ),
    AppDataRefreshRule(
      id: 'inventory',
      sources: const {'inventory'},
      refresh: (_) async {
        inventory.invalidateInventoryCache();
        inventory.invalidateMaintenanceCatalog();
        if (inventory.hasLoaded) await inventory.loadInventory(force: true);
      },
    ),
    AppDataRefreshRule(
      id: 'maintenance',
      sources: const {'maintenance'},
      refresh: (_) async {
        maintenance.invalidateEligibleVehicles();
        if (maintenance.hasLoaded) await maintenance.loadOrders(force: true);
      },
    ),
    AppDataRefreshRule(
      id: 'installments',
      sources: const {'installments'},
      refresh: (_) => installments.loadInstallments(),
    ),
    AppDataRefreshRule(
      id: 'expenses',
      sources: const {'expenses'},
      refresh: (_) => expenses.loadExpenses(),
    ),
    AppDataRefreshRule(
      id: 'cashbox',
      sources: const {'cashbox'},
      refresh: (_) => cashbox.loadTransactions(),
    ),
    AppDataRefreshRule(
      id: 'accounting',
      sources: const {'accounting'},
      refresh: (_) => accounting.loadAccounting(),
    ),
    AppDataRefreshRule(
      id: 'access',
      sources: const {'users', 'access'},
      refresh: (_) => access.loadAccess(force: true),
    ),
    AppDataRefreshRule(
      id: 'settings',
      sources: const {'settings'},
      refresh: (_) => settings.loadSettings(),
    ),
    AppDataRefreshRule(
      id: 'dashboard',
      sources: _aggregateSources,
      debounce: const Duration(milliseconds: 1400),
      refresh: (_) => dashboard.hasLoaded
          ? dashboard.loadDashboard(force: true)
          : Future<void>.value(),
    ),
    AppDataRefreshRule(
      id: 'reports',
      sources: _aggregateSources,
      debounce: const Duration(milliseconds: 2000),
      refresh: (_) => reports.hasLoaded
          ? reports.loadReports(
              startDate: reports.startDate,
              endDate: reports.endDate,
              force: true,
            )
          : Future<void>.value(),
    ),
  ];

  static const Set<String> _aggregateSources = <String>{
    'cars',
    'car_images',
    'inventory',
    'sales',
    'purchases',
    'maintenance',
    'expenses',
    'cashbox',
    'accounting',
    'installments',
    'customers',
    'suppliers',
    'business_partners',
    'opportunities',
  };
}
