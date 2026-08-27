import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_executor.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_components.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:quality_line_erp/design_system/kaj_query_toolbar.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class WarehouseManagementPage extends StatefulWidget {
  const WarehouseManagementPage({super.key});

  @override
  State<WarehouseManagementPage> createState() =>
      _WarehouseManagementPageState();
}

class _WarehouseManagementPageState extends State<WarehouseManagementPage> {
  late final UnifiedQueryController _queryController =
      UnifiedQueryController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<InventoryController>().loadInventory();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<WarehouseModel> _visible(List<WarehouseModel> warehouses) {
    final executor = UnifiedQueryExecutor<WarehouseModel>(
      criteriaBuilder: (state) => UnifiedFilterCriteria(
        searchText: state.search,
        statuses: state.filters
            .where((filter) => filter.key == 'status')
            .map((filter) => filter.value.toString())
            .toSet(),
        types: state.filters
            .where((filter) => filter.key == 'type')
            .map((filter) => filter.value.toString())
            .toSet(),
      ),
      filterAdapter: UnifiedFilterAdapter<WarehouseModel>(
        searchableText: (warehouse) => <Object?>[
          warehouse.code,
          warehouse.name,
          warehouse.branchId,
          warehouse.address,
          warehouse.notes,
        ],
        status: (warehouse) => warehouse.isActive ? 'active' : 'inactive',
        type: (warehouse) => warehouse.warehouseType,
      ),
      sort: (left, right, field) {
        switch (field) {
          case 'code':
            return left.code.toLowerCase().compareTo(right.code.toLowerCase());
          case 'type':
            return left.warehouseType
                .toLowerCase()
                .compareTo(right.warehouseType.toLowerCase());
          case 'status':
            return (left.isActive ? 1 : 0).compareTo(right.isActive ? 1 : 0);
          default:
            return left.name.toLowerCase().compareTo(right.name.toLowerCase());
        }
      },
    );
    return executor.execute(warehouses, _queryController.state);
  }

  Future<void> _openEditor([WarehouseModel? warehouse]) async {
    final permission = warehouse == null
        ? 'warehouses.create'
        : 'warehouses.update';
    if (!await PermissionAction.require(context, permission)) return;
    if (!mounted) return;

    final result = await showAppWorkspaceDialogBuilder<WarehouseModel>(
      context: context,
      builder: (_) => _WarehouseEditor(warehouse: warehouse),
    );
    if (result == null || !mounted) return;
    try {
      final controller = context.read<InventoryController>();
      if (warehouse == null) {
        await controller.createWarehouse(result);
      } else {
        await controller.updateWarehouse(result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            warehouse == null ? 'تمت إضافة المخزن' : 'تم تحديث المخزن',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حفظ المخزن.',
              englishFallback: 'Unable to save the warehouse.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _delete(WarehouseModel warehouse) async {
    if (!await PermissionAction.require(context, 'warehouses.delete')) return;
    if (!mounted) return;
    final accepted = await showAppConfirmDialog(
      context,
      title: 'حذف المخزن',
      message:
          'سيُرفض الحذف إذا كان المخزن مرتبطًا بسيارات أو أرصدة أو حركات. هل تريد حذف ${warehouse.name}؟',
      confirmLabel: 'حذف المخزن',
      destructive: true,
    );
    if (accepted != true || !mounted) return;
    try {
      await context.read<InventoryController>().deleteWarehouse(warehouse.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حذف المخزن.',
              englishFallback: 'Unable to delete the warehouse.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InventoryController>();
    final visible = _visible(controller.allWarehouses);
    final canCreate = PermissionAction.allowed(context, 'warehouses.create');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const AppText(
                'إدارة المخازن',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              AppText(
                context.l10n.isArabic
                    ? '${controller.allWarehouses.length} مخزن'
                    : '${controller.allWarehouses.length} warehouses',
                style: const TextStyle(color: Colors.grey),
              ),
              if (canCreate)
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: AppText(
                    context.l10n.isArabic ? 'إضافة مخزن' : 'Add warehouse',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          KajQueryToolbar(
            controller: _queryController,
            hintText: 'البحث بالرمز أو الاسم أو الفرع أو العنوان',
            filterBuilder: (_) => Wrap(
              spacing: 6,
              children: [
                PopupMenuButton<String>(
                  tooltip: AppTranslation.translate('الحالة'),
                  icon: const Icon(Icons.toggle_on_outlined),
                  onSelected: (value) {
                    if (value == 'all') {
                      _queryController.removeFilterKey('status');
                    } else {
                      _queryController.addFilter(
                        UnifiedFilterToken(
                          key: 'status',
                          label: 'الحالة',
                          value: value,
                          valueLabel: value == 'active' ? 'فعال' : 'غير فعال',
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'all',
                      child: AppText('كل الحالات'),
                    ),
                    PopupMenuItem(
                      value: 'active',
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 18),
                          const SizedBox(width: 8),
                          AppText(
                            context.l10n.isArabic ? 'فعال' : 'Active',
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'inactive',
                      child: Row(
                        children: [
                          const Icon(Icons.pause_circle_outline, size: 18),
                          const SizedBox(width: 8),
                          AppText(
                            context.l10n.isArabic ? 'غير فعال' : 'Inactive',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: AppTranslation.translate('نوع المخزن'),
                  icon: const Icon(Icons.category_outlined),
                  onSelected: (value) {
                    if (value == 'all') {
                      _queryController.removeFilterKey('type');
                    } else {
                      _queryController.addFilter(
                        UnifiedFilterToken(
                          key: 'type',
                          label: 'نوع المخزن',
                          value: value,
                          valueLabel: value == 'scrap_consumption'
                              ? 'توالف واستهلاك'
                              : 'اعتيادي',
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'all',
                      child: AppText('كل الأنواع'),
                    ),
                    PopupMenuItem(
                      value: 'normal',
                      child: AppText('اعتيادي'),
                    ),
                    PopupMenuItem(
                      value: 'scrap_consumption',
                      child: AppText('توالف واستهلاك'),
                    ),
                  ],
                ),
              ],
            ),
            sortBuilder: (_) => PopupMenuButton<String>(
              tooltip: AppTranslation.translate('إضافة فرز'),
              icon: const Icon(Icons.sort_rounded),
              onSelected: (field) {
                final rule = switch (field) {
                  'code' => const UnifiedSortRule(
                    field: 'code',
                    label: 'رمز المخزن',
                  ),
                  'type' => const UnifiedSortRule(
                    field: 'type',
                    label: 'نوع المخزن',
                  ),
                  'status' => const UnifiedSortRule(
                    field: 'status',
                    label: 'الحالة',
                    descending: true,
                  ),
                  _ => const UnifiedSortRule(
                    field: 'name',
                    label: 'الاسم',
                  ),
                };
                _queryController.addSort(rule);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'name', child: AppText('الاسم')),
                PopupMenuItem(value: 'code', child: AppText('رمز المخزن')),
                PopupMenuItem(value: 'type', child: AppText('نوع المخزن')),
                PopupMenuItem(value: 'status', child: AppText('الحالة')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: controller.isLoading && controller.allWarehouses.isEmpty
                ? const KajInventoryLoadingState()
                : visible.isEmpty
                ? Center(
                    child: AppText(
                      context.l10n.isArabic
                          ? 'لا توجد مخازن مطابقة لشروط البحث والتصفية.'
                          : 'No warehouses match the current query.',
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final count = constraints.maxWidth >= 1180
                          ? 3
                          : constraints.maxWidth >= 720
                          ? 2
                          : 1;
                      return GridView.builder(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: count,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              mainAxisExtent: 124,
                            ),
                        itemCount: visible.length,
                        itemBuilder: (_, index) => _WarehouseCard(
                          warehouse: visible[index],
                          onEdit: () => _openEditor(visible[index]),
                          onDelete: () => _delete(visible[index]),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({
    required this.warehouse,
    required this.onEdit,
    required this.onDelete,
  });

  final WarehouseModel warehouse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  radius: 16,
                  child: const Icon(Icons.warehouse_rounded, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppText(
                    warehouse.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: warehouse.isActive
                        ? Colors.green.withValues(alpha: .13)
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AppText(
                    warehouse.isActive
                        ? (context.l10n.isArabic ? 'فعال' : 'Active')
                        : (context.l10n.isArabic ? 'غير فعال' : 'Inactive'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: warehouse.isActive
                          ? Colors.green.shade800
                          : scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 8),
            _line(
              context.l10n.isArabic ? 'رمز المخزن' : 'Warehouse code',
              warehouse.code,
            ),
            _line(
              context.l10n.isArabic ? 'العنوان' : 'Address',
              warehouse.address,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: AppText(context.l10n.isArabic ? 'تعديل' : 'Edit'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onDelete,
                  color: scheme.error,
                  tooltip: AppTranslation.translate('حذف'),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: AppText(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        Expanded(
          child: AppSelectableText(
            value.trim().isEmpty ? '—' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _WarehouseEditor extends StatefulWidget {
  const _WarehouseEditor({this.warehouse});

  final WarehouseModel? warehouse;

  @override
  State<_WarehouseEditor> createState() => _WarehouseEditorState();
}

class _WarehouseEditorState extends State<_WarehouseEditor> {
  final _formKey = GlobalKey<FormState>();

  String get _writePermission =>
      widget.warehouse == null ? 'warehouses.create' : 'warehouses.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'warehouses',
    field: field,
    viewPermission: 'warehouses.view',
    writePermission: _writePermission,
    child: child,
  );

  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _branch;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  late bool _active;
  late String _warehouseType;
  String? _scrapExpenseIqdAccountId;
  String? _scrapExpenseUsdAccountId;

  @override
  void initState() {
    super.initState();
    final value = widget.warehouse;
    _code = TextEditingController(text: value?.code ?? '');
    _name = TextEditingController(text: value?.name ?? '');
    _branch = TextEditingController(text: value?.branchId ?? '');
    _address = TextEditingController(text: value?.address ?? '');
    _notes = TextEditingController(text: value?.notes ?? '');
    _active = value?.isActive ?? true;
    _warehouseType = value?.warehouseType ?? 'normal';
    _scrapExpenseIqdAccountId = value?.scrapExpenseIqdAccountId;
    _scrapExpenseUsdAccountId = value?.scrapExpenseUsdAccountId;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _branch.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: AppText(widget.warehouse == null ? 'إضافة مخزن' : 'تعديل المخزن'),
    content: SizedBox(
      width: AppResponsive.dialogWidth(context, 560),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _field(_name, 'اسم المخزن', field: 'name', isRequired: true),
              _field(_code, 'رمز المخزن', field: 'code', isRequired: true),
              _field(_branch, 'الفرع', field: 'branchId'),
              _field(_address, 'عنوان المخزن', field: 'address'),
              _securedField(
                'warehouseType',
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _warehouseType,
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('نوع المخزن'),
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'normal',
                      child: AppText('مخزن اعتيادي'),
                    ),
                    DropdownMenuItem(
                      value: 'scrap_consumption',
                      child: AppText('مخزن توالف واستهلاك'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _warehouseType = value ?? 'normal'),
                ),
              ),
              const SizedBox(height: 12),
              if (_warehouseType == 'scrap_consumption') ...[
                Builder(
                  builder: (context) {
                    final accounts = context
                        .watch<AccountingController>()
                        .accounts;
                    final expenseAccounts = accounts
                        .where((a) => a.type == 'expense' && a.isActive)
                        .toList();
                    final iqdExpenseAccounts = expenseAccounts
                        .where((a) => a.currency.toUpperCase() == 'IQD')
                        .toList();
                    final usdExpenseAccounts = expenseAccounts
                        .where((a) => a.currency.toUpperCase() == 'USD')
                        .toList();
                    String? safeValue(
                      String? value,
                      List<AccountModel> items,
                    ) => items.any((a) => a.id == value) ? value : null;
                    return Column(
                      children: [
                        const AppText(
                          'حساب المادة التالفة يُحدد آليًا من حساب تقييم المادة أو السيارة في بطاقة التعريف.',
                        ),
                        const SizedBox(height: 12),
                        _securedField(
                          'scrapExpenseIqdAccountId',
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: safeValue(
                              _scrapExpenseIqdAccountId,
                              iqdExpenseAccounts,
                            ),
                            decoration: InputDecoration(
                              labelText: AppTranslation.translate(
                                'حساب تكاليف التوالف بالدينار العراقي',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            items: iqdExpenseAccounts
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a.id,
                                    child: AppText('${a.code} — ${a.name}'),
                                  ),
                                )
                                .toList(),
                            validator: (v) => v == null
                                ? AppTranslation.translate(
                                    'اختر حساب تكاليف التوالف بالدينار',
                                  )
                                : null,
                            onChanged: (v) =>
                                setState(() => _scrapExpenseIqdAccountId = v),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _securedField(
                          'scrapExpenseUsdAccountId',
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: safeValue(
                              _scrapExpenseUsdAccountId,
                              usdExpenseAccounts,
                            ),
                            decoration: InputDecoration(
                              labelText: AppTranslation.translate(
                                'حساب تكاليف التوالف بالدولار',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            items: usdExpenseAccounts
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a.id,
                                    child: AppText('${a.code} — ${a.name}'),
                                  ),
                                )
                                .toList(),
                            validator: (v) => v == null
                                ? AppTranslation.translate(
                                    'اختر حساب تكاليف التوالف بالدولار',
                                  )
                                : null,
                            onChanged: (v) =>
                                setState(() => _scrapExpenseUsdAccountId = v),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    );
                  },
                ),
              ],
              _field(_notes, 'ملاحظات', field: 'notes', lines: 3),
              _securedField(
                'isActive',
                SwitchListTile(
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const AppText('المخزن فعال'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const AppText('إلغاء'),
      ),
      FilledButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: const AppText('حفظ'),
      ),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    required String field,
    bool isRequired = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _securedField(
      field,
      TextFormField(
        controller: controller,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: AppTranslation.translate(label),
          border: const OutlineInputBorder(),
        ),
        validator: isRequired
            ? (value) => value == null || value.trim().isEmpty
                  ? AppTranslation.translate('$label مطلوب')
                  : null
            : null,
      ),
    ),
  );

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final old = widget.warehouse;
    Navigator.pop(
      context,
      WarehouseModel(
        id: old?.id ?? const Uuid().v4(),
        code: _code.text.trim(),
        name: _name.text.trim(),
        branchId: _branch.text.trim().isEmpty ? null : _branch.text.trim(),
        address: _address.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isActive: _active,
        warehouseType: _warehouseType,
        inventoryAccountId: old?.inventoryAccountId,
        scrapExpenseAccountId: _warehouseType == 'scrap_consumption'
            ? (_scrapExpenseIqdAccountId ?? _scrapExpenseUsdAccountId)
            : null,
        scrapExpenseIqdAccountId: _warehouseType == 'scrap_consumption'
            ? _scrapExpenseIqdAccountId
            : null,
        scrapExpenseUsdAccountId: _warehouseType == 'scrap_consumption'
            ? _scrapExpenseUsdAccountId
            : null,
      ),
    );
  }
}
