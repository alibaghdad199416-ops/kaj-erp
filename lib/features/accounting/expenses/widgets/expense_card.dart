import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class ExpenseCard extends StatelessWidget {
  const ExpenseCard({super.key, required this.expense, this.onDelete});

  final ExpenseModel expense;
  final VoidCallback? onDelete;

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'expenses',
    field: field,
    viewPermission: 'accounting.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final scheme = Theme.of(context).colorScheme;
        final amount = _field(
          'amount',
          AppText(
            MoneyFormatter.format(expense.amount, currency: expense.currency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        );
        final delete = onDelete == null
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: context.l10n.isArabic
                    ? 'حذف المصروف'
                    : 'Delete expense',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                onPressed: onDelete,
              );

        final identity = Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AppText(
                expense.category.isNotEmpty ? expense.category[0] : '?',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FieldPermissionVisibility(
                    resource: 'expenses',
                    field: 'name',
                    viewPermission: 'accounting.view',
                    child: AppText(
                      expense.title,
                      maxLines: desktop ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      _field(
                        'category',
                        AppText(
                          expense.category,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      _field(
                        'operationalDate',
                        AppText(
                          expense.date,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        final statuses = Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _field(
              'postingStatus',
              _StatusPill(
                label: context.l10n.isArabic
                    ? 'الترحيل: ${expense.postingStatus}'
                    : 'Posting: ${expense.postingStatus}',
              ),
            ),
            _field(
              'approvalStatus',
              _StatusPill(
                label: context.l10n.isArabic
                    ? 'الاعتماد: ${expense.approvalStatus}'
                    : 'Approval: ${expense.approvalStatus}',
              ),
            ),
          ],
        );

        final converted = _field(
          'convertedAmounts',
          AppText(
            'USD ${MoneyFormatter.format(expense.amountUsd, currency: 'USD')}  •  IQD ${MoneyFormatter.format(expense.amountIqd, currency: 'IQD')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        );

        return Container(
          key: ValueKey(
            desktop ? 'expense-desktop-row' : 'expense-compact-column',
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 5, 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .68),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: desktop
              ? Row(
                  children: [
                    SizedBox(width: 300, child: identity),
                    const SizedBox(width: 12),
                    Expanded(child: statuses),
                    const SizedBox(width: 12),
                    SizedBox(width: 255, child: converted),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 135,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: amount,
                      ),
                    ),
                    delete,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 7),
                    statuses,
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: converted),
                        const SizedBox(width: 8),
                        amount,
                        delete,
                      ],
                    ),
                    if (expense.notes != null &&
                        expense.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _field(
                        'notes',
                        AppText(
                          expense.notes!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AppText(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
