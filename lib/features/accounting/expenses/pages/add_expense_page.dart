import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:quality_line_erp/features/accounting/expenses/controllers/expenses_controller.dart';
import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

String expenseAccountDisplayLabel(Map<String, Object?> row) =>
    '${ErpDisplayFormatter.accountCode(row['code'])} — '
    '${row['name'] ?? row['nameAr'] ?? ''}';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key});

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'expenses',
    field: field,
    viewPermission: 'accounting.view',
    writePermission: 'accounting.create',
    child: child,
  );

  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final notesController = TextEditingController();

  String category = 'أخرى';
  String currency = 'USD';
  String? accountId;
  String? expenseAccountId;
  String branchId = 'branch-main';
  bool loadingOptions = true;
  bool saving = false;
  DateTime operationalDate = DateTime.now();
  String? optionsError;
  List<Map<String, Object?>> accounts = const [];
  List<Map<String, Object?>> expenseAccounts = const [];
  List<Map<String, Object?>> currencies = const [
    {'code': 'USD'},
    {'code': 'IQD'},
  ];

  final categories = const [
    'رواتب',
    'إيجار',
    'كهرباء',
    'ماء',
    'نقل',
    'صيانة',
    'تسويق',
    'مشتريات',
    'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  Future<void> _loadOptions() async {
    if (mounted) {
      setState(() {
        loadingOptions = true;
        optionsError = null;
      });
    }
    try {
      final repository = context.read<ExpensesController>().repository;
      final values = await Future.wait<List<Map<String, Object?>>>([
        repository.activeAccounts(),
        repository.activeExpenseAccounts(),
      ]).timeout(const Duration(seconds: 18));
      if (!mounted) return;
      final loadedAccounts = values[0];
      final loadedExpenseAccounts = values[1];
      final selectedAccount = loadedAccounts.firstOrNull;
      final selectedCurrency = selectedAccount?['currency']
          ?.toString()
          .trim()
          .toUpperCase();
      final safeCurrency = selectedCurrency == 'IQD' ? 'IQD' : 'USD';
      final matchingExpenseAccounts = loadedExpenseAccounts.where((row) {
        final value = row['currency']?.toString().trim().toUpperCase();
        return value == safeCurrency || value == 'MULTI' || value == null;
      });
      setState(() {
        accounts = loadedAccounts;
        expenseAccounts = loadedExpenseAccounts;
        accountId = selectedAccount?['id']?.toString();
        expenseAccountId = matchingExpenseAccounts.firstOrNull?['id']
            ?.toString();
        currency = safeCurrency;
        branchId = 'branch-main';
        loadingOptions = false;
        if (loadedAccounts.isEmpty || loadedExpenseAccounts.isEmpty) {
          optionsError = loadedAccounts.isEmpty
              ? AppTranslation.translate(
                  'لا توجد حسابات صندوق أو بنك فعالة. أضف حسابًا نقديًا من شجرة الحسابات أولًا.',
                )
              : AppTranslation.translate(
                  'لا توجد حسابات مصروفات فعالة. أضف حسابًا من نوع مصروف أولًا.',
                );
        }
      });
    } catch (error) {
      AppLogger.debug('Expense option loading failed: $error');
      if (!mounted) return;
      setState(() {
        loadingOptions = false;
        optionsError = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: AppTranslation.translate(
            'تعذر تحميل حسابات المصروف. تحقق من الاتصال ثم أعد المحاولة.',
          ),
          englishFallback:
              'Unable to load expense accounts. Check the connection and retry.',
        );
      });
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> saveExpense() async {
    final amount = ThousandsInputFormatter.parse(amountController.text) ?? 0;
    if (titleController.text.trim().isEmpty ||
        amount <= 0 ||
        accountId == null ||
        expenseAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'يرجى إكمال الحساب والعملة والمبلغ.'
                : 'Complete the account, currency, and amount.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      // Expenses are posted in their document currency. Exchange rates belong
      // exclusively to payment settlement and financial transfer workflows.
      final amountUsd = currency == 'USD' ? amount : 0.0;
      final amountIqd = currency == 'IQD' ? amount : 0.0;
      final expense = ExpenseModel(
        id: const Uuid().v4(),
        title: titleController.text.trim(),
        category: category,
        amount: amount,
        date: operationalDate.toIso8601String(),
        notes: notesController.text.trim(),
        accountId: accountId,
        expenseAccountId: expenseAccountId,
        branchId: branchId,
        currency: currency,
        exchangeRate: 1,
        amountUsd: amountUsd,
        amountIqd: amountIqd,
        postingStatus: 'posted',
      );
      await context.read<ExpensesController>().addExpense(expense);
      if (mounted) AppWorkspaceWindowScope.closeCurrent(context);
    } catch (error) {
      if (!mounted) return;
      AppLogger.debug('Expense save failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _pickOperationalDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: operationalDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(operationalDate),
    );
    if (!mounted) return;
    final selectedTime = time ?? TimeOfDay.fromDateTime(operationalDate);
    setState(() {
      operationalDate = DateTime(
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
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const AppText('إضافة مصروف'),
      ),
      body: loadingOptions
          ? const Center(child: CircularProgressIndicator())
          : optionsError != null
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 42),
                        const SizedBox(height: 12),
                        AppText(optionsError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadOptions,
                          icon: const Icon(Icons.refresh),
                          label: const AppText('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    _securedField(
                      'name',
                      TextField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('اسم المصروف'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _securedField(
                            'amount',
                            TextField(
                              controller: amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),

                              inputFormatters: <TextInputFormatter>[
                                ThousandsInputFormatter(decimalDigits: 2),
                              ],
                              decoration: InputDecoration(
                                labelText: AppTranslation.translate('المبلغ'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _securedField(
                            'currency',
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: currency,
                              decoration: InputDecoration(
                                labelText: AppTranslation.translate('العملة'),
                              ),
                              items: currencies.map((row) {
                                final code = row['code']?.toString() ?? '';
                                return DropdownMenuItem(
                                  value: code,
                                  child: AppText(code),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  currency = value;
                                  final matches = accounts.where(
                                    (row) =>
                                        row['currency']
                                            ?.toString()
                                            .toUpperCase() ==
                                        value,
                                  );
                                  if (!matches.any(
                                    (row) => row['id'] == accountId,
                                  )) {
                                    accountId = matches.firstOrNull?['id']
                                        ?.toString();
                                  }
                                  final matchingExpenses = expenseAccounts
                                      .where((row) {
                                        final accountCurrency = row['currency']
                                            ?.toString()
                                            .trim()
                                            .toUpperCase();
                                        return accountCurrency == value ||
                                            accountCurrency == 'MULTI';
                                      });
                                  if (!matchingExpenses.any(
                                    (row) => row['id'] == expenseAccountId,
                                  )) {
                                    expenseAccountId = matchingExpenses
                                        .firstOrNull?['id']
                                        ?.toString();
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _securedField(
                      'cashAccount',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: accountId,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate(
                            'الصندوق أو الحساب',
                          ),
                        ),
                        items: accounts
                            .where(
                              (row) =>
                                  row['currency']?.toString().toUpperCase() ==
                                  currency,
                            )
                            .map(
                              (row) => DropdownMenuItem(
                                value: row['id']?.toString(),
                                child: AppText(
                                  '${row['name']} (${row['currency']})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => accountId = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _securedField(
                      'expenseAccount',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: expenseAccountId,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate(
                            'حساب الكلفة (مصروف فقط)',
                          ),
                        ),
                        items: expenseAccounts
                            .where((row) {
                              final c = row['currency']
                                  ?.toString()
                                  .toUpperCase();
                              return c == currency || c == 'MULTI';
                            })
                            .map(
                              (row) => DropdownMenuItem(
                                value: row['id']?.toString(),
                                child: AppText(expenseAccountDisplayLabel(row)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => expenseAccountId = value),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _securedField(
                      'category',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: category,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('التصنيف'),
                        ),
                        items: categories
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: AppText(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => category = value);
                        },
                      ),
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
                          operationalDate.toLocal().toString().substring(0, 16),
                        ),
                        onTap: _pickOperationalDate,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _securedField(
                      'notes',
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('ملاحظات'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving ? null : saveExpense,
                        child: saving
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const AppText('حفظ المصروف'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
