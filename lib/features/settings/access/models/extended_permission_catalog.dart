import 'permission_model.dart';

/// Permissions added after the original static catalog. They are deliberately
/// kept in a small extension catalog so older role definitions remain stable
/// while the user/role editors can immediately expose new PostgreSQL-enforced
/// capabilities.
abstract final class ExtendedPermissionCatalog {
  static const List<PermissionModel> operational = <PermissionModel>[
    PermissionModel(
      id: 'catalog-users-image-update',
      code: 'users.image.update',
      name: 'تعديل صورة المستخدم',
      module: 'المستخدمون • الصور',
      description: 'رفع أو استبدال أو حذف صورة مستخدم قائم.',
    ),
    PermissionModel(
      id: 'catalog-users-credentials-update',
      code: 'users.credentials.update',
      name: 'تعديل بيانات دخول المستخدم',
      module: 'المستخدمون • الأمان',
      description: 'تعديل البريد أو بيانات الهوية السحابية الحساسة.',
    ),
    PermissionModel(
      id: 'catalog-customers-image-update',
      code: 'customers.image.update',
      name: 'تعديل صورة العميل',
      module: 'العملاء • الصور',
      description: 'رفع أو استبدال أو حذف صورة العميل.',
    ),
    PermissionModel(
      id: 'catalog-suppliers-image-update',
      code: 'suppliers.image.update',
      name: 'تعديل صورة المورد',
      module: 'الموردون • الصور',
      description: 'رفع أو استبدال أو حذف صورة المورد.',
    ),
    PermissionModel(
      id: 'catalog-cars-images-manage',
      code: 'cars.images.manage',
      name: 'إدارة صور السيارات',
      module: 'السيارات • الصور',
      description: 'إضافة أو حذف صور السيارة وصورتها الرئيسية.',
    ),
    PermissionModel(
      id: 'catalog-inventory-images-manage',
      code: 'inventory.images.manage',
      name: 'إدارة صور المنتجات',
      module: 'المخزون • الصور',
      description: 'إضافة أو حذف صور المنتج وصورته الرئيسية.',
    ),
    PermissionModel(
      id: 'catalog-reports-audit-view',
      code: 'reports.audit.view',
      name: 'عرض تفاصيل تدقيق التقارير',
      module: 'التقارير • التدقيق',
      description: 'عرض منفذي الإدخال وآثار العمليات داخل التقارير.',
    ),
    PermissionModel(
      id: 'catalog-reports-contextual-view',
      code: 'reports.contextual.view',
      name: 'عرض التفاصيل السياقية للتقارير',
      module: 'التقارير • التفاصيل',
      description: 'عرض الجداول والسجلات المرتبطة بالمودل المحدد.',
    ),
    PermissionModel(
      id: 'catalog-reports-financial-details-view',
      code: 'reports.financial_details.view',
      name: 'عرض التفاصيل المالية للتقارير',
      module: 'التقارير • المالية',
      description: 'عرض تفاصيل الحسابات والدفعات والذمم داخل مركز التقارير.',
    ),
  ];

  static const Map<String, String> recordScopedModules = <String, String>{
    'customers': 'العملاء',
    'suppliers': 'الموردون',
    'cars': 'السيارات',
    'inventory': 'المخزون والمنتجات',
    'warehouses': 'المخازن',
    'customer_service': 'خدمة العملاء والفرص',
    'sales': 'المبيعات',
    'purchases': 'المشتريات',
    'maintenance': 'الصيانة',
    'accounting': 'المحاسبة',
    'cashbox': 'الصناديق والحركات النقدية',
    'expenses': 'المصروفات',
    'installments': 'الأقساط',
  };

  static final List<PermissionModel> recordScopes = <PermissionModel>[
    for (final entry in recordScopedModules.entries) ...<PermissionModel>[
      PermissionModel(
        id: 'catalog-${entry.key}-records-own',
        code: '${entry.key}.records.own',
        name: 'عرض إدخالات المستخدم نفسه',
        module: '${entry.value} • نطاق السجلات',
        description:
            'عند تخصيص الصلاحيات لهذا المستخدم، يقيد هذا المودل بالسجلات التي أنشأها المستخدم نفسه.',
      ),
      PermissionModel(
        id: 'catalog-${entry.key}-records-all',
        code: '${entry.key}.records.all',
        name: 'عرض إدخالات جميع المستخدمين',
        module: '${entry.value} • نطاق السجلات',
        description:
            'يسمح بعرض سجلات بقية مستخدمي الشركة داخل هذا المودل.',
      ),
    ],
  ];

  static final List<PermissionModel> all = <PermissionModel>[
    ...operational,
    ...recordScopes,
  ];

  /// A module may never persist both scope choices. `all` wins when an old
  /// client or imported role submits both; otherwise `own` is retained.
  static Set<String> normalizeRecordScopes(Iterable<String> codes) {
    final result = codes.map((code) => code.trim()).where((code) => code.isNotEmpty).toSet();
    for (final module in recordScopedModules.keys) {
      final own = '$module.records.own';
      final all = '$module.records.all';
      if (result.contains(all)) result.remove(own);
    }
    return result;
  }
}
