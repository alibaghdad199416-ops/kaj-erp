import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_components.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class WarehouseManagementPage extends StatefulWidget {
  const WarehouseManagementPage({super.key});

  @override
  State<WarehouseManagementPage> createState() =>
      _WarehouseManagementPageState();
}

class _WarehouseManagementPageState extends State<WarehouseManagementPage> {
  final _search = TextEditingController();
  bool _showInactive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<InventoryController>().loadInventory();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor([WarehouseModel? warehouse]) async {
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
    final query = _search.text.trim().toLowerCase();
    final rows = controller.allWarehouses
        .where((warehouse) {
          if (!_showInactive && !warehouse.isActive) return false;
          if (query.isEmpty) return true;
          return <String?>[
            warehouse.id,
            warehouse.code,
            warehouse.name,
            warehouse.branchId,
            warehouse.address,
            warehouse.notes,
          ].any((value) => value?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          KajInventoryActionBar(
            title: context.l10n.isArabic
                ? 'إدارة المخازن'
                : 'Warehouse management',
            subtitle: context.l10n.isArabic
                ? 'إدارة مواقع التخزين والفروع وحالة كل مخزن ضمن مساحة موحدة.'
                : 'Manage storage locations, branches and warehouse availability in one workspace.',
            icon: Icons.warehouse_rounded,
            actions: <Widget>[
              FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_business_rounded),
                label: AppText(
                  context.l10n.isArabic ? 'إضافة مخزن' : 'Add warehouse',
                ),
              ),
            ],
            metrics: <Widget>[
              KajInventoryMetricPill(
                label: context.l10n.isArabic
                    ? 'إجمالي المخازن'
                    : 'Total warehouses',
                value: '${controller.allWarehouses.length}',
                icon: Icons.warehouse_outlined,
              ),
              KajInventoryMetricPill(
                label: context.l10n.isArabic ? 'الفعالة' : 'Active',
                value:
                    '${controller.allWarehouses.where((item) => item.isActive).length}',
                icon: Icons.verified_outlined,
                accent: const Color(0xFF16A36A),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate(
                    'بحث في جميع بيانات المخازن',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              );
              final inactive = FilterChip(
                selected: _showInactive,
                onSelected: (value) => setState(() => _showInactive = value),
                avatar: const Icon(Icons.visibility_outlined, size: 18),
                label: AppText(
                  context.l10n.isArabic ? 'إظهار غير الفعال' : 'Show inactive',
                ),
              );
              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: inactive,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  inactive,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: controller.isLoading && controller.allWarehouses.isEmpty
                ? const KajInventoryLoadingState()
                : rows.isEmpty
                ? Center(
                    child: AppText(
                      context.l10n.isArabic
                          ? 'لا توجد مخازن مطابقة'
                          : 'No matching warehouses',
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
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          mainAxisExtent: 124,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (_, index) => _WarehouseCard(
                          warehouse: rows[index],
                          onEdit: () => _openEditor(rows[index]),
                          onDelete: () => _delete(rows[index]),
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
                    icon: const Icon(Icons.edit_outlined),
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
        inventoryAccountId: null,
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
