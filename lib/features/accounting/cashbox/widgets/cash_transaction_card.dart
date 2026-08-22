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
    final scheme = Theme.of(context).colorScheme;
    final isReceipt = transaction.isReceipt;
    final accent = isReceipt ? Colors.green.shade700 : Colors.red.shade700;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .78)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;
            if (desktop) {
              return _desktopLayout(context, accent, isReceipt);
            }
            return _compactLayout(context, accent, isReceipt);
          },
        ),
      ),
    );
  }

  Widget _desktopLayout(BuildContext context, Color accent, bool isReceipt) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('cash-transaction-desktop-row'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _directionIcon(accent, isReceipt),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FieldPermissionVisibility(
                resource: 'cashbox',
                field: 'purpose',
                viewPermission: 'accounting.view',
                child: AppText(
                  transaction.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 3),
              FieldPermissionVisibility(
                resource: 'cashbox',
                field: 'documentNumber',
                viewPermission: 'accounting.view',
                child: AppText(
                  transaction.voucherNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if ((transaction.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                FieldPermissionVisibility(
                  resource: 'cashbox',
                  field: 'notes',
                  viewPermission: 'accounting.view',
                  child: AppText(
                    transaction.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 5,
          child: Wrap(spacing: 13, runSpacing: 5, children: _details(context)),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 150, child: _amount(context, accent, isReceipt)),
        const SizedBox(width: 6),
        _actions(context),
      ],
    );
  }

  Widget _compactLayout(BuildContext context, Color accent, bool isReceipt) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('cash-transaction-compact-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _directionIcon(accent, isReceipt),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldPermissionVisibility(
                    resource: 'cashbox',
                    field: 'purpose',
                    viewPermission: 'accounting.view',
                    child: AppText(
                      transaction.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FieldPermissionVisibility(
                    resource: 'cashbox',
                    field: 'documentNumber',
                    viewPermission: 'accounting.view',
                    child: AppText(
                      transaction.voucherNumber,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _amount(context, accent, isReceipt),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 6, children: _details(context)),
        if ((transaction.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          FieldPermissionVisibility(
            resource: 'cashbox',
            field: 'notes',
            viewPermission: 'accounting.view',
            child: AppText(
              transaction.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
        const SizedBox(height: 5),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _actions(context),
        ),
      ],
    );
  }

  Widget _directionIcon(Color accent, bool isReceipt) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        isReceipt ? Icons.south_west_rounded : Icons.north_east_rounded,
        size: 18,
        color: accent,
      ),
    );
  }

  Widget _amount(BuildContext context, Color accent, bool isReceipt) {
    return FieldPermissionVisibility(
      resource: 'cashbox',
      field: 'amount',
      viewPermission: 'accounting.view',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AppText(
            transaction.currency.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppText(
            '${isReceipt ? '+' : '-'}${MoneyFormatter.withCurrency(transaction.amount, transaction.currency)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _details(BuildContext context) {
    final result = <Widget>[
      FieldPermissionVisibility(
        resource: 'cashbox',
        field: 'operationalDate',
        viewPermission: 'accounting.view',
        child: _detail(
          context,
          Icons.calendar_today_outlined,
          _date(transaction.transactionDate),
        ),
      ),
      _field(
        'paymentMethod',
        _detail(
          context,
          Icons.account_balance_wallet_outlined,
          _paymentMethodLabel(transaction.paymentMethod),
        ),
      ),
    ];

    if ((transaction.partyName ?? '').trim().isNotEmpty) {
      result.add(
        FieldPermissionVisibility(
          resource: 'cashbox',
          field: 'partyName',
          viewPermission: 'accounting.view',
          child: _detail(context, Icons.person_outline, transaction.partyName!),
        ),
      );
    }
    if ((transaction.referenceType ?? '').trim().isNotEmpty ||
        (transaction.referenceId ?? '').trim().isNotEmpty) {
      result.add(
        _field(
          'reference',
          _detail(
            context,
            Icons.link_outlined,
            [
              transaction.referenceType,
              transaction.referenceId,
            ].where((value) => (value ?? '').trim().isNotEmpty).join(' • '),
          ),
        ),
      );
    }
    if ((transaction.journalEntryId ?? '').trim().isNotEmpty) {
      result.add(
        _field(
          'journalEntryId',
          _detail(
            context,
            Icons.menu_book_outlined,
            transaction.journalEntryId!,
          ),
        ),
      );
    }
    result.add(
      _field(
        'auditMetadata',
        _detail(
          context,
          Icons.history_outlined,
          transaction.updatedAt == null
              ? _date(transaction.transactionDate)
              : '${_date(transaction.transactionDate)} → ${_date(transaction.updatedAt!)}',
        ),
      ),
    );
    return result;
  }

  Widget _actions(BuildContext context) {
    return Wrap(
      spacing: 1,
      children: [
        _actionButton(
          context,
          tooltip: context.l10n.isArabic ? 'عرض التفاصيل' : 'View details',
          icon: Icons.visibility_outlined,
          onPressed: onView,
        ),
        _actionButton(
          context,
          tooltip: context.l10n.isArabic ? 'طباعة السند' : 'Print voucher',
          icon: Icons.print_outlined,
          onPressed: onPrint,
        ),
        _actionButton(
          context,
          tooltip: context.l10n.isArabic ? 'تعديل' : 'Edit',
          icon: Icons.edit_outlined,
          onPressed: onEdit,
        ),
        if (onDelete != null)
          _actionButton(
            context,
            tooltip: context.l10n.isArabic ? 'حذف' : 'Delete',
            icon: Icons.delete_outline,
            onPressed: onDelete!,
            danger: true,
          ),
      ],
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: 18,
        color: danger ? Theme.of(context).colorScheme.error : null,
      ),
      onPressed: onPressed,
    );
  }

  Widget _detail(BuildContext context, IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: AppText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
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
