import 'erp_module.dart';

/// Canonical registry for the eleven accepted Quality Line ERP modules.
///
/// Authentication, reports, audit helpers and workflow engines are supporting
/// capabilities and must not register themselves as independent modules.
class ErpModuleRegistry {
  ErpModuleRegistry._();

  static const List<ErpModule> modules = <ErpModule>[
    ErpModule(
      code: 'dashboard',
      nameAr: 'لوحة التحكم',
      nameEn: 'Dashboard',
      route: '/dashboard',
      status: ErpModuleStatus.stable,
      permissions: <String>['dashboard.view'],
      capabilities: <String>['kpis', 'filters', 'charts', 'live_refresh'],
    ),
    ErpModule(
      code: 'global_search',
      nameAr: 'البحث الشامل',
      nameEn: 'Global Search',
      route: '/global-search',
      status: ErpModuleStatus.stable,
      dependencies: <String>[
        'inventory',
        'maintenance',
        'business_partners',
        'customer_service',
        'sales',
        'purchases',
        'accounting',
      ],
      permissions: <String>['dashboard.view'],
      capabilities: <String>['permission_scoped_search', 'record_navigation'],
    ),
    ErpModule(
      code: 'notifications',
      nameAr: 'مركز الإشعارات',
      nameEn: 'Notification Center',
      route: '/notifications',
      status: ErpModuleStatus.stable,
      dependencies: <String>[
        'inventory',
        'maintenance',
        'customer_service',
        'sales',
        'purchases',
        'accounting',
      ],
      permissions: <String>['dashboard.view'],
      capabilities: <String>[
        'read_state',
        'deduplication',
        'record_navigation',
      ],
    ),
    ErpModule(
      code: 'inventory',
      nameAr: 'المخزون',
      nameEn: 'Inventory',
      route: '/inventory',
      status: ErpModuleStatus.stable,
      dependencies: <String>[],
      permissions: <String>['inventory.view', 'cars.view'],
      capabilities: <String>[
        'cars',
        'warehouses',
        'stock_balances',
        'transfers',
        'reservations',
        'adjustments',
      ],
    ),
    ErpModule(
      code: 'maintenance',
      nameAr: 'الصيانة',
      nameEn: 'Maintenance',
      route: '/maintenance',
      status: ErpModuleStatus.stable,
      dependencies: <String>['inventory', 'business_partners', 'accounting'],
      permissions: <String>['maintenance.view'],
      capabilities: <String>['orders', 'parts', 'appointments', 'payments'],
    ),
    ErpModule(
      code: 'business_partners',
      nameAr: 'الشركاء التجاريون',
      nameEn: 'Business Partners',
      route: '/business-partners',
      status: ErpModuleStatus.stable,
      permissions: <String>['customers.view', 'suppliers.view'],
      capabilities: <String>['customers', 'suppliers', 'statements', 'credit'],
    ),
    ErpModule(
      code: 'customer_service',
      nameAr: 'خدمة العملاء',
      nameEn: 'Customer Service',
      route: '/customer-service',
      status: ErpModuleStatus.stable,
      dependencies: <String>['business_partners'],
      permissions: <String>['customer_service.view'],
      capabilities: <String>['tickets', 'follow_up', 'timeline', 'attachments'],
    ),
    ErpModule(
      code: 'sales',
      nameAr: 'المبيعات',
      nameEn: 'Sales',
      route: '/sales',
      status: ErpModuleStatus.stable,
      dependencies: <String>['inventory', 'business_partners', 'accounting'],
      permissions: <String>['sales.view'],
      capabilities: <String>['orders', 'delivery', 'invoicing', 'payments'],
    ),
    ErpModule(
      code: 'purchases',
      nameAr: 'المشتريات',
      nameEn: 'Purchases',
      route: '/purchases',
      status: ErpModuleStatus.stable,
      dependencies: <String>['inventory', 'business_partners', 'accounting'],
      permissions: <String>['purchases.view'],
      capabilities: <String>['orders', 'receipts', 'vendor_bills', 'payments'],
    ),
    ErpModule(
      code: 'accounting',
      nameAr: 'المحاسبة',
      nameEn: 'Accounting',
      route: '/accounting',
      status: ErpModuleStatus.stable,
      dependencies: <String>['business_partners'],
      permissions: <String>['accounting.view'],
      capabilities: <String>[
        'chart_of_accounts',
        'double_entry',
        'payments',
        'ledger',
        'currencies',
        'financial_reports',
      ],
    ),
    ErpModule(
      code: 'settings',
      nameAr: 'الإعدادات',
      nameEn: 'Settings',
      route: '/settings',
      status: ErpModuleStatus.stable,
      permissions: <String>['settings.view', 'users.view', 'reports.view'],
      capabilities: <String>[
        'company',
        'users',
        'roles',
        'localization',
        'notifications',
        'reports',
        'audit',
      ],
    ),
  ];

  static Map<String, ErpModule> get byCode => <String, ErpModule>{
    for (final module in modules) module.code: module,
  };

  static ErpModule? find(String code) => byCode[code];

  static List<ErpModule> available({Set<String>? permissions}) {
    if (permissions == null || permissions.isEmpty) {
      return List<ErpModule>.unmodifiable(modules.where((m) => m.isAvailable));
    }
    return List<ErpModule>.unmodifiable(
      modules.where(
        (module) =>
            module.isAvailable &&
            (module.permissions.isEmpty ||
                module.permissions.any(permissions.contains)),
      ),
    );
  }

  static List<ErpModule> resolveDependencies(Iterable<String> moduleCodes) {
    final selected = <String>{};

    void addModule(String code) {
      if (!selected.add(code)) return;
      final module = find(code);
      if (module == null) return;
      for (final dependency in module.dependencies) {
        addModule(dependency);
      }
    }

    for (final code in moduleCodes) {
      addModule(code);
    }

    return modules
        .where((module) => selected.contains(module.code))
        .toList(growable: false);
  }

  static ModuleValidationResult validate() {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final module in modules) {
      if (!seen.add(module.code)) duplicates.add(module.code);
    }

    final known = byCode.keys.toSet();
    final missing = <String>{};
    for (final module in modules) {
      for (final dependency in module.dependencies) {
        if (!known.contains(dependency)) {
          missing.add('${module.code}:$dependency');
        }
      }
    }

    final cycles = <String>{};
    final visiting = <String>{};
    final visited = <String>{};

    void visit(String code, List<String> path) {
      if (visiting.contains(code)) {
        cycles.add(<String>[...path, code].join(' -> '));
        return;
      }
      if (!visited.add(code)) return;
      visiting.add(code);
      final module = find(code);
      for (final dependency in module?.dependencies ?? const <String>[]) {
        visit(dependency, <String>[...path, code]);
      }
      visiting.remove(code);
    }

    for (final module in modules) {
      visit(module.code, const <String>[]);
    }

    return ModuleValidationResult(
      isValid: duplicates.isEmpty && missing.isEmpty && cycles.isEmpty,
      duplicateCodes: duplicates.toList(growable: false)..sort(),
      missingDependencies: missing.toList(growable: false)..sort(),
      circularDependencies: cycles.toList(growable: false)..sort(),
    );
  }
}
