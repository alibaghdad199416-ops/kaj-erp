import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/features/accounting/cashbox/controllers/cashbox_controller.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class CashAccountForm extends StatefulWidget {
  const CashAccountForm({super.key, this.account});
  final CashAccountModel? account;

  @override
  State<CashAccountForm> createState() => _CashAccountFormState();
}

class _CashAccountFormState extends State<CashAccountForm> {
  final _key = GlobalKey<FormState>();

  String get _writePermission =>
      widget.account == null ? 'accounting.create' : 'accounting.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'cashbox',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: _writePermission,
    child: child,
  );
  late final TextEditingController _name;
  late final TextEditingController _opening;
  String _type = 'cash';
  String _currency = 'USD';
  String? _ledgerId;
  String? _linkedCashAccountId;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.account;
    _name = TextEditingController(text: item?.name ?? '');
    _opening = TextEditingController(
      text: item == null ? '0' : item.openingBalance.toString(),
    );
    _type = item?.type ?? 'cash';
    _currency = SupportedCurrency.initial(
      isNew: item == null,
      stored: item?.currency,
    );
    _ledgerId = item?.accountId;
    _linkedCashAccountId = item?.linkedCashAccountId;
    _active = item?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        !(_key.currentState?.validate() ?? false) ||
        _ledgerId == null)
      return;
    setState(() => _saving = true);
    try {
      final old = widget.account;
      await context.read<CashboxController>().saveCashAccount(
        CashAccountModel(
          id: old?.id ?? const Uuid().v4(),
          name: _name.text.trim(),
          type: _type,
          currency: _currency,
          openingBalance:
              double.tryParse(_opening.text.replaceAll(',', '')) ?? 0,
          isActive: _active,
          accountId: _ledgerId!,
          createdAt: old?.createdAt ?? DateTime.now(),
          updatedAt: old?.updatedAt,
          linkedCashAccountId: _linkedCashAccountId,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CashboxController>();
    final ledger = controller.ledgerAccounts
        .where(
          (a) =>
              a.type == 'asset' &&
              (a.currency == _currency || a.currency == 'MULTI'),
        )
        .toList();
    final selectedLedgerId = ledger.any((a) => a.id == _ledgerId)
        ? _ledgerId
        : null;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: AppText(
              widget.account == null
                  ? 'إنشاء صندوق نقدي'
                  : 'تعديل الصندوق النقدي',
            ),
          ),
          IconButton(
            tooltip: AppTranslation.translate('إغلاق'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, 620),
        child: Form(
          key: _key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _securedField(
                  'name',
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('اسم الصندوق *'),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? AppTranslation.translate('اسم الصندوق مطلوب')
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final type = _securedField(
                      'type',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _type,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('نوع الصندوق'),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'cash',
                            child: AppText('صندوق نقدي'),
                          ),
                          DropdownMenuItem(
                            value: 'bank',
                            child: AppText('حساب مصرفي'),
                          ),
                          DropdownMenuItem(
                            value: 'wallet',
                            child: AppText('محفظة إلكترونية'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'cash'),
                      ),
                    );
                    final currency = _securedField(
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
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'USD',
                            child: AppText('USD - دولار أمريكي'),
                          ),
                          DropdownMenuItem(
                            value: 'IQD',
                            child: AppText('IQD - دينار عراقي'),
                          ),
                        ],
                        onChanged: (v) => setState(() {
                          final code = SupportedCurrency.normalize(v);
                          if (code == null) return;
                          _currency = code;
                          _ledgerId = null;
                        }),
                      ),
                    );
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          type,
                          const SizedBox(height: 12),
                          currency,
                        ],
                      );
                    }
                    return Row(
                      children: <Widget>[
                        Expanded(child: type),
                        const SizedBox(width: 12),
                        Expanded(child: currency),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _securedField(
                  'ledgerAccount',
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    key: ValueKey('ledger-$_currency-$selectedLedgerId'),
                    initialValue: selectedLedgerId,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate(
                        'حساب الصندوق في شجرة الحسابات *',
                      ),
                      border: OutlineInputBorder(),
                      helperText: AppTranslation.translate(
                        'يستطيع المستخدم اختيار الحساب المحاسبي وتغييره لاحقًا.',
                      ),
                    ),
                    items: ledger
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: AppText(
                              '${a.code} — ${a.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _ledgerId = v),
                    validator: (v) => v == null
                        ? AppTranslation.translate('اختر حساب شجرة الحسابات')
                        : null,
                  ),
                ),

                const SizedBox(height: 12),
                _securedField(
                  'linkedCashAccount',
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    key: ValueKey(
                      'linked-cash-$_currency-$_linkedCashAccountId',
                    ),
                    initialValue:
                        controller.cashAccounts.any(
                          (a) =>
                              a.id == _linkedCashAccountId &&
                              a.currency != _currency,
                        )
                        ? _linkedCashAccountId
                        : null,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate(
                        'الصندوق المرتبط للعملة الأخرى',
                      ),
                      border: const OutlineInputBorder(),
                      helperText: AppTranslation.translate(
                        'يستخدم تلقائيًا عند دفع فاتورة بعملة مغايرة.',
                      ),
                    ),
                    items: <DropdownMenuItem<String?>>[
                      DropdownMenuItem<String?>(
                        value: null,
                        child: AppText('بدون ربط'),
                      ),
                      ...controller.cashAccounts
                          .where(
                            (a) =>
                                a.id != widget.account?.id &&
                                a.currency != _currency &&
                                a.isActive,
                          )
                          .map(
                            (a) => DropdownMenuItem<String?>(
                              value: a.id,
                              child: AppText(
                                '${a.name} (${a.currency})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) =>
                        setState(() => _linkedCashAccountId = value),
                  ),
                ),
                const SizedBox(height: 12),
                _securedField(
                  'openingBalance',
                  TextFormField(
                    controller: _opening,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),

                    inputFormatters: <TextInputFormatter>[
                      ThousandsInputFormatter(decimalDigits: 2),
                    ],
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('الرصيد الافتتاحي'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                _securedField(
                  'isActive',
                  SwitchListTile(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    title: const AppText('الصندوق فعال'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const AppText('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: AppText(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
        ),
      ],
    );
  }
}
