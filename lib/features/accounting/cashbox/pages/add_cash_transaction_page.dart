import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/features/accounting/cashbox/controllers/cashbox_controller.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';

class AddCashTransactionPage extends StatefulWidget {
  const AddCashTransactionPage({
    super.key,
    this.transaction,
    this.initialType = 'receipt',
  });
  final CashTransactionModel? transaction;
  final String initialType;

  @override
  State<AddCashTransactionPage> createState() => _AddCashTransactionPageState();
}

class _AddCashTransactionPageState extends State<AddCashTransactionPage> {
  final _key = GlobalKey<FormState>();

  String get _writePermission =>
      _type == 'receipt' ? 'cashbox.receipt' : 'cashbox.payment';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'cashbox',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: _writePermission,
    child: child,
  );
  late final TextEditingController _voucher, _category, _amount, _party, _notes;
  late String _type;
  String _currency = 'USD';
  String _partyType = 'other';
  String _method = 'cash';
  String? _cashAccountId;
  String? _counterAccountId;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _type = t?.type ?? widget.initialType;
    _currency = SupportedCurrency.initial(
      isNew: t == null,
      stored: t?.currency,
    );
    _partyType = t?.partyType ?? 'other';
    _method = t?.paymentMethod ?? 'cash';
    _cashAccountId = t?.cashAccountId;
    _counterAccountId = t?.counterAccountId;
    _date = t?.transactionDate ?? DateTime.now();
    _voucher = TextEditingController(text: t?.voucherNumber ?? _number());
    _category = TextEditingController(text: t?.category ?? '');
    _amount = TextEditingController(text: t == null ? '' : t.amount.toString());
    _party = TextEditingController(text: t?.partyName ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
  }

  String _number() =>
      '${_type == 'receipt' ? 'RCV' : 'PAY'}-${DateTime.now().millisecondsSinceEpoch}';
  @override
  void dispose() {
    for (final c in [_voucher, _category, _amount, _party, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_key.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final old = widget.transaction;
      final item = CashTransactionModel(
        id: old?.id ?? const Uuid().v4(),
        voucherNumber: _voucher.text.trim(),
        type: _type,
        category: _category.text.trim(),
        amount: double.parse(_amount.text.replaceAll(',', '')),
        currency: _currency,
        transactionDate: _date,
        partyType: _partyType,
        partyId: old?.partyId,
        partyName: _party.text.trim().isEmpty ? null : _party.text.trim(),
        paymentMethod: _method,
        referenceType: old?.referenceType,
        referenceId: old?.referenceId,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        createdAt: old?.createdAt ?? DateTime.now(),
        updatedAt: old == null ? null : DateTime.now(),
        cashAccountId: _cashAccountId,
        counterAccountId: _counterAccountId,
        journalEntryId: old?.journalEntryId,
      );
      final c = context.read<CashboxController>();
      old == null
          ? await c.addTransaction(item)
          : await c.updateTransaction(item);
      if (mounted) AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: AppText(
              context.read<CashboxController>().errorMessage ??
                  userFacingError(e, isArabic: context.l10n.isArabic),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTransactionDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (!mounted) return;
    final selectedTime = time ?? TimeOfDay.fromDateTime(_date);
    setState(() {
      _date = DateTime(
        date.year,
        date.month,
        date.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CashboxController>();
    final cashboxes = c.cashAccounts
        .where((a) => a.isActive && a.currency == _currency)
        .toList();
    final selectedCashAccountId =
        _cashAccountId != null && cashboxes.any((a) => a.id == _cashAccountId)
        ? _cashAccountId
        : null;
    String? selectedCashLedgerId;
    for (final cashbox in c.cashAccounts) {
      if (cashbox.id == selectedCashAccountId) {
        selectedCashLedgerId = cashbox.accountId;
        break;
      }
    }
    final accounts = c.ledgerAccounts
        .where(
          (a) =>
              a.isActive &&
              (a.currency == _currency || a.currency == 'MULTI') &&
              a.id != selectedCashLedgerId,
        )
        .toList();
    final selectedCounterAccountId =
        _counterAccountId != null &&
            accounts.any((a) => a.id == _counterAccountId)
        ? _counterAccountId
        : null;
    return Scaffold(
      appBar: AppBar(
        title: AppText(
          widget.transaction == null ? 'سند مالي جديد' : 'تعديل السند المالي',
        ),
      ),
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 300,
                  child: _securedField(
                    'transactionType',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _type,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('نوع الحركة'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'receipt',
                          child: AppText('سند قبض'),
                        ),
                        DropdownMenuItem(
                          value: 'payment',
                          child: AppText('سند صرف'),
                        ),
                      ],
                      onChanged: widget.transaction == null
                          ? (v) => setState(() {
                              _type = v ?? 'receipt';
                              _voucher.text = _number();
                            })
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: _securedField(
                    'documentNumber',
                    TextFormField(
                      controller: _voucher,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('رقم السند *'),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? AppTranslation.translate('رقم السند مطلوب')
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: _securedField(
                    'currency',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: SupportedCurrency.normalize(_currency),
                      validator: (value) => SupportedCurrency.isSupported(value)
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
                        _cashAccountId = null;
                        _counterAccountId = null;
                      }),
                    ),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: _securedField(
                    'amount',
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),

                      inputFormatters: <TextInputFormatter>[
                        ThousandsInputFormatter(decimalDigits: 2),
                      ],
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('المبلغ *'),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (double.tryParse((v ?? '').replaceAll(',', '')) ??
                                  0) <=
                              0
                          ? AppTranslation.translate('أدخل مبلغًا صحيحًا')
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                title: const AppText('التاريخ والوقت التشغيلي'),
                subtitle: AppText(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')} '
                  '${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}',
                ),
                onTap: _pickTransactionDateTime,
              ),
            ),
            const SizedBox(height: 12),
            _securedField(
              'cashAccount',
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedCashAccountId,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate(
                    'الصندوق المستلم أو الصارف *',
                  ),
                  border: OutlineInputBorder(),
                ),
                items: cashboxes
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: AppText(
                          '${a.name} — الرصيد ${MoneyFormatter.format(c.balances[a.id] ?? 0, currency: a.currency)} ${a.currency}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _cashAccountId = v),
                validator: (v) =>
                    v == null ? AppTranslation.translate('اختر الصندوق') : null,
              ),
            ),
            const SizedBox(height: 12),
            _securedField(
              'counterAccount',
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedCounterAccountId,
                decoration: InputDecoration(
                  labelText: _type == 'receipt'
                      ? 'الحساب الدائن المقابل *'
                      : 'الحساب المدين المقابل *',
                  helperText: AppTranslation.translate(
                    'يتم إنشاء قيد يومية متوازن تلقائيًا وفق اختيار المستخدم.',
                  ),
                  border: const OutlineInputBorder(),
                ),
                items: accounts
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
                onChanged: (v) => setState(() => _counterAccountId = v),
                validator: (v) => v == null
                    ? AppTranslation.translate('اختر الحساب المقابل')
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            _securedField(
              'purpose',
              TextFormField(
                controller: _category,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('الغرض أو التصنيف *'),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? AppTranslation.translate('أدخل الغرض المالي')
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _securedField(
                    'partyType',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _partyType,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('نوع الجهة'),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'customer',
                          child: AppText('عميل'),
                        ),
                        DropdownMenuItem(
                          value: 'supplier',
                          child: AppText('مورد'),
                        ),
                        DropdownMenuItem(
                          value: 'employee',
                          child: AppText('موظف'),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: AppText('أخرى'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _partyType = v ?? 'other'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _securedField(
                    'partyName',
                    TextFormField(
                      controller: _party,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('اسم الجهة'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _securedField(
              'notes',
              TextFormField(
                controller: _notes,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('البيان والملاحظات'),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: AppText(
                _saving ? 'جارٍ الحفظ...' : 'حفظ وترحيل القيد المحاسبي',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
