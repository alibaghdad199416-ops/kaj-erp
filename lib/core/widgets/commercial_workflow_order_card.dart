import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/localization/operational_status_label.dart';
import 'package:quality_line_erp/core/widgets/app_module_action_icon.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

class CommercialWorkflowAction {
  const CommercialWorkflowAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool primary;
}

class CommercialWorkflowOrderCard extends StatelessWidget {
  const CommercialWorkflowOrderCard({
    super.key,
    required this.order,
    required this.purchase,
    required this.partnerLabel,
    required this.partnerName,
    required this.actions,
    required this.onDetails,
    this.busy = false,
  });

  final Map<String, Object?> order;
  final bool purchase;
  final String partnerLabel;
  final String partnerName;
  final List<CommercialWorkflowAction> actions;
  final VoidCallback onDetails;
  final bool busy;

  String _value(Object? value) {
    if (value == null) return '—';
    if (value is num) return NumberFormat('#,##0.##').format(value);
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  Object? _first(List<String> keys) {
    for (final key in keys) {
      final value = order[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  String _statusLabel(Object? value) => operationalStatusLabel(value);

  String _dateTime(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null
        ? _value(value)
        : DateFormat('yyyy/MM/dd  HH:mm').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final orderNumber = _value(
      _first(const ['orderNumber', 'order_number', 'number']),
    );
    final ar = context.l10n.isArabic;
    String t(String arText, String enText) => ar ? arText : enText;
    final documentTitle = purchase
        ? t('أمر شراء', 'Purchase Order')
        : t('أمر بيع', 'Sales Order');
    final logisticsNumber = _value(
      _first(
        purchase
            ? const ['receiptNumber', 'receipt_number', 'logisticsNumber']
            : const ['deliveryNumber', 'delivery_number', 'logisticsNumber'],
      ),
    );
    final invoiceNumber = _value(
      _first(const ['invoiceNumber', 'invoice_number']),
    );
    final journalNumber = _value(
      _first(const [
        'journalEntryNumber',
        'journal_entry_number',
        'journalNumber',
      ]),
    );
    final hasInvoice = invoiceNumber != '—';
    final paidAmount = _value(
      _first(const [
        'invoicePaid',
        'invoice_paid',
        'paidAmount',
        'paid_amount',
      ]),
    );
    final remainingAmount = _value(
      _first(const [
        'invoiceRemaining',
        'invoice_remaining',
        'remainingAmount',
        'remaining_amount',
      ]),
    );
    final paymentStatus = _statusLabel(
      _first(const ['paymentStatus', 'payment_status']),
    );
    final accountingOwner =
        _first(const ['accountingOwner', 'accounting_owner'])?.toString() ==
            'invoice'
        ? t('الفاتورة', 'Invoice')
        : '—';
    final status = _statusLabel(
      _first(const ['status', 'orderStatus', 'order_status']),
    );
    final logistics = _statusLabel(
      _first(const [
        'deliveryStatus',
        'delivery_status',
        'receiptStatus',
        'receipt_status',
      ]),
    );
    final invoice = _statusLabel(
      _first(const ['invoiceStatus', 'invoice_status']),
    );
    final currency = _value(
      _first(const ['currency', 'currencyCode', 'currency_code']),
    );
    final total = _value(
      _first(const [
        'total',
        'grandTotal',
        'grand_total',
        'netTotal',
        'net_total',
      ]),
    );
    final createdAt = _dateTime(
      _first(const ['createdAt', 'created_at', 'effectiveAt', 'effective_at']),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: KajSurface(
        onTap: busy ? null : onDetails,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 10),
        accent: purchase
            ? KajDesignTokens.champagne
            : KajDesignTokens.electricBlue,
        showShadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: LinearGradient(
                      colors: purchase
                          ? <Color>[
                              KajDesignTokens.champagne.withValues(alpha: .20),
                              KajDesignTokens.champagne.withValues(alpha: .06),
                            ]
                          : <Color>[
                              KajDesignTokens.electricBlue.withValues(
                                alpha: .22,
                              ),
                              KajDesignTokens.electricBlue.withValues(
                                alpha: .06,
                              ),
                            ],
                    ),
                    border: Border.all(
                      color:
                          (purchase
                                  ? KajDesignTokens.champagne
                                  : KajDesignTokens.electricBlue)
                              .withValues(alpha: .32),
                    ),
                  ),
                  child: Icon(
                    purchase
                        ? Icons.shopping_cart_checkout_rounded
                        : Icons.receipt_long_rounded,
                    size: 20,
                    color: purchase
                        ? KajDesignTokens.champagne
                        : KajDesignTokens.electricBlue,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AppText(
                        ar
                            ? '$documentTitle رقم $orderNumber'
                            : '$documentTitle $orderNumber',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppText(
                        '$partnerLabel: $partnerName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _Status(label: status),
              ],
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                _Metric(
                  icon: Icons.request_quote_outlined,
                  label: '${t('الفاتورة', 'Invoice')} $invoice',
                  value: invoiceNumber,
                ),
                _Metric(
                  icon: Icons.inventory_2_outlined,
                  label: purchase
                      ? '${t('إشعار الاستلام', 'Receipt')} • $logistics'
                      : '${t('إذن التجهيز', 'Delivery')} • $logistics',
                  value: logisticsNumber,
                ),
                _Metric(
                  icon: Icons.account_balance_outlined,
                  label:
                      '${t('القيد المحاسبي', 'Accounting entry')} • ${t('من', 'from')} $accountingOwner',
                  value: journalNumber == '—'
                      ? (hasInvoice
                            ? t('غير مرحّل', 'Not posted')
                            : t('لا توجد فاتورة', 'No invoice'))
                      : journalNumber,
                ),
                _Metric(
                  icon: Icons.payments_outlined,
                  label: hasInvoice
                      ? '${t('حالة الدفع', 'Payment status')} • $paymentStatus'
                      : t('الدفع بعد الفاتورة', 'Payment after invoicing'),
                  value:
                      '$paidAmount / ${t('متبقي', 'Remaining')} $remainingAmount $currency',
                ),
                _Metric(
                  icon: Icons.schedule_rounded,
                  label: AppTranslation.translate('التاريخ'),
                  value: createdAt,
                ),
                _Metric(
                  icon: Icons.payments_outlined,
                  label: AppTranslation.translate('الإجمالي'),
                  value: '$total $currency',
                  emphasis: true,
                ),
              ],
            ),
            const SizedBox(height: 9),
            Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .55),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                if (busy)
                  const SizedBox.square(
                    dimension: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  _TinyAction(
                    label: AppTranslation.translate('التفاصيل'),
                    icon: Icons.visibility_outlined,
                    onPressed: onDetails,
                  ),
                ...actions.map(
                  (action) => _TinyAction(
                    label: action.label,
                    icon: action.icon,
                    onPressed: busy ? null : action.onPressed,
                    destructive: action.destructive,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 124),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: emphasis
            ? KajDesignTokens.electricBlue.withValues(alpha: .08)
            : scheme.surfaceContainerHighest.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: emphasis
              ? KajDesignTokens.electricBlue.withValues(alpha: .24)
              : scheme.outlineVariant.withValues(alpha: .65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: emphasis
                ? KajDesignTokens.electricBlue
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: emphasis ? 11.5 : 10.5,
                    fontWeight: FontWeight.w900,
                    color: emphasis ? KajDesignTokens.electricBlue : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: KajDesignTokens.success.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: KajDesignTokens.success.withValues(alpha: .28)),
    ),
    child: AppText(
      label,
      style: const TextStyle(
        fontSize: 9.5,
        color: KajDesignTokens.success,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _TinyAction extends StatelessWidget {
  const _TinyAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AppModuleActionIcon(
    tooltip: AppTranslation.translate(label),
    icon: icon,
    color: KajDesignTokens.electricBlue,
    destructive: destructive,
    onPressed: onPressed,
  );
}
