import 'field_permission_catalog.dart';
import 'permission_model.dart';

class _PermissionActionSpec {
  const _PermissionActionSpec(this.suffix, this.name, [this.description = '']);
  final String suffix;
  final String name;
  final String description;
}

class _PermissionModuleSpec {
  const _PermissionModuleSpec({
    required this.key,
    required this.label,
    required this.actions,
    this.recordScoped = true,
  });
  final String key;
  final String label;
  final List<_PermissionActionSpec> actions;
  final bool recordScoped;
}

/// Canonical permission catalog used by role and per-user permission editors.
abstract final class PermissionCatalog {
  static const _view = _PermissionActionSpec('view', 'عرض');
  static const _create = _PermissionActionSpec('create', 'إضافة');
  static const _update = _PermissionActionSpec('update', 'تعديل');
  static const _delete = _PermissionActionSpec('delete', 'حذف');
  static const _print = _PermissionActionSpec('print', 'طباعة');
  static const _export = _PermissionActionSpec('export', 'تصدير');

  static const List<_PermissionModuleSpec> _modules = [
    _PermissionModuleSpec(
      key: 'users',
      label: 'المستخدمون',
      actions: [_view, _create, _update, _delete, _print, _export],
    ),
    _PermissionModuleSpec(
      key: 'customers',
      label: 'العملاء',
      actions: [_view, _create, _update, _delete, _print, _export],
    ),
    _PermissionModuleSpec(
      key: 'suppliers',
      label: 'الموردون',
      actions: [_view, _create, _update, _delete, _print, _export],
    ),
    _PermissionModuleSpec(
      key: 'cars',
      label: 'السيارات',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('transfer.delete', 'حذف نقل سيارة'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'inventory',
      label: 'المخزون والمنتجات',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('transfer', 'نقل مخزني'),
        _PermissionActionSpec('transfer.delete', 'حذف نقل مخزني'),
        _PermissionActionSpec('adjust', 'تسوية وجرد'),
        _PermissionActionSpec('receive', 'استلام مخزني'),
        _PermissionActionSpec('issue', 'تجهيز/صرف مخزني'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'warehouses',
      label: 'المخازن',
      actions: [_view, _create, _update, _delete, _print, _export],
    ),
    _PermissionModuleSpec(
      key: 'customer_service',
      label: 'خدمة العملاء والفرص',
      actions: [_view, _create, _update, _delete, _print, _export],
    ),
    _PermissionModuleSpec(
      key: 'sales',
      label: 'المبيعات',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('approve', 'تصديق'),
        _PermissionActionSpec('cancel', 'إلغاء'),
        _PermissionActionSpec('delivery', 'إنشاء/إدارة التجهيز'),
        _PermissionActionSpec('invoice', 'إنشاء/إدارة الفاتورة'),
        _PermissionActionSpec('payment', 'تسجيل دفعة'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'purchases',
      label: 'المشتريات',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('approve', 'تصديق'),
        _PermissionActionSpec('cancel', 'إلغاء'),
        _PermissionActionSpec('receipt', 'إنشاء/إدارة الاستلام'),
        _PermissionActionSpec('invoice', 'إنشاء/إدارة الفاتورة'),
        _PermissionActionSpec('payment', 'تسجيل دفعة'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'maintenance',
      label: 'الصيانة',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('approve', 'تصديق'),
        _PermissionActionSpec('cancel', 'إلغاء'),
        _PermissionActionSpec('issue', 'صرف/إرجاع مواد'),
        _PermissionActionSpec('invoice', 'إنشاء/إدارة الفاتورة'),
        _PermissionActionSpec('payment', 'تسجيل دفعة'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'accounting',
      label: 'المحاسبة',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('post', 'ترحيل/تصديق قيد'),
        _PermissionActionSpec('reverse', 'عكس قيد'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'cashbox',
      label: 'الصناديق والحركات النقدية',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('receipt', 'سند قبض'),
        _PermissionActionSpec('payment', 'سند صرف'),
        _PermissionActionSpec('transfer', 'تحويل بين الصناديق'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'expenses',
      label: 'المصروفات',
      actions: [_view, _create, _update, _delete, _print, _export],
    ),
    _PermissionModuleSpec(
      key: 'installments',
      label: 'الأقساط',
      actions: [
        _view,
        _create,
        _update,
        _delete,
        _PermissionActionSpec('collect', 'تحصيل قسط'),
        _print,
        _export,
      ],
    ),
    _PermissionModuleSpec(
      key: 'dashboard',
      label: 'لوحة التحكم',
      recordScoped: false,
      actions: [_view],
    ),
    _PermissionModuleSpec(
      key: 'reports',
      label: 'التقارير',
      recordScoped: false,
      actions: [_view, _export],
    ),
    _PermissionModuleSpec(
      key: 'approvals',
      label: 'الموافقات',
      recordScoped: false,
      actions: [_view, _PermissionActionSpec('decide', 'الموافقة/الرفض')],
    ),
    _PermissionModuleSpec(
      key: 'periods',
      label: 'الفترات التشغيلية',
      recordScoped: false,
      actions: [
        _view,
        _PermissionActionSpec('close', 'إغلاق/إدارة فترة'),
        _PermissionActionSpec('reopen', 'إعادة فتح فترة'),
      ],
    ),
    _PermissionModuleSpec(
      key: 'audit',
      label: 'سجل التدقيق',
      recordScoped: false,
      actions: [_view, _export],
    ),
    _PermissionModuleSpec(
      key: 'settings',
      label: 'الإعدادات',
      recordScoped: false,
      actions: [
        _view,
        _PermissionActionSpec('backup', 'نسخة احتياطية'),
        _PermissionActionSpec('restore', 'استعادة نسخة'),
      ],
    ),
  ];

  static PermissionModel _permission(
    _PermissionModuleSpec module,
    _PermissionActionSpec action,
  ) {
    final code = '${module.key}.${action.suffix}';
    return PermissionModel(
      id: 'catalog-${code.replaceAll('.', '-')}',
      code: code,
      name: '${action.name} ${module.label}',
      module: module.label,
      description: action.description,
    );
  }

  static Iterable<PermissionModel> _modulePermissions(
    _PermissionModuleSpec module,
  ) sync* {
    for (final action in module.actions) {
      yield _permission(module, action);
    }
    if (module.recordScoped) {
      yield PermissionModel(
        id: 'catalog-${module.key}-records-own',
        code: '${module.key}.records.own',
        name: 'عرض إدخالات المستخدم نفسه فقط',
        module: '${module.label} • نطاق السجلات',
        description: 'يقيد قوائم هذا المودل بالسجلات التي أنشأها المستخدم الحالي.',
      );
      yield PermissionModel(
        id: 'catalog-${module.key}-records-all',
        code: '${module.key}.records.all',
        name: 'عرض إدخالات جميع المستخدمين',
        module: '${module.label} • نطاق السجلات',
        description: 'يسمح بعرض سجلات بقية مستخدمي الشركة داخل هذا المودل.',
      );
    }
  }

  static const List<PermissionModel> _granular = [
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

  static final List<PermissionModel> all = <PermissionModel>[
    for (final module in _modules) ..._modulePermissions(module),
    ..._granular,
    const PermissionModel(
      id: 'catalog-scopes',
      code: 'permissions.scopes.manage',
      name: 'إدارة الصلاحيات المخصصة للمستخدمين',
      module: 'المستخدمون',
      description: 'منح وسحب صلاحيات مستخدم واحد بصورة مستقلة عن دوره.',
    ),
    const PermissionModel(
      id: 'catalog-recycle-view',
      code: 'settings.recycle_bin.view',
      name: 'عرض سلة المحذوفات',
      module: 'الإعدادات',
      description: '',
    ),
    const PermissionModel(
      id: 'catalog-recycle-restore',
      code: 'settings.recycle_bin.restore',
      name: 'استعادة المحذوفات',
      module: 'الإعدادات',
      description: '',
    ),
    const PermissionModel(
      id: 'catalog-recycle-purge',
      code: 'settings.recycle_bin.purge',
      name: 'الحذف النهائي',
      module: 'الإعدادات',
      description: '',
    ),
    ...FieldPermissionCatalog.all,
  ];

  static List<PermissionModel> forModuleKey(String moduleKey) {
    final prefix = '$moduleKey.';
    return all
        .where((permission) => permission.code.startsWith(prefix))
        .toList(growable: false);
  }

  static String? recordScopeFor(Set<String> codes, String moduleKey) {
    if (codes.contains('$moduleKey.records.all')) return 'all';
    if (codes.contains('$moduleKey.records.own')) return 'own';
    return null;
  }

  static Set<String> withRecordScope(
    Set<String> codes,
    String moduleKey,
    String? scope,
  ) {
    final next = Set<String>.from(codes)
      ..remove('$moduleKey.records.own')
      ..remove('$moduleKey.records.all');
    if (scope == 'own' || scope == 'all') next.add('$moduleKey.records.$scope');
    return next;
  }
}
