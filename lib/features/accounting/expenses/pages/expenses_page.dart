import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/widgets/incremental_list_view.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';

import 'package:quality_line_erp/features/accounting/expenses/controllers/expenses_controller.dart';
import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';
import 'package:quality_line_erp/features/accounting/expenses/pages/add_expense_page.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/features/accounting/expenses/widgets/expense_card.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final UnifiedQueryController _queryController = UnifiedQueryController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<ExpensesController>().loadExpenses());
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  String? _filterValue(UnifiedQueryState state, String key) {
    final token = state.filters.where((item) => item.key == key).firstOrNull;
    return token?.value.toString();
  }

  void _setFilter(String key, String label, String value) {
    if (value == 'ALL' || value.isEmpty) {
      _queryController.removeFilterKey(key);
      return;
    }
    _queryController.addFilter(
      UnifiedFilterToken(
        key: key,
        label: label,
        value: value,
        valueLabel: value,
      ),
    );
  }

  Future<void> _deleteExpense(
    ExpensesController controller,
    ExpenseModel expense,
  ) async {
    if (!await PermissionAction.require(context, 'accounting.delete')) return;
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'حذف المصروف',
      message:
          'سيتم حذف المصروف وعكس حركة الصندوق والقيد المحاسبي المرتبط به. هل تريد المتابعة؟',
      confirmLabel: 'حذف المصروف',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await controller.deleteExpense(expense.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حذف المصروف أو عكس القيد المرتبط.',
              englishFallback:
                  'Unable to delete the expense or reverse its journal entry.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExpensesController>();
    final queryState = _queryController.state;
    final currency = _filterValue(queryState, 'currency') ?? 'ALL';
    final category = _filterValue(queryState, 'category') ?? 'ALL';

    final filtered = UnifiedFilterEngine.apply<ExpenseModel>(
      controller.expenses,
      criteria: UnifiedFilterCriteria(
        searchText: queryState.search,
        currencies: currency == 'ALL' ? const <String>{} : <String>{currency},
        types: category == 'ALL' ? const <String>{} : <String>{category},
      ),
      adapter: UnifiedFilterAdapter<ExpenseModel>(
        searchableText: (expense) => <Object?>[
          expense.id,
          expense.title,
          expense.category,
          expense.notes,
          expense.postingStatus,
          expense.approvalStatus,
        ],
        type: (expense) => expense.category,
        currency: (expense) => expense.currency,
        status: (expense) => expense.postingStatus,
        date: (expense) => DateTime.tryParse(expense.date),
      ),
    );
    final categories =
        controller.expenses.map((e) => e.category).toSet().toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await showAppWorkspaceDialog<void>(
                    context: context,
                    child: const AddExpensePage(),
                  );
                  if (mounted) await controller.loadExpenses();
                },
                icon: const Icon(Icons.add),
                label: AppText(
                  context.l10n.isArabic ? 'إضافة مصروف' : 'Add expense',
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: _queryController.setSearch,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: AppTranslation.translate('بحث المصروفات'),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: currency,
                items: const [
                  DropdownMenuItem(value: 'ALL', child: AppText('كل العملات')),
                  DropdownMenuItem(value: 'USD', child: AppText('USD')),
                  DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                ],
                onChanged: (v) => _setFilter(
                  'currency',
                  context.l10n.isArabic ? 'العملة' : 'Currency',
                  v ?? 'ALL',
                ),
              ),
              DropdownButton<String>(
                value: category,
                items: [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: AppText(AppTranslation.translate('كل التصنيفات')),
                  ),
                  ...categories.map(
                    (c) => DropdownMenuItem(value: c, child: AppText(c)),
                  ),
                ],
                onChanged: (v) => _setFilter(
                  'category',
                  context.l10n.isArabic ? 'التصنيف' : 'Category',
                  v ?? 'ALL',
                ),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.all(12),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.money_off)),
            title: AppText(
              context.l10n.isArabic ? 'إجمالي المصاريف' : 'Total expenses',
            ),
            subtitle: AppText(
              MoneyFormatter.format(controller.totalAmount),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Expanded(
          child: controller.isLoading
              ? KajFinanceState(
                  icon: Icons.sync_rounded,
                  title: context.l10n.isArabic
                      ? 'جارٍ تحميل المصاريف'
                      : 'Loading expenses',
                  message: context.l10n.isArabic
                      ? 'تتم مزامنة المصاريف والقيود المرتبطة.'
                      : 'Synchronizing expenses and linked journal entries.',
                )
              : controller.loadError != null
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, size: 44),
                            const SizedBox(height: 12),
                            AppText(
                              AppTranslation.translate('تعذر تحميل المصروفات'),
                            ),
                            const SizedBox(height: 8),
                            AppText(controller.loadError!),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: controller.loadExpenses,
                              icon: const Icon(Icons.refresh),
                              label: const AppText('إعادة المحاولة'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : filtered.isEmpty
              ? KajFinanceState(
                  icon: Icons.receipt_long_outlined,
                  title: context.l10n.isArabic
                      ? 'لا توجد مصاريف'
                      : 'No expenses',
                  message: context.l10n.isArabic
                      ? 'أضف أول مصروف لبدء المتابعة المالية.'
                      : 'Add the first expense to begin financial tracking.',
                )
              : IncrementalListView(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final ExpenseModel expense = filtered[index];

                    return ExpenseCard(
                      expense: expense,
                      onDelete:
                          PermissionAction.allowed(context, 'accounting.delete')
                          ? () => _deleteExpense(controller, expense)
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
