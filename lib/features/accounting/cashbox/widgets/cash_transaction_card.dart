import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class CashTransactionCard extends StatelessWidget {
  const CashTransactionCard({
    super.key,
    required this.transaction,
    required this.onEdit,
    this.onDelete,
    required this.onView,
    required this.onPrint,
  });

  final CashTransactionModel transaction;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onView;
  final VoidCallback onPrint;

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'cashbox',
    field: field,
    viewPermission: 'accounting.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final isReceipt = transaction.isReceipt;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: isReceipt
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.12),
              child: Icon(
                isReceipt ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: isReceipt ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FieldPermissionVisibility(
                          resource: 'cashbox',
                          field: 'purpose',
                          viewPermission: 'accounting.view',
                          child: AppText(
                            transaction.category,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      FieldPermissionVisibility(
                        resource: 'cashbox',
                        field: 'amount',
                        viewPermission: 'accounting.view',
                        child: AppText(
                          '${isReceipt ? '+' : '-'}${MoneyFormatter.withCurrency(transaction.amount, transaction.currency)}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isReceipt
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      FieldPermissionVisibility(
                        resource: 'cashbox',
                        field: 'documentNumber',
                        viewPermission: 'accounting.view',
                        child: _detail(
                          Icons.receipt_long_outlined,
                          transaction.voucherNumber,
                        ),
                      ),
                      FieldPermissionVisibility(
                        resource: 'cashbox',
                        field: 'operationalDate',
                        viewPermission: 'accounting.view',
                        child: _detail(
                          Icons.calendar_today_outlined,
                          _date(transaction.transactionDate),
                        ),
                      ),
                      _field(
                        'paymentMethod',
                        _detail(
                          Icons.account_balance_wallet_outlined,
                          _paymentMethodLabel(transaction.paymentMethod),
                        ),
                      ),
                      if ((transaction.partyName ?? '').trim().isNotEmpty)
                        FieldPermissionVisibility(
                          resource: 'cashbox',
                          field: 'partyName',
                          viewPermission: 'accounting.view',
                          child: _detail(
                            Icons.person_outline,
                            transaction.partyName!,
                          ),
                        ),
                      if ((transaction.referenceType ?? '').trim().isNotEmpty ||
                          (transaction.referenceId ?? '').trim().isNotEmpty)
                        _field(
                          'reference',
                          _detail(
                            Icons.link_outlined,
                            [transaction.referenceType, transaction.referenceId]
                                .where(
                                  (value) => (value ?? '').trim().isNotEmpty,
                                )
                                .join(' • '),
                          ),
                        ),
                      if ((transaction.journalEntryId ?? '').trim().isNotEmpty)
                        _field(
                          'journalEntryId',
                          _detail(
                            Icons.menu_book_outlined,
                            transaction.journalEntryId!,
                          ),
                        ),
                      _field(
                        'auditMetadata',
                        _detail(
                          Icons.history_outlined,
                          transaction.updatedAt == null
                              ? _date(transaction.transactionDate)
                              : '${_date(transaction.transactionDate)} → ${_date(transaction.updatedAt!)}',
                        ),
                      ),
                    ],
                  ),
                  if ((transaction.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    FieldPermissionVisibility(
                      resource: 'cashbox',
                      field: 'notes',
                      viewPermission: 'accounting.view',
                      child: AppText(
                        transaction.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'view') onView();
                if (value == 'print') onPrint();
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'print',
                  child: Row(
                    children: [
                      Icon(Icons.print_outlined),
                      SizedBox(width: 10),
                      AppText('طباعة السند'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.visibility_outlined),
                      SizedBox(width: 10),
                      AppText('عرض التفاصيل'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined),
                      SizedBox(width: 10),
                      AppText('تعديل'),
                    ],
                  ),
                ),
                if (onDelete != null)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 10),
                        AppText('حذف', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: Colors.grey.shade700),
        const SizedBox(width: 5),
        AppText(value, style: TextStyle(color: Colors.grey.shade800)),
      ],
    );
  }

  String _paymentMethodLabel(String value) {
    switch (value) {
      case 'bank_transfer':
        return AppTranslation.translate('تحويل مصرفي');
      case 'card':
        return AppTranslation.translate('بطاقة');
      case 'cheque':
        return AppTranslation.translate('صك');
      default:
        return AppTranslation.translate('نقدي');
    }
  }

  String _date(DateTime value) {
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  }
}
