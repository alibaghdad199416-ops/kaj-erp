import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/accounting/expenses/models/expense_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;

  final VoidCallback? onDelete;

  const ExpenseCard({super.key, required this.expense, this.onDelete});

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'expenses',
    field: field,
    viewPermission: 'accounting.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: AppText(
            expense.category.isNotEmpty ? expense.category[0] : '?',
          ),
        ),
        title: FieldPermissionVisibility(
          resource: 'expenses',
          field: 'name',
          viewPermission: 'accounting.view',
          child: AppText(
            expense.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldPermissionVisibility(
              resource: 'expenses',
              field: 'category',
              viewPermission: 'accounting.view',
              child: AppText(expense.category),
            ),
            FieldPermissionVisibility(
              resource: 'expenses',
              field: 'operationalDate',
              viewPermission: 'accounting.view',
              child: AppText(expense.date),
            ),
            FieldPermissionVisibility(
              resource: 'expenses',
              field: 'postingStatus',
              viewPermission: 'accounting.view',
              child: AppText('حالة الترحيل: ${expense.postingStatus}'),
            ),
            FieldPermissionVisibility(
              resource: 'expenses',
              field: 'approvalStatus',
              viewPermission: 'accounting.view',
              child: AppText('حالة الاعتماد: ${expense.approvalStatus}'),
            ),
            if (expense.notes != null && expense.notes!.isNotEmpty)
              FieldPermissionVisibility(
                resource: 'expenses',
                field: 'notes',
                viewPermission: 'accounting.view',
                child: AppText(expense.notes!),
              ),
            _field(
              'convertedAmounts',
              AppText(
                'USD ${MoneyFormatter.format(expense.amountUsd, currency: 'USD')} • IQD ${MoneyFormatter.format(expense.amountIqd, currency: 'IQD')}',
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FieldPermissionVisibility(
              resource: 'expenses',
              field: 'amount',
              viewPermission: 'accounting.view',
              child: AppText(
                MoneyFormatter.format(
                  expense.amount,
                  currency: expense.currency,
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: AppTranslation.translate('حذف المصروف'),
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
