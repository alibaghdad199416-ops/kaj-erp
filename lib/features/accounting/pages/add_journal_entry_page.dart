import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/models/journal_entry_model.dart';
import 'package:quality_line_erp/features/accounting/models/journal_line_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class AddJournalEntryPage extends StatefulWidget {
  const AddJournalEntryPage({
    super.key,
    this.entry,
    this.initialLines = const [],
  });

  final JournalEntryModel? entry;
  final List<JournalLineModel> initialLines;

  @override
  State<AddJournalEntryPage> createState() => _AddJournalEntryPageState();
}

class _AddJournalEntryPageState extends State<AddJournalEntryPage> {
  final _formKey = GlobalKey<FormState>();

  String get _writePermission =>
      widget.entry == null ? 'accounting.create' : 'accounting.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'accounting',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: _writePermission,
    child: child,
  );
  final _numberController = TextEditingController();
  final _descriptionController = TextEditingController();
  final List<_LineEditor> _lines = [];
  DateTime _entryDate = DateTime.now();
  String _currency = 'USD';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.entry;
    if (existing == null) {
      final now = DateTime.now();
      _numberController.text =
          'JV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch.toString().substring(8)}';
      _lines.addAll([_LineEditor(), _LineEditor()]);
    } else {
      _numberController.text = existing.entryNumber;
      _descriptionController.text = existing.description;
      _entryDate = existing.entryDate;
      _currency = existing.currency;
      _lines.addAll(widget.initialLines.map(_LineEditor.fromModel));
      while (_lines.length < 2) {
        _lines.add(_LineEditor());
      }
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _descriptionController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _totalDebit => _lines.fold(
    0,
    (sum, line) =>
        sum + (double.tryParse(line.debit.text.replaceAll(',', '')) ?? 0),
  );
  double get _totalCredit => _lines.fold(
    0,
    (sum, line) =>
        sum + (double.tryParse(line.credit.text.replaceAll(',', '')) ?? 0),
  );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = context.read<AccountingController>();
    final validLines = _lines.where((line) => line.account != null).toList();
    for (final line in validLines) {
      final debit = double.tryParse(line.debit.text.replaceAll(',', '')) ?? 0;
      final credit = double.tryParse(line.credit.text.replaceAll(',', '')) ?? 0;
      if (debit < 0 ||
          credit < 0 ||
          (debit > 0 && credit > 0) ||
          (debit == 0 && credit == 0)) {
        _showError('يجب أن يحتوي كل سطر على مبلغ مدين أو دائن موجب واحد فقط.');
        return;
      }
      final accountCurrency = line.account!.currency.toUpperCase();
      if (accountCurrency != _currency && accountCurrency != 'MULTI') {
        _showError('عملة حساب السطر لا تطابق عملة القيد.');
        return;
      }
    }
    if (validLines.length < 2) {
      _showError('يجب إضافة سطرين محاسبيين على الأقل.');
      return;
    }
    if ((_totalDebit - _totalCredit).abs() > 0.01 || _totalDebit <= 0) {
      _showError('القيد غير متوازن. يجب أن يتساوى المدين مع الدائن.');
      return;
    }

    setState(() => _saving = true);
    try {
      final id = widget.entry?.id ?? const Uuid().v4();
      final now = DateTime.now();
      final entry = JournalEntryModel(
        id: id,
        entryNumber: _numberController.text.trim(),
        entryDate: _entryDate,
        description: _descriptionController.text.trim(),
        currency: _currency,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        status: 'posted',
        createdAt: widget.entry?.createdAt ?? now,
        updatedAt: widget.entry == null ? null : now,
      );
      final lines = validLines.map((line) {
        final account = line.account!;
        return JournalLineModel(
          id: widget.entry == null
              ? const Uuid().v4()
              : (line.originalId ?? const Uuid().v4()),
          entryId: id,
          accountId: account.id,
          accountCode: account.code,
          accountName: account.name,
          debit: double.tryParse(line.debit.text.replaceAll(',', '')) ?? 0,
          credit: double.tryParse(line.credit.text.replaceAll(',', '')) ?? 0,
          description: line.description.text.trim().isEmpty
              ? null
              : line.description.text.trim(),
        );
      }).toList();
      if (widget.entry == null) {
        await controller.addEntry(entry: entry, lines: lines);
      } else {
        await controller.updateEntry(entry: entry, lines: lines);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      _showError(controller.errorMessage ?? 'تعذر حفظ القيد.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _pickEntryDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_entryDate),
    );
    if (!mounted) return;
    final selected = time ?? TimeOfDay.fromDateTime(_entryDate);
    setState(() {
      _entryDate = DateTime(
        date.year,
        date.month,
        date.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountingController>().accounts;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: AppText(
            widget.entry == null ? 'قيد يومية جديد' : 'تعديل قيد اليومية',
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _securedField(
                      'entryNumber',
                      TextFormField(
                        controller: _numberController,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('رقم القيد'),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? AppTranslation.translate('رقم القيد مطلوب')
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _securedField(
                      'currency',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _currency,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('العملة'),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'USD', child: AppText('USD')),
                          DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                        ],
                        onChanged: (value) => setState(() {
                          _currency = value ?? _currency;
                          for (final line in _lines) {
                            final accountCurrency = line.account?.currency
                                .toUpperCase();
                            if (accountCurrency != null &&
                                accountCurrency != _currency &&
                                accountCurrency != 'MULTI') {
                              line.account = null;
                            }
                          }
                        }),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _securedField(
                'entryDate',
                OutlinedButton.icon(
                  onPressed: _pickEntryDateTime,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: AppText(
                    '${_entryDate.year}-${_entryDate.month.toString().padLeft(2, '0')}-${_entryDate.day.toString().padLeft(2, '0')} '
                    '${_entryDate.hour.toString().padLeft(2, '0')}:${_entryDate.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _securedField(
                'description',
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('وصف القيد'),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? AppTranslation.translate('وصف القيد مطلوب')
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(_lines.length, (index) {
                final line = _lines[index];
                line.account ??= accounts.cast<AccountModel?>().firstWhere(
                  (account) => account?.id == line.originalAccountId,
                  orElse: () => null,
                );
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _securedField(
                                'journalLines',
                                DropdownButtonFormField<AccountModel>(
                                  isExpanded: true,
                                  initialValue: line.account,
                                  decoration: InputDecoration(
                                    labelText: AppTranslation.translate(
                                      'الحساب ${index + 1}',
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  items: accounts
                                      .where(
                                        (account) =>
                                            account.isActive &&
                                            (account.currency.toUpperCase() ==
                                                    _currency ||
                                                account.currency
                                                        .toUpperCase() ==
                                                    'MULTI'),
                                      )
                                      .map(
                                        (account) => DropdownMenuItem(
                                          value: account,
                                          child: AppText(
                                            '${account.code} - ${account.name}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => line.account = value,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _securedField(
                                'debit',
                                TextFormField(
                                  controller: line.debit,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),

                                  inputFormatters: <TextInputFormatter>[
                                    ThousandsInputFormatter(decimalDigits: 2),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: AppTranslation.translate('مدين'),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _securedField(
                                'credit',
                                TextFormField(
                                  controller: line.credit,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),

                                  inputFormatters: <TextInputFormatter>[
                                    ThousandsInputFormatter(decimalDigits: 2),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: AppTranslation.translate('دائن'),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            if (_lines.length > 2)
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _lines.removeAt(index).dispose();
                                  });
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _securedField(
                          'journalLines',
                          TextField(
                            controller: line.description,
                            decoration: InputDecoration(
                              labelText: AppTranslation.translate(
                                'بيان السطر (اختياري)',
                              ),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: () => setState(() => _lines.add(_LineEditor())),
                icon: const Icon(Icons.add),
                label: const AppText('إضافة سطر'),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      AppText(
                        'إجمالي المدين: ${MoneyFormatter.format(_totalDebit, currency: _currency)}',
                      ),
                      AppText(
                        'إجمالي الدائن: ${MoneyFormatter.format(_totalCredit, currency: _currency)}',
                      ),
                      AppText(
                        (_totalDebit - _totalCredit).abs() <= 0.01 &&
                                _totalDebit > 0
                            ? 'متوازن'
                            : 'غير متوازن',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              (_totalDebit - _totalCredit).abs() <= 0.01 &&
                                  _totalDebit > 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: AppText(
                  widget.entry == null
                      ? 'حفظ وترحيل القيد'
                      : 'حفظ تعديلات القيد',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineEditor {
  _LineEditor();

  _LineEditor.fromModel(JournalLineModel model) {
    originalId = model.id;
    originalAccountId = model.accountId;
    debit.text = model.debit == 0 ? '' : model.debit.toString();
    credit.text = model.credit == 0 ? '' : model.credit.toString();
    description.text = model.description ?? '';
  }

  String? originalId;
  String? originalAccountId;
  AccountModel? account;
  final debit = TextEditingController();
  final credit = TextEditingController();
  final description = TextEditingController();

  void dispose() {
    debit.dispose();
    credit.dispose();
    description.dispose();
  }
}
