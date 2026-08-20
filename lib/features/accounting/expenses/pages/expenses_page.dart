import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/core/widgets/incremental_list_view.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/features/accounting/expenses/controllers/expenses_controller.dart';
import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';
import 'package:quality_line_erp/features/accounting/expenses/pages/add_expense_page.dart';
import 'package:quality_line_erp/features/accounting/expenses/widgets/expense_card.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({
    super.key,
    this.embedded = false,
    this.continuous = false,
  });

  final bool embedded;
  final bool continuous;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  String _query = '';
  String _currency = 'ALL';
  String _category = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<ExpensesController>().loadExpenses());
      }
    });
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

  Future<void> _openAddExpense(ExpensesController controller) async {
    await showAppWorkspaceDialog<void>(
      context: context,
      child: const AddExpensePage(),
    );
    if (mounted) await controller.loadExpenses();
  }

  Map<String, double> _totalsByCurrency(List<ExpenseModel> expenses) {
    final totals = <String, double>{};
    for (final expense in expenses) {
      final currency = expense.currency.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExpensesController>();
    final ar = context.l10n.isArabic;

    final filtered = UnifiedFilterEngine.apply<ExpenseModel>(
      controller.expenses,
      criteria: UnifiedFilterCriteria(
        searchText: _query,
        currencies: _currency == 'ALL' ? const <String>{} : <String>{_currency},
        types: _category == 'ALL' ? const <String>{} : <String>{_category},
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
    final visibleTotals = _totalsByCurrency(filtered);

    final toolbar = LayoutBuilder(
      key: const ValueKey('expenses-horizontal-toolbar'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        final add = FilledButton.icon(
          onPressed: () => _openAddExpense(controller),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(142, 44),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: AppText(ar ? 'إضافة مصروف' : 'Add expense'),
        );
        final search = TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: ar
                ? 'بحث بالعنوان أو التصنيف أو الحالة'
                : 'Search title, category or status',
            border: const OutlineInputBorder(),
          ),
        );
        final currency = DropdownButtonFormField<String>(
          initialValue: _currency,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: ar ? 'العملة' : 'Currency',
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'ALL',
              child: AppText(ar ? 'كل العملات' : 'All currencies'),
            ),
            const DropdownMenuItem(value: 'USD', child: AppText('USD')),
            const DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
          ],
          onChanged: (value) => setState(() => _currency = value ?? 'ALL'),
        );
        final category = DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            labelText: ar ? 'التصنيف' : 'Category',
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'ALL',
              child: AppText(ar ? 'كل التصنيفات' : 'All categories'),
            ),
            ...categories.map(
              (value) => DropdownMenuItem(value: value, child: AppText(value)),
            ),
          ],
          onChanged: (value) => setState(() => _category = value ?? 'ALL'),
        );

        if (wide) {
          return Row(
            children: [
              add,
              const SizedBox(width: 8),
              Expanded(child: search),
              const SizedBox(width: 8),
              SizedBox(width: 154, child: currency),
              const SizedBox(width: 8),
              SizedBox(width: 210, child: category),
            ],
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            add,
            SizedBox(
              width: constraints.maxWidth >= 720 ? 360 : constraints.maxWidth,
              child: search,
            ),
            SizedBox(width: 160, child: currency),
            SizedBox(width: 210, child: category),
          ],
        );
      },
    );

    final metrics = Wrap(
      key: const ValueKey('expenses-compact-metrics'),
      spacing: 8,
      runSpacing: 8,
      children: [
        CompactMetricPill(
          icon: Icons.receipt_long_outlined,
          label: ar ? 'النتائج الظاهرة' : 'Visible expenses',
          value: '${filtered.length}',
        ),
        CompactMetricPill(
          icon: Icons.payments_outlined,
          label: ar ? 'إجمالي النتائج' : 'Visible total',
          value: CurrencyTotalsFormatter.format(visibleTotals),
        ),
      ],
    );

    final result = controller.isLoading
        ? KajFinanceState(
            icon: Icons.sync_rounded,
            title: ar ? 'جارٍ تحميل المصاريف' : 'Loading expenses',
            message: ar
                ? 'تتم مزامنة المصاريف والقيود المرتبطة.'
                : 'Synchronizing expenses and linked journal entries.',
          )
        : controller.loadError != null
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 34),
                      const SizedBox(height: 8),
                      AppText(
                        ar ? 'تعذر تحميل المصروفات' : 'Unable to load expenses',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        controller.loadError!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: controller.loadExpenses,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: AppText(ar ? 'إعادة المحاولة' : 'Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : filtered.isEmpty
        ? Center(
            child: KajFinanceState(
              icon: Icons.receipt_long_outlined,
              title: ar ? 'لا توجد مصاريف مطابقة' : 'No matching expenses',
              message: ar
                  ? 'غيّر المرشحات أو أضف أول مصروف.'
                  : 'Adjust the filters or add the first expense.',
            ),
          )
        : widget.continuous
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: filtered
                .map(
                  (expense) => ExpenseCard(
                    expense: expense,
                    onDelete:
                        PermissionAction.allowed(context, 'accounting.delete')
                        ? () => _deleteExpense(controller, expense)
                        : null,
                  ),
                )
                .toList(growable: false),
          )
        : IncrementalListView(
            key: const ValueKey('expenses-full-height-list'),
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 8),
            separatorBuilder: (_, _) => const SizedBox(height: 5),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final expense = filtered[index];
              return ExpenseCard(
                expense: expense,
                onDelete: PermissionAction.allowed(context, 'accounting.delete')
                    ? () => _deleteExpense(controller, expense)
                    : null,
              );
            },
          );

    final controls = <Widget>[
      toolbar,
      const SizedBox(height: 8),
      metrics,
      const SizedBox(height: 8),
    ];

    if (widget.continuous) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[...controls, result],
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('expenses-full-height-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...controls,
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: .72),
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: result,
            ),
          ),
        ),
      ],
    );
  }
}
