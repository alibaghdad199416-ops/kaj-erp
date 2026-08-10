import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class InventoryAccountFields extends StatefulWidget {
  const InventoryAccountFields({
    super.key,
    required this.currency,
    required this.inventoryAssetAccountId,
    required this.salesCostExpenseAccountId,
    required this.salesRevenueIqdAccountId,
    required this.salesRevenueUsdAccountId,
    required this.onInventoryAssetChanged,
    required this.onSalesCostExpenseChanged,
    required this.onSalesRevenueIqdChanged,
    required this.onSalesRevenueUsdChanged,
    this.permissionResource,
    this.viewPermission,
    this.writePermission,
  });

  final String currency;
  final String? inventoryAssetAccountId;
  final String? salesCostExpenseAccountId;
  final String? salesRevenueIqdAccountId;
  final String? salesRevenueUsdAccountId;
  final ValueChanged<String?> onInventoryAssetChanged;
  final ValueChanged<String?> onSalesCostExpenseChanged;
  final ValueChanged<String?> onSalesRevenueIqdChanged;
  final ValueChanged<String?> onSalesRevenueUsdChanged;
  final String? permissionResource;
  final String? viewPermission;
  final String? writePermission;

  @override
  State<InventoryAccountFields> createState() => _InventoryAccountFieldsState();
}

class _InventoryAccountFieldsState extends State<InventoryAccountFields> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AccountingController>().ensureAccountsLoaded(
        force: force,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر تحميل حسابات المخزون والكلفة.',
          englishFallback: 'Unable to load inventory and cost accounts.',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountingController>().accounts;
    final currency = widget.currency.trim().toUpperCase();
    final assets = accounts
        .where(
          (a) =>
              a.isActive &&
              a.type.toLowerCase() == 'asset' &&
              a.currency.toUpperCase() == currency,
        )
        .toList(growable: false);
    final expenses = accounts
        .where(
          (a) =>
              a.isActive &&
              a.type.toLowerCase() == 'expense' &&
              a.currency.toUpperCase() == currency,
        )
        .toList(growable: false);
    final revenueIqd = accounts
        .where(
          (a) =>
              a.isActive &&
              a.type.toLowerCase() == 'revenue' &&
              a.currency.toUpperCase() == 'IQD',
        )
        .toList(growable: false);
    final revenueUsd = accounts
        .where(
          (a) =>
              a.isActive &&
              a.type.toLowerCase() == 'revenue' &&
              a.currency.toUpperCase() == 'USD',
        )
        .toList(growable: false);

    if (_loading && accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && accounts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(_load(force: true)),
                icon: const Icon(Icons.refresh_rounded),
                label: AppText(
                  context.l10n.isArabic
                      ? 'إعادة تحميل الحسابات'
                      : 'Reload accounts',
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget protect(String field, Widget child) {
      final resource = widget.permissionResource;
      if (resource == null || resource.trim().isEmpty) return child;
      return FieldPermissionControl(
        resource: resource,
        field: field,
        viewPermission: widget.viewPermission,
        writePermission: widget.writePermission,
        child: child,
      );
    }

    return Column(
      children: [
        protect(
          'inventoryAssetAccountId',
          _AccountDropdown(
            label:
                'حساب مخزون الأصل (مدين عند الشراء / دائن عند البيع أو التلف)',
            emptyMessage: 'لا يوجد حساب أصل فعال بعملة $currency',
            value: widget.inventoryAssetAccountId,
            accounts: assets,
            onChanged: widget.onInventoryAssetChanged,
            onReload: () => unawaited(_load(force: true)),
          ),
        ),
        const SizedBox(height: 15),
        protect(
          'salesCostExpenseAccountId',
          _AccountDropdown(
            label: 'حساب الكلفة / تكلفة المبيعات (مصروف مدين عند البيع)',
            emptyMessage: 'لا يوجد حساب مصروف فعال بعملة $currency',
            value: widget.salesCostExpenseAccountId,
            accounts: expenses,
            onChanged: widget.onSalesCostExpenseChanged,
            onReload: () => unawaited(_load(force: true)),
          ),
        ),
        const SizedBox(height: 15),
        protect(
          'salesRevenueIqdAccountId',
          _AccountDropdown(
            label: 'حساب إيراد البيع بالدينار IQD',
            emptyMessage: 'لا يوجد حساب إيراد فعال بعملة IQD',
            value: widget.salesRevenueIqdAccountId,
            accounts: revenueIqd,
            onChanged: widget.onSalesRevenueIqdChanged,
            onReload: () => unawaited(_load(force: true)),
          ),
        ),
        const SizedBox(height: 15),
        protect(
          'salesRevenueUsdAccountId',
          _AccountDropdown(
            label: 'حساب إيراد البيع بالدولار USD',
            emptyMessage: 'لا يوجد حساب إيراد فعال بعملة USD',
            value: widget.salesRevenueUsdAccountId,
            accounts: revenueUsd,
            onChanged: widget.onSalesRevenueUsdChanged,
            onReload: () => unawaited(_load(force: true)),
          ),
        ),
      ],
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.emptyMessage,
    required this.value,
    required this.accounts,
    required this.onChanged,
    required this.onReload,
  });

  final String label;
  final String emptyMessage;
  final String? value;
  final List<AccountModel> accounts;
  final ValueChanged<String?> onChanged;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final safeValue = accounts.any((a) => a.id == value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('$label-${safeValue ?? ''}-${accounts.length}'),
          initialValue: safeValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: AppTranslation.translate(label),
            border: const OutlineInputBorder(),
          ),
          items: accounts
              .map(
                (a) => DropdownMenuItem<String>(
                  value: a.id,
                  child: AppText('${a.code} — ${a.name} (${a.currency})'),
                ),
              )
              .toList(growable: false),
          validator: (selected) => selected == null || selected.isEmpty
              ? AppTranslation.translate('هذا الحقل مطلوب')
              : null,
          onChanged: accounts.isEmpty ? null : onChanged,
        ),
        if (accounts.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: AppText(AppTranslation.translate(emptyMessage)),
            ),
          ),
      ],
    );
  }
}
