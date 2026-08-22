import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'currency_payment_validator.dart';

enum InvoicePaymentType { partial, full, settlement }

String _normalizedCashboxCurrency(Object? raw) {
  final value = raw?.toString().trim().toUpperCase() ?? '';
  return value == 'USD' || value == 'IQD' ? value : '';
}

bool _hasUsableCashboxIdentity(Map<String, Object?> account) {
  final id = account['id']?.toString().trim() ?? '';
  return id.isNotEmpty &&
      _normalizedCashboxCurrency(account['currency']).isNotEmpty;
}

String? _configuredLinkedCashboxFor({
  required Map<String, dynamic> source,
  required List<Map<String, Object?>> cashAccounts,
  required String invoiceCurrency,
}) {
  final raw = source['linkedCashAccountId'] ?? source['linked_cash_account_id'];
  final id = raw?.toString().trim();
  if (id == null || id.isEmpty) return null;
  final valid = cashAccounts.any(
    (account) =>
        account['id']?.toString() == id &&
        _normalizedCashboxCurrency(account['currency']) ==
            invoiceCurrency.toUpperCase(),
  );
  return valid ? id : null;
}

class InvoicePaymentDraft {
  const InvoicePaymentDraft({
    required this.cashAccountId,
    required this.paymentCurrency,
    required this.invoiceAmount,
    required this.cashAmount,
    required this.exchangeRate,
    required this.paymentType,
    required this.paymentDate,
    this.notes,
    this.settlementAccountId,
    this.linkedCashAccountId,
    required this.paymentKey,
  });

  final String cashAccountId;
  final String paymentCurrency;
  final double invoiceAmount;
  final double cashAmount;
  final double exchangeRate;
  final InvoicePaymentType paymentType;
  final DateTime paymentDate;
  final String? notes;
  final String? settlementAccountId;
  final String? linkedCashAccountId;
  final String paymentKey;

  Map<String, Object?> toRpcJson() => {
    'cashAccountId': cashAccountId,
    'paymentCurrency': paymentCurrency,
    'invoiceAmount': invoiceAmount,
    'cashAmount': cashAmount,
    'exchangeRate': exchangeRate,
    'paymentDate': paymentDate.toUtc().toIso8601String(),
    'notes': notes,
    'paymentMethod': 'cash',
    'settlementMode': switch (paymentType) {
      InvoicePaymentType.partial => 'partial',
      InvoicePaymentType.full => 'full',
      InvoicePaymentType.settlement => 'settlement',
    },
    if (settlementAccountId != null) 'settlementAccountId': settlementAccountId,
    if (linkedCashAccountId != null) 'linkedCashAccountId': linkedCashAccountId,
    'paymentKey': paymentKey,
  };
}

Future<List<InvoicePaymentDraft>?> showInvoicePaymentBatchDialog({
  required BuildContext context,
  required String invoiceCurrency,
  required double remainingAmount,
  required List<Map<String, Object?>> cashAccounts,
  required List<Map<String, Object?>> settlementAccounts,
  required bool purchase,
  String? documentLabelArabic,
  String? documentLabelEnglish,
}) async {
  return showAppWorkspaceDialogBuilder<List<InvoicePaymentDraft>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => InvoicePaymentBatchDialog(
      invoiceCurrency: invoiceCurrency,
      remainingAmount: remainingAmount,
      cashAccounts: cashAccounts,
      settlementAccounts: settlementAccounts,
      purchase: purchase,
      documentLabelArabic: documentLabelArabic,
      documentLabelEnglish: documentLabelEnglish,
    ),
  );
}

class InvoicePaymentBatchDialog extends StatefulWidget {
  const InvoicePaymentBatchDialog({
    super.key,
    required this.invoiceCurrency,
    required this.remainingAmount,
    required this.cashAccounts,
    required this.settlementAccounts,
    required this.purchase,
    this.documentLabelArabic,
    this.documentLabelEnglish,
  });

  final String invoiceCurrency;
  final double remainingAmount;
  final List<Map<String, Object?>> cashAccounts;
  final List<Map<String, Object?>> settlementAccounts;
  final bool purchase;
  final String? documentLabelArabic;
  final String? documentLabelEnglish;

  @override
  State<InvoicePaymentBatchDialog> createState() =>
      _InvoicePaymentBatchDialogState();
}

class _InvoicePaymentBatchDialogState extends State<InvoicePaymentBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_PaymentRowController> _rows = [];

  List<Map<String, Object?>> get _usableCashAccounts => widget.cashAccounts
      .where(_hasUsableCashboxIdentity)
      .toList(growable: false);

  Map<String, dynamic> _preferredCashbox() {
    return Map<String, dynamic>.from(
      _usableCashAccounts.firstWhere(
        (account) =>
            (account['currency']?.toString() ?? '').toUpperCase() ==
            widget.invoiceCurrency.toUpperCase(),
        orElse: () => _usableCashAccounts.first,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (_usableCashAccounts.isNotEmpty) {
      final account = _preferredCashbox();
      _rows.add(
        _PaymentRowController(
          cashAccountId: account['id'].toString(),
          paymentCurrency: _normalizedCashboxCurrency(account['currency']),
          linkedCashAccountId: _configuredLinkedCashboxFor(
            source: account,
            cashAccounts: _usableCashAccounts,
            invoiceCurrency: widget.invoiceCurrency,
          ),
          remaining: widget.remainingAmount,
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final row in _rows) row.dispose();
    super.dispose();
  }

  void _addRow() {
    if (_usableCashAccounts.isEmpty) return;
    setState(() {
      final account = _preferredCashbox();
      _rows.add(
        _PaymentRowController(
          cashAccountId: account['id'].toString(),
          paymentCurrency: _normalizedCashboxCurrency(account['currency']),
          linkedCashAccountId: _configuredLinkedCashboxFor(
            source: account,
            cashAccounts: _usableCashAccounts,
            invoiceCurrency: widget.invoiceCurrency,
          ),
          remaining: _remainingAfterRows,
        ),
      );
    });
  }

  double get _remainingAfterRows {
    final applied = _rows.fold<double>(
      0,
      (sum, row) => sum + row.invoiceAmount,
    );
    return (widget.remainingAmount - applied)
        .clamp(0, double.infinity)
        .toDouble();
  }

  void _removeRow(int index) {
    final row = _rows.removeAt(index);
    row.dispose();
    setState(() {});
  }

  void _recalculate(_PaymentRowController row) {
    if (row.paymentType != InvoicePaymentType.partial) {
      row.invoiceAmountController.text = _remainingAfterRowsFor(
        row,
      ).toStringAsFixed(2);
    }
    final invoiceAmount = row.invoiceAmount;
    final rate = row.exchangeRate;
    if (invoiceAmount <= 0 || rate <= 0) return;
    try {
      final expected = CurrencyPaymentValidator.expectedCashAmount(
        invoiceCurrency: widget.invoiceCurrency,
        paymentCurrency: row.paymentCurrency,
        invoiceAmount: invoiceAmount,
        exchangeRate: rate,
      );
      row.cashAmountController.text = expected.toStringAsFixed(
        row.paymentCurrency == 'IQD' ? 0 : 2,
      );
    } catch (error, stackTrace) {
      AppLogger.debug(
        'Failed to restore payment allocations: $error\n$stackTrace',
      );
    }
  }

  Future<void> _pickPaymentDate(_PaymentRowController row) async {
    final ar = context.l10n.isArabic;
    final date = await showDatePicker(
      context: context,
      initialDate: row.paymentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: ar ? 'اختر تاريخ الدفعة' : 'Select payment date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(row.paymentDate),
      helpText: ar ? 'اختر وقت الدفعة' : 'Select payment time',
    );
    if (!mounted) return;
    final selectedTime = time ?? TimeOfDay.fromDateTime(row.paymentDate);
    setState(() {
      row.paymentDate = DateTime(
        date.year,
        date.month,
        date.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  double _remainingAfterRowsFor(_PaymentRowController target) {
    final appliedByOthers = _rows
        .where((row) => !identical(row, target))
        .fold<double>(0, (sum, row) => sum + row.invoiceAmount);
    return (widget.remainingAmount - appliedByOthers)
        .clamp(0, double.infinity)
        .toDouble();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_rows.isEmpty) return;
    final closingIndexes = <int>[
      for (var index = 0; index < _rows.length; index++)
        if (_rows[index].paymentType != InvoicePaymentType.partial) index,
    ];
    if (closingIndexes.length > 1 ||
        (closingIndexes.isNotEmpty &&
            closingIndexes.single != _rows.length - 1)) {
      _message(
        AppTranslation.translate(
          'يجب أن تكون الدفعة الكلية أو دفعة التسوية هي الدفعة الأخيرة فقط',
        ),
      );
      return;
    }
    final drafts = <InvoicePaymentDraft>[];
    var remaining = widget.remainingAmount;
    for (final row in _rows) {
      final applied = row.paymentType == InvoicePaymentType.partial
          ? row.invoiceAmount
          : remaining;
      if (applied <= 0 || applied > remaining + .01) {
        _message(
          AppTranslation.translate('مجموع الدفعات يتجاوز المبلغ المتبقي'),
        );
        return;
      }
      if (row.paymentCurrency != widget.invoiceCurrency &&
          (row.linkedCashAccountId?.trim().isEmpty ?? true)) {
        _message(
          AppTranslation.translate('اختر الصندوق المرتبط بعملة الفاتورة'),
        );
        return;
      }
      if (row.paymentType == InvoicePaymentType.settlement &&
          (row.settlementAccountId?.trim().isEmpty ?? true)) {
        _message(AppTranslation.translate('يجب اختيار حساب التسوية المحاسبي'));
        return;
      }
      drafts.add(
        InvoicePaymentDraft(
          cashAccountId: row.cashAccountId,
          paymentCurrency: row.paymentCurrency,
          invoiceAmount: applied,
          cashAmount: row.cashAmount,
          exchangeRate: row.exchangeRate,
          paymentType: row.paymentType,
          paymentDate: row.paymentDate,
          notes: row.notesController.text.trim().isEmpty
              ? null
              : row.notesController.text.trim(),
          settlementAccountId: row.paymentType == InvoicePaymentType.settlement
              ? row.settlementAccountId
              : null,
          linkedCashAccountId: row.paymentCurrency == widget.invoiceCurrency
              ? null
              : row.linkedCashAccountId,
          paymentKey: const Uuid().v4(),
        ),
      );
      remaining -= applied;
    }
    Navigator.pop(context, drafts);
  }

  void _message(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: AppText(text)));
  }

  @override
  Widget build(BuildContext context) {
    final wideActions = MediaQuery.sizeOf(context).width >= 1100;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: AppText(
          context.l10n.isArabic
              ? (widget.documentLabelArabic ??
                    (widget.purchase
                        ? 'دفعات فاتورة الشراء'
                        : 'دفعات فاتورة البيع'))
              : (widget.documentLabelEnglish ??
                    (widget.purchase
                        ? 'Purchase invoice payments'
                        : 'Sales invoice payments')),
        ),
        actions: wideActions ? _appBarActions() : null,
      ),
      body: Column(
        children: <Widget>[
          if (!wideActions) _compactActionBar(),
          Expanded(
            child: Form(
              key: _formKey,
              child: _usableCashAccounts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: AppText(
                          AppTranslation.translate(
                            'لا توجد صناديق نقدية معرفة.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return _PaymentRowCard(
                          index: index,
                          row: row,
                          invoiceCurrency: widget.invoiceCurrency,
                          cashAccounts: _usableCashAccounts,
                          settlementAccounts: widget.settlementAccounts,
                          canRemove: _rows.length > 1,
                          onRemove: () => _removeRow(index),
                          onPickPaymentDate: () => _pickPaymentDate(row),
                          onChanged: () {
                            _recalculate(row);
                            setState(() {});
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _appBarActions() => <Widget>[
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Center(
        child: AppText(
          '${AppTranslation.translate('المتبقي')}: ${MoneyFormatter.format(widget.remainingAmount, currency: widget.invoiceCurrency)} ${widget.invoiceCurrency}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    ),
    OutlinedButton.icon(
      onPressed: _usableCashAccounts.isEmpty || _remainingAfterRows <= .01
          ? null
          : _addRow,
      icon: const Icon(Icons.add),
      label: AppText(AppTranslation.translate('إضافة دفعة أخرى')),
    ),
    const SizedBox(width: 6),
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: AppText(AppTranslation.translate('إلغاء')),
    ),
    const SizedBox(width: 6),
    FilledButton.icon(
      onPressed: _rows.isEmpty ? null : _submit,
      icon: const Icon(Icons.account_balance_wallet_outlined),
      label: AppText(AppTranslation.translate('تسجيل جميع الدفعات')),
    ),
    const SizedBox(width: 8),
  ];

  Widget _compactActionBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppText(
            '${AppTranslation.translate('المتبقي')}: ${MoneyFormatter.format(widget.remainingAmount, currency: widget.invoiceCurrency)} ${widget.invoiceCurrency}',
            maxLines: 2,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed:
                    _usableCashAccounts.isEmpty || _remainingAfterRows <= .01
                    ? null
                    : _addRow,
                icon: const Icon(Icons.add),
                label: AppText(AppTranslation.translate('إضافة دفعة أخرى')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: AppText(AppTranslation.translate('إلغاء')),
              ),
              FilledButton.icon(
                onPressed: _rows.isEmpty ? null : _submit,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: AppText(AppTranslation.translate('تسجيل جميع الدفعات')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _PaymentRowController {
  _PaymentRowController({
    required this.cashAccountId,
    required this.paymentCurrency,
    this.linkedCashAccountId,
    required double remaining,
  }) : invoiceAmountController = TextEditingController(
         text: remaining.toStringAsFixed(2),
       ),
       cashAmountController = TextEditingController(
         text: remaining.toStringAsFixed(2),
       ),
       exchangeRateController = TextEditingController(text: '1'),
       notesController = TextEditingController();

  String cashAccountId;
  String paymentCurrency;
  InvoicePaymentType paymentType = InvoicePaymentType.partial;
  String? settlementAccountId;
  String? linkedCashAccountId;
  DateTime paymentDate = DateTime.now();
  final TextEditingController invoiceAmountController;
  final TextEditingController cashAmountController;
  final TextEditingController exchangeRateController;
  final TextEditingController notesController;

  double get invoiceAmount =>
      double.tryParse(invoiceAmountController.text.replaceAll(',', '')) ?? 0;
  double get cashAmount =>
      double.tryParse(cashAmountController.text.replaceAll(',', '')) ?? 0;
  double get exchangeRate =>
      double.tryParse(exchangeRateController.text.replaceAll(',', '')) ?? 0;

  void dispose() {
    invoiceAmountController.dispose();
    cashAmountController.dispose();
    exchangeRateController.dispose();
    notesController.dispose();
  }
}

class _PaymentRowCard extends StatelessWidget {
  const _PaymentRowCard({
    required this.index,
    required this.row,
    required this.invoiceCurrency,
    required this.cashAccounts,
    required this.settlementAccounts,
    required this.canRemove,
    required this.onRemove,
    required this.onPickPaymentDate,
    required this.onChanged,
  });

  final int index;
  final _PaymentRowController row;
  final String invoiceCurrency;
  final List<Map<String, Object?>> cashAccounts;
  final List<Map<String, Object?>> settlementAccounts;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onPickPaymentDate;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppText(
                    '${AppTranslation.translate('الدفعة')} ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: AppTranslation.translate('حذف'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                double width(double preferred) =>
                    preferred.clamp(0, constraints.maxWidth).toDouble();
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: width(260),
                      child: InkWell(
                        onTap: onPickPaymentDate,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'تاريخ ووقت الدفعة',
                            ),
                            prefixIcon: const Icon(
                              Icons.event_available_outlined,
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          child: AppText(
                            DateFormat(
                              'yyyy-MM-dd HH:mm',
                            ).format(row.paymentDate),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: width(260),
                      child: DropdownButtonFormField<InvoicePaymentType>(
                        isExpanded: true,
                        initialValue: row.paymentType,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('نوع الدفعة'),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: InvoicePaymentType.partial,
                            child: AppText(
                              AppTranslation.translate('دفعة جزئية'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: InvoicePaymentType.full,
                            child: AppText(
                              AppTranslation.translate('دفعة كلية'),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          row.paymentType = value ?? InvoicePaymentType.partial;
                          onChanged();
                        },
                      ),
                    ),
                    SizedBox(
                      width: width(300),
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: row.cashAccountId,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('الصندوق المالي'),
                          border: OutlineInputBorder(),
                        ),
                        items: cashAccounts
                            .map(
                              (account) => DropdownMenuItem(
                                value: account['id'].toString(),
                                child: AppText(
                                  '${account['name']} (${account['currency']})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final account = cashAccounts.firstWhere(
                            (item) => item['id'].toString() == value,
                          );
                          row.cashAccountId = value;
                          row.paymentCurrency = _normalizedCashboxCurrency(
                            account['currency'],
                          );
                          if (row.paymentCurrency == invoiceCurrency) {
                            row.linkedCashAccountId = null;
                            row.exchangeRateController.text = '1';
                          } else {
                            row.linkedCashAccountId =
                                _configuredLinkedCashboxFor(
                                  source: account,
                                  cashAccounts: cashAccounts,
                                  invoiceCurrency: invoiceCurrency,
                                );
                          }
                          onChanged();
                        },
                      ),
                    ),
                    if (row.paymentCurrency != invoiceCurrency)
                      SizedBox(
                        width: width(300),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: row.linkedCashAccountId,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'الصندوق المرتبط بعملة الفاتورة $invoiceCurrency',
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          items: cashAccounts
                              .where(
                                (account) =>
                                    (account['currency']?.toString() ?? '')
                                        .toUpperCase() ==
                                    invoiceCurrency.toUpperCase(),
                              )
                              .map(
                                (account) => DropdownMenuItem(
                                  value: account['id'].toString(),
                                  child: AppText(
                                    '${account['name']} (${account['currency']})',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            row.linkedCashAccountId = value;
                            onChanged();
                          },
                          validator: (value) =>
                              row.paymentCurrency != invoiceCurrency &&
                                  (value == null || value.isEmpty)
                              ? AppTranslation.translate('اختر الصندوق المرتبط')
                              : null,
                        ),
                      ),
                    SizedBox(
                      width: width(210),
                      child: TextFormField(
                        controller: row.invoiceAmountController,
                        enabled: row.paymentType == InvoicePaymentType.partial,

                        inputFormatters: <TextInputFormatter>[
                          ThousandsInputFormatter(decimalDigits: 2),
                        ],
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate(
                            'المبلغ بعملة الفاتورة $invoiceCurrency',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => onChanged(),
                        validator: (_) => row.invoiceAmount <= 0
                            ? AppTranslation.translate('أدخل مبلغًا صحيحًا')
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: width(210),
                      child: TextFormField(
                        controller: row.cashAmountController,

                        inputFormatters: <TextInputFormatter>[
                          ThousandsInputFormatter(decimalDigits: 2),
                        ],
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate(
                            'مبلغ الصندوق ${row.paymentCurrency}',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (_) => row.cashAmount <= 0
                            ? AppTranslation.translate('أدخل مبلغ الصندوق')
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: width(180),
                      child: TextFormField(
                        controller: row.exchangeRateController,

                        inputFormatters: <TextInputFormatter>[
                          ThousandsInputFormatter(decimalDigits: 20),
                        ],
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('معامل التحويل'),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => onChanged(),
                        validator: (_) => row.exchangeRate <= 0
                            ? AppTranslation.translate('أدخل معاملًا صحيحًا')
                            : null,
                      ),
                    ),
                    if (row.paymentType == InvoicePaymentType.settlement)
                      SizedBox(
                        width: width(300),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: row.settlementAccountId,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate(
                              'حساب التسوية في الشجرة المحاسبية',
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: settlementAccounts
                              .map(
                                (account) => DropdownMenuItem(
                                  value: account['id'].toString(),
                                  child: AppText(
                                    '${account['code'] ?? ''} - ${account['name'] ?? ''}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            row.settlementAccountId = value;
                            onChanged();
                          },
                          validator: (value) =>
                              row.paymentType ==
                                      InvoicePaymentType.settlement &&
                                  (value == null || value.isEmpty)
                              ? AppTranslation.translate('اختر حساب التسوية')
                              : null,
                        ),
                      ),
                    SizedBox(
                      width: width(420),
                      child: TextFormField(
                        controller: row.notesController,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('ملاحظات الدفعة'),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
