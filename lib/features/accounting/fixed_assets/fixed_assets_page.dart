import 'dart:async';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/utils/business_date_codec.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/fixed_assets/data/fixed_assets_repository.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class FixedAssetsPage extends StatefulWidget {
  const FixedAssetsPage({super.key});

  @override
  State<FixedAssetsPage> createState() => _FixedAssetsPageState();
}

class _FixedAssetsPageState extends State<FixedAssetsPage> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _busyAssetId;
  final FixedAssetsRepository _repository = FixedAssetsRepository();

  String _assetMoney(num value, Object? rawCurrency) {
    final currency = rawCurrency?.toString().trim().toUpperCase() ?? '';
    return currency.isEmpty
        ? MoneyFormatter.format(value)
        : MoneyFormatter.withCurrency(value, currency);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final rows = await _repository.listAssets();
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(
          rows.map((e) => Map<String, dynamic>.from(e)),
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(userFacingError(e, isArabic: context.l10n.isArabic)),
        ),
      );
    }
  }

  Future<void> _edit([Map<String, dynamic>? asset]) async {
    final changed = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (_) => _FixedAssetDialog(asset: asset),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> asset) async {
    if (!await PermissionAction.require(context, 'accounting.delete')) return;
    if (!mounted) return;
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          context.l10n.isArabic
              ? 'حذف الأصل الثابت مع ارتباطاته'
              : 'Delete fixed asset and links',
        ),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                context.l10n.isArabic
                    ? 'سيتم حذف الأصل من القائمة مع سجلات الإهلاك وجميع القيود المرتبطة مباشرة بالأصل. القيود المستقلة غير المرتبطة بالأصل لا تُحذف.'
                    : 'The asset will be removed with its depreciation entries and every journal linked directly to it. Unrelated independent journals are not deleted.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.isArabic
                      ? 'سبب الحذف'
                      : 'Deletion reason',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(context.l10n.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: AppText(
              context.l10n.isArabic
                  ? 'حذف وعكس الارتباطات'
                  : 'Delete and reverse',
            ),
          ),
        ],
      ),
    );
    final deletionReason = reason.text.trim();
    reason.dispose();
    if (accepted != true || !mounted) return;
    if (deletionReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'سبب الحذف مطلوب.'
                : 'Deletion reason is required.',
          ),
        ),
      );
      return;
    }
    final id = asset['id']?.toString() ?? '';
    setState(() => _busyAssetId = id);
    try {
      await _repository.deleteAsset(assetId: id, reason: deletionReason);
      if (!mounted) return;
      await context.read<AccountingController>().loadAccounting();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'تم حذف الأصل وعكس ارتباطاته.'
                : 'The asset and linked records were deleted.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(userFacingError(e, isArabic: context.l10n.isArabic)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAssetId = null);
    }
  }

  Future<DateTime?> _pickDepreciationDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (!mounted) return null;
    final selected = time ?? TimeOfDay.fromDateTime(now);
    return DateTime(
      date.year,
      date.month,
      date.day,
      selected.hour,
      selected.minute,
    );
  }

  Future<void> _depreciate(Map<String, dynamic> asset) async {
    if (!await PermissionAction.require(context, 'accounting.post')) return;
    if (!mounted) return;
    final access = context.read<AccessController>();
    if (!access.canEditField(
      'fixed_assets',
      'depreciationPostingDate',
      viewPermission: 'accounting.view',
      writePermission: 'accounting.post',
    )) {
      await access.recordDeniedAccess(
        'fixed_assets.fields.depreciationPostingDate.edit',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('ليس لديك صلاحية لترحيل إهلاك الأصل.')),
      );
      return;
    }
    final effectiveAt = await _pickDepreciationDateTime();
    if (effectiveAt == null || !mounted) return;
    try {
      await _repository.postDepreciation(
        assetId: asset['id']?.toString() ?? '',
        effectiveAt: effectiveAt,
      );
      if (!mounted) return;
      await context.read<AccountingController>().loadAccounting();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('تم توليد قيد الإهلاك بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(userFacingError(e, isArabic: context.l10n.isArabic)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return KajFinanceState(
        icon: Icons.sync_rounded,
        title: context.l10n.isArabic ? 'جارٍ تحميل الأصول' : 'Loading assets',
        message: context.l10n.isArabic
            ? 'تتم مزامنة الأصول والإهلاك والقيود المرتبطة.'
            : 'Synchronizing assets, depreciation and linked journals.',
      );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: AppText(
                  'الأصول الثابتة وغير المتداولة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const AppText('إضافة أصل'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? const Center(child: AppText('لا توجد أصول ثابتة مسجلة.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final a = _items[i];
                    final cost =
                        (a['acquisition_cost'] as num?)?.toDouble() ?? 0;
                    final accumulated =
                        (a['accumulated_depreciation'] as num?)?.toDouble() ??
                        0;
                    final salvage =
                        (a['salvage_value'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.apartment_outlined),
                      ),
                      title: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          FieldPermissionVisibility(
                            resource: 'fixed_assets',
                            field: 'assetCode',
                            viewPermission: 'accounting.view',
                            child: AppText(a['asset_code']?.toString() ?? ''),
                          ),
                          FieldPermissionVisibility(
                            resource: 'fixed_assets',
                            field: 'name',
                            viewPermission: 'accounting.view',
                            child: AppText(a['name']?.toString() ?? ''),
                          ),
                        ],
                      ),
                      subtitle: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          FieldPermissionVisibility(
                            resource: 'fixed_assets',
                            field: 'acquisitionCost',
                            viewPermission: 'accounting.view',
                            child: AppText(
                              'الكلفة: ${_assetMoney(cost, a['currency'])}',
                            ),
                          ),
                          FieldPermissionVisibility(
                            resource: 'fixed_assets',
                            field: 'accumulatedDepreciation',
                            viewPermission: 'accounting.view',
                            child: AppText(
                              'مجمع الإهلاك: ${_assetMoney(accumulated, a['currency'])}',
                            ),
                          ),
                          FieldPermissionVisibility(
                            resource: 'fixed_assets',
                            field: 'bookValue',
                            viewPermission: 'accounting.view',
                            child: AppText(
                              'القيمة الدفترية: ${_assetMoney((cost - accumulated).clamp(salvage, cost).toDouble(), a['currency'])}',
                            ),
                          ),
                          if ((a['last_depreciation_date'] ?? '')
                              .toString()
                              .isNotEmpty)
                            FieldPermissionVisibility(
                              resource: 'fixed_assets',
                              field: 'depreciationPostingDate',
                              viewPermission: 'accounting.view',
                              child: AppText(
                                'آخر إهلاك: ${a['last_depreciation_date']}',
                              ),
                            ),
                        ],
                      ),
                      onTap: _busyAssetId == a['id']?.toString()
                          ? null
                          : () => _edit(a),
                      trailing: _busyAssetId == a['id']?.toString()
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'depreciate') {
                                  unawaited(_depreciate(a));
                                } else if (value == 'edit') {
                                  unawaited(_edit(a));
                                } else if (value == 'delete') {
                                  unawaited(_delete(a));
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'depreciate',
                                  child: AppText('توليد الإهلاك'),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: AppText('تعديل الأصل'),
                                ),
                                if (PermissionAction.allowed(
                                  context,
                                  'accounting.delete',
                                ))
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: AppText('حذف الأصل وارتباطاته'),
                                  ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FixedAssetDialog extends StatefulWidget {
  const _FixedAssetDialog({this.asset});
  final Map<String, dynamic>? asset;

  @override
  State<_FixedAssetDialog> createState() => _FixedAssetDialogState();
}

class _FixedAssetDialogState extends State<_FixedAssetDialog> {
  final FixedAssetsRepository _repository = FixedAssetsRepository();

  String get _writePermission =>
      widget.asset == null ? 'accounting.create' : 'accounting.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'fixed_assets',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: _writePermission,
    child: child,
  );

  final _key = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late final TextEditingController _cost;
  late final TextEditingController _salvage;
  late final TextEditingController _life;
  late final TextEditingController _rate;
  late final TextEditingController _notes;
  String _currency = 'USD';
  String _method = 'straight_line';
  String? _assetAccount;
  String? _accumulatedAccount;
  String? _expenseAccount;
  DateTime? _acquisitionDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _code = TextEditingController(
      text:
          a?['asset_code']?.toString() ??
          'FA-${DateTime.now().millisecondsSinceEpoch}',
    );
    _name = TextEditingController(text: a?['name']?.toString() ?? '');
    _cost = TextEditingController(text: '${a?['acquisition_cost'] ?? 0}');
    _salvage = TextEditingController(text: '${a?['salvage_value'] ?? 0}');
    _life = TextEditingController(text: '${a?['useful_life_months'] ?? 60}');
    _rate = TextEditingController(text: '${a?['declining_rate'] ?? ''}');
    _notes = TextEditingController(text: a?['notes']?.toString() ?? '');
    _currency = SupportedCurrency.initial(
      isNew: a == null,
      stored: a?['currency'],
    );
    _method = a?['depreciation_method']?.toString() ?? 'straight_line';
    _assetAccount = a?['asset_account_id']?.toString();
    _accumulatedAccount = a?['accumulated_depreciation_account_id']?.toString();
    _expenseAccount = a?['depreciation_expense_account_id']?.toString();
    _acquisitionDate = a == null
        ? DateTime.now()
        : DateTime.tryParse(a['acquisition_date']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _cost, _salvage, _life, _rate, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_key.currentState?.validate() ?? false)) return;
    if (_acquisitionDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(AppTranslation.translate('تاريخ الاقتناء مطلوب')),
        ),
      );
      return;
    }
    if (_assetAccount == null ||
        _accumulatedAccount == null ||
        _expenseAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('اختر حساب الأصل ومجمع الإهلاك ومصروف الإهلاك.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _repository.saveAsset({
        'id': widget.asset?['id'] ?? const Uuid().v4(),
        'assetCode': _code.text.trim(),
        'name': _name.text.trim(),
        'acquisitionDate': BusinessDateCodec.encode(_acquisitionDate!),
        'acquisitionCost': double.tryParse(_cost.text.replaceAll(',', '')) ?? 0,
        'salvageValue': double.tryParse(_salvage.text.replaceAll(',', '')) ?? 0,
        'usefulLifeMonths': int.tryParse(_life.text.replaceAll(',', '')) ?? 60,
        'depreciationMethod': _method,
        'decliningRate': _rate.text.trim(),
        'currency': _currency,
        'assetAccountId': _assetAccount,
        'accumulatedDepreciationAccountId': _accumulatedAccount,
        'depreciationExpenseAccountId': _expenseAccount,
        'isActive': true,
        'notes': _notes.text.trim(),
      });
      if (mounted) AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              userFacingError(e, isArabic: context.l10n.isArabic),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAcquisitionDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _acquisitionDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() {
      // acquisition_date is a PostgreSQL DATE. Keep it date-only so the
      // browser timezone can never shift the business day.
      _acquisitionDate = DateTime(date.year, date.month, date.day);
    });
  }

  Widget _responsiveFieldGroup({
    required List<Widget> children,
    required int columns,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = children
            .where((child) {
              return !(child is SizedBox && child.width == 10);
            })
            .toList(growable: false);
        final effectiveColumns = constraints.maxWidth < 620 ? 1 : columns;
        final width = effectiveColumns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - (effectiveColumns - 1) * 10) /
                  effectiveColumns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: visible
              .map((child) {
                final content = child is Expanded ? child.child : child;
                return SizedBox(width: width, child: content);
              })
              .toList(growable: false),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountingController>().accounts;
    List<AccountModel> byType(String type) => accounts
        .where(
          (a) =>
              a.type == type &&
              (a.currency == _currency || a.currency == 'MULTI'),
        )
        .toList();
    Widget accountField(
      String field,
      String label,
      String? value,
      List<AccountModel> items,
      ValueChanged<String?> changed,
    ) => _securedField(
      field,
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: items.any((a) => a.id == value) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map(
              (a) => DropdownMenuItem(
                value: a.id,
                child: AppText('${a.code} — ${a.name}'),
              ),
            )
            .toList(),
        onChanged: changed,
      ),
    );
    return AlertDialog(
      title: AppText(
        widget.asset == null ? 'إضافة أصل ثابت' : 'تعديل الأصل الثابت',
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, 720),
        child: Form(
          key: _key,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _responsiveFieldGroup(
                  columns: 2,
                  children: [
                    Expanded(
                      child: _securedField(
                        'assetCode',
                        TextFormField(
                          controller: _code,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('رمز الأصل'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? AppTranslation.translate('مطلوب')
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _securedField(
                        'name',
                        TextFormField(
                          controller: _name,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('اسم الأصل'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? AppTranslation.translate('مطلوب')
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _responsiveFieldGroup(
                  columns: 3,
                  children: [
                    Expanded(
                      child: _securedField(
                        'acquisitionCost',
                        TextFormField(
                          controller: _cost,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'كلفة الاقتناء',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,

                          inputFormatters: <TextInputFormatter>[
                            ThousandsInputFormatter(decimalDigits: 2),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _securedField(
                        'salvageValue',
                        TextFormField(
                          controller: _salvage,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('قيمة الخردة'),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,

                          inputFormatters: <TextInputFormatter>[
                            ThousandsInputFormatter(decimalDigits: 2),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _securedField(
                        'usefulLifeMonths',
                        TextFormField(
                          controller: _life,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'العمر بالأشهر',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,

                          inputFormatters: <TextInputFormatter>[
                            ThousandsInputFormatter(decimalDigits: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _responsiveFieldGroup(
                  columns: 3,
                  children: [
                    Expanded(
                      child: _securedField(
                        'currency',
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: SupportedCurrency.normalize(_currency),
                          validator: (value) =>
                              SupportedCurrency.isSupported(value)
                              ? null
                              : AppTranslation.translate('العملة مطلوبة'),
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('العملة'),
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'USD',
                              child: AppText('USD'),
                            ),
                            DropdownMenuItem(
                              value: 'IQD',
                              child: AppText('IQD'),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            final code = SupportedCurrency.normalize(v);
                            if (code == null) return;
                            _currency = code;
                            _assetAccount = null;
                            _accumulatedAccount = null;
                            _expenseAccount = null;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _securedField(
                        'depreciationMethod',
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _method,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'طريقة الإهلاك',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'straight_line',
                              child: AppText('القسط الثابت'),
                            ),
                            DropdownMenuItem(
                              value: 'declining_balance',
                              child: AppText('القسط المتناقص'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _method = v ?? 'straight_line'),
                        ),
                      ),
                    ),
                    if (_method == 'declining_balance') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _securedField(
                          'decliningRate',
                          TextFormField(
                            controller: _rate,
                            decoration: InputDecoration(
                              labelText: AppTranslation.translate(
                                'المعدل الشهري (مثال 0.03)',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,

                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _securedField(
                  'operationalDate',
                  ListTile(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    leading: const Icon(Icons.event_outlined),
                    title: const AppText('تاريخ الاقتناء'),
                    subtitle: AppText(
                      _acquisitionDate == null
                          ? AppTranslation.translate('اختر تاريخ الاقتناء')
                          : '${_acquisitionDate!.year}-${_acquisitionDate!.month.toString().padLeft(2, '0')}-${_acquisitionDate!.day.toString().padLeft(2, '0')}',
                    ),
                    onTap: _pickAcquisitionDate,
                  ),
                ),
                const SizedBox(height: 10),
                accountField(
                  'assetAccount',
                  'حساب الأصل غير المتداول',
                  _assetAccount,
                  byType('asset'),
                  (v) => setState(() => _assetAccount = v),
                ),
                const SizedBox(height: 10),
                accountField(
                  'accumulatedDepreciationAccount',
                  'حساب مجمع الإهلاك (دائن)',
                  _accumulatedAccount,
                  byType('asset'),
                  (v) => setState(() => _accumulatedAccount = v),
                ),
                const SizedBox(height: 10),
                accountField(
                  'depreciationExpenseAccount',
                  'حساب مصروف الإهلاك (مدين)',
                  _expenseAccount,
                  byType('expense'),
                  (v) => setState(() => _expenseAccount = v),
                ),
                const SizedBox(height: 10),
                _securedField(
                  'notes',
                  TextFormField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('ملاحظات'),
                      border: const OutlineInputBorder(),
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
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const AppText('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: AppText(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}
