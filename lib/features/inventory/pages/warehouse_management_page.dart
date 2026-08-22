import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/controllers/settings_controller.dart';
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
      await Future.wait<void>([
        context.read<InventoryController>().loadInventory(),
        context.read<SettingsController>().ensureBranchesLoaded(),
        context.read<AccountingController>().ensureAccountsLoaded(),
      ]);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor([WarehouseModel? warehouse]) async {
    final permission = warehouse == null
        ? 'warehouses.create'
        : 'warehouses.update';
    if (!await PermissionAction.require(context, permission)) return;
    if (!mounted) return;
    final result = await showAppWorkspaceDialogBuilder<WarehouseModel>(
      context: context,
      builder: (_) => WarehouseEditor(warehouse: warehouse),
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
    final activeCount = controller.allWarehouses
        .where((item) => item.isActive)
        .length;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  hintText: AppTranslation.translate(
                    'بحث في جميع بيانات المخازن',
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 38,
                    minHeight: 36,
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              );
              final inactive = FilterChip(
                selected: _showInactive,
                onSelected: (value) => setState(() => _showInactive = value),
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.visibility_outlined, size: 16),
                label: AppText(
                  context.l10n.isArabic ? 'إظهار غير الفعال' : 'Show inactive',
                  style: const TextStyle(fontSize: 11),
                ),
              );
              final totalMetric = _WarehouseMetricChip(
                label: context.l10n.isArabic ? 'المخازن' : 'Warehouses',
                value: '${controller.allWarehouses.length}',
                icon: Icons.warehouse_outlined,
              );
              final activeMetric = _WarehouseMetricChip(
                label: context.l10n.isArabic ? 'الفعالة' : 'Active',
                value: '$activeCount',
                icon: Icons.verified_outlined,
                tone: const Color(0xFF16A36A),
              );
              final addButton = FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_business_rounded, size: 16),
                label: AppText(
                  context.l10n.isArabic ? 'إضافة مخزن' : 'Add warehouse',
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              );

              if (constraints.maxWidth >= 980) {
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    inactive,
                    const SizedBox(width: 7),
                    totalMetric,
                    const SizedBox(width: 7),
                    activeMetric,
                    const SizedBox(width: 8),
                    addButton,
                  ],
                );
              }

              if (constraints.maxWidth >= 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 8),
                        addButton,
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [inactive, totalMetric, activeMetric],
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  search,
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [inactive, totalMetric, activeMetric, addButton],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
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
                      const gap = 10.0;
                      const minimumCardWidth = 285.0;
                      final count =
                          ((constraints.maxWidth + gap) /
                                  (minimumCardWidth + gap))
                              .floor()
                              .clamp(1, 4)
                              .toInt();
                      return GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: count,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
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
      margin: EdgeInsets.zero,
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
                  radius: 14,
                  child: const Icon(Icons.warehouse_rounded, size: 15),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    warehouse.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: warehouse.isActive
                        ? Colors.green.withValues(alpha: .12)
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AppText(
                    warehouse.isActive
                        ? (context.l10n.isArabic ? 'فعال' : 'Active')
                        : (context.l10n.isArabic ? 'غير فعال' : 'Inactive'),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: warehouse.isActive
                          ? Colors.green.shade800
                          : scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _WarehouseDetail(
                    label: context.l10n.isArabic ? 'الرمز' : 'Code',
                    value: warehouse.code,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _WarehouseDetail(
                    label: context.l10n.isArabic ? 'العنوان' : 'Address',
                    value: warehouse.address,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: AppText(
                      context.l10n.isArabic ? 'تعديل' : 'Edit',
                      style: const TextStyle(fontSize: 10.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onDelete,
                    color: scheme.error,
                    tooltip: AppTranslation.translate('حذف'),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 17,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseDetail extends StatelessWidget {
  const _WarehouseDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      AppText(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
      const SizedBox(height: 1),
      AppText(
        value.trim().isEmpty ? '—' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _WarehouseMetricChip extends StatelessWidget {
  const _WarehouseMetricChip({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          AppText(
            '$label: $value',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class WarehouseEditor extends StatefulWidget {
  const WarehouseEditor({super.key, this.warehouse});

  final WarehouseModel? warehouse;

  @override
  State<WarehouseEditor> createState() => _WarehouseEditorState();
}

class _WarehouseEditorState extends State<WarehouseEditor> {
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
  String? _branchId;
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
    _branchId = value?.branchId;
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
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: AppText(
      context.l10n.isArabic
          ? (widget.warehouse == null ? 'إضافة مخزن' : 'تعديل المخزن')
          : (widget.warehouse == null ? 'Add warehouse' : 'Edit warehouse'),
    ),
    content: SizedBox(
      width: AppResponsive.dialogWidth(context, 560),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _field(_name, 'اسم المخزن', field: 'name', isRequired: true),
              _field(_code, 'رمز المخزن', field: 'code', isRequired: true),
              _securedField(
                'branchId',
                Builder(
                  builder: (context) {
                    final branches = context
                        .watch<SettingsController>()
                        .branches
                        .where(
                          (branch) => branch.isActive || branch.id == _branchId,
                        )
                        .toList(growable: false);
                    final safeBranchId =
                        branches.any((branch) => branch.id == _branchId)
                        ? _branchId
                        : null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: safeBranchId,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('الفرع'),
                          border: const OutlineInputBorder(),
                        ),
                        items: <DropdownMenuItem<String?>>[
                          DropdownMenuItem<String?>(
                            value: null,
                            child: AppText(
                              context.l10n.isArabic
                                  ? 'بدون فرع محدد'
                                  : 'No specific branch',
                            ),
                          ),
                          ...branches.map(
                            (branch) => DropdownMenuItem<String?>(
                              value: branch.id,
                              child: AppText(
                                '${branch.code} — ${branch.name}${branch.isActive ? '' : (context.l10n.isArabic ? ' (غير فعال)' : ' (Inactive)')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() => _branchId = value),
                      ),
                    );
                  },
                ),
              ),
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
                        .postableAccounts;
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
                  title: AppText(
                    context.l10n.isArabic ? 'المخزن فعال' : 'Warehouse active',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => AppWorkspaceWindowScope.closeCurrent(context),
        child: AppText(context.l10n.isArabic ? 'إلغاء' : 'Cancel'),
      ),
      FilledButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_outlined),
        label: AppText(context.l10n.isArabic ? 'حفظ' : 'Save'),
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
    AppWorkspaceWindowScope.closeCurrent(
      context,
      WarehouseModel(
        id: old?.id ?? const Uuid().v4(),
        code: _code.text.trim(),
        name: _name.text.trim(),
        branchId: _branchId,
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
