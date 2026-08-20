import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/localization/operational_status_label.dart';
import 'package:quality_line_erp/core/widgets/commercial_workflow_order_card.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';

/// Dense operational document table used by Sales and Purchases.
///
/// Status is informational. Only real workflow operations are exposed through
/// [actionsBuilder], so presentation-only states never become action buttons.
class CommercialWorkflowOrderTable extends StatefulWidget {
  const CommercialWorkflowOrderTable({
    super.key,
    required this.orders,
    required this.purchase,
    required this.actionsBuilder,
    required this.onDetails,
    required this.isBusy,
  });

  final List<Map<String, Object?>> orders;
  final bool purchase;
  final List<CommercialWorkflowAction> Function(Map<String, Object?> order)
  actionsBuilder;
  final void Function(Map<String, Object?> order) onDetails;
  final bool Function(Map<String, Object?> order) isBusy;

  @override
  State<CommercialWorkflowOrderTable> createState() =>
      _CommercialWorkflowOrderTableState();
}

class _CommercialWorkflowOrderTableState
    extends State<CommercialWorkflowOrderTable> {
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Object? _first(Map<String, Object?> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return value;
    }
    return null;
  }

  String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '—' : text;
  }

  String _amount(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    return number == null
        ? _text(value)
        : NumberFormat('#,##0.##').format(number);
  }

  String _dateTime(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null
        ? _text(value)
        : DateFormat('yyyy/MM/dd  HH:mm').format(parsed);
  }

  String _stage(Map<String, Object?> row, bool ar) {
    final orderStatus = _text(
      _first(row, const ['status', 'orderStatus', 'order_status']),
    ).toLowerCase();
    final logisticsStatus = _text(
      _first(
        row,
        widget.purchase
            ? const ['receiptStatus', 'receipt_status']
            : const ['deliveryStatus', 'delivery_status'],
      ),
    ).toLowerCase();
    final invoiceStatus = _text(
      _first(row, const ['invoiceStatus', 'invoice_status']),
    ).toLowerCase();
    final remaining = _first(row, const [
      'invoiceRemaining',
      'invoice_remaining',
      'remainingAmount',
    ]);
    final remainingValue = remaining is num
        ? remaining.toDouble()
        : double.tryParse('$remaining');

    if (invoiceStatus == 'approved' && (remainingValue ?? 1) <= 0) {
      return ar ? 'مدفوع' : 'Paid';
    }
    if (invoiceStatus == 'approved' || invoiceStatus == 'posted') {
      return ar ? 'مفوتر' : 'Invoiced';
    }
    if (logisticsStatus == 'approved' || logisticsStatus == 'posted') {
      return widget.purchase
          ? (ar ? 'مستلم مخزنياً' : 'Warehouse received')
          : (ar ? 'مجهز مخزنياً' : 'Warehouse delivered');
    }
    if (logisticsStatus == 'draft') {
      return widget.purchase
          ? (ar ? 'مسودة استلام' : 'Receipt draft')
          : (ar ? 'مسودة تجهيز' : 'Delivery draft');
    }
    if (orderStatus == 'approved' || orderStatus == 'partially_executed') {
      return ar ? 'أمر مصدق' : 'Order approved';
    }
    return operationalStatusLabel(orderStatus);
  }

  Widget _statusChip(BuildContext context, Map<String, Object?> order) {
    final ar = context.l10n.isArabic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _stage(order, ar),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _actions(BuildContext context, Map<String, Object?> order) {
    final actions = widget.actionsBuilder(order);
    final busy = widget.isBusy(order);
    final ar = context.l10n.isArabic;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : () => widget.onDetails(order),
          icon: const Icon(Icons.table_rows_outlined, size: 17),
          label: Text(ar ? 'التفاصيل والمواد' : 'Details & Items'),
        ),
        const SizedBox(width: 6),
        if (busy)
          const SizedBox(
            width: 28,
            height: 28,
            child: Padding(
              padding: EdgeInsets.all(5),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (actions.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: ar ? 'العمليات' : 'Actions',
            icon: const Icon(Icons.more_horiz_rounded),
            itemBuilder: (context) => [
              for (var index = 0; index < actions.length; index++)
                PopupMenuItem<int>(
                  value: index,
                  enabled: actions[index].onPressed != null,
                  child: Row(
                    children: [
                      Icon(
                        actions[index].icon,
                        size: 18,
                        color: actions[index].destructive
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          actions[index].label,
                          style: actions[index].destructive
                              ? TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onSelected: (index) => actions[index].onPressed?.call(),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arText, String enText) => ar ? arText : enText;

    DataColumn column(String arText, String enText, {bool numeric = false}) =>
        DataColumn(label: Text(t(arText, enText)), numeric: numeric);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 12),
      child: KajSurface(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) => Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 46,
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 62,
                    columnSpacing: 26,
                    horizontalMargin: 18,
                    columns: [
                      column('رقم الأمر', 'Order number'),
                      column('التاريخ والوقت', 'Date & time'),
                      column(
                        widget.purchase ? 'المجهز' : 'العميل',
                        widget.purchase ? 'Supplier' : 'Customer',
                      ),
                      column('أُدخل بواسطة', 'Created by'),
                      column('العملة', 'Currency'),
                      column('الإجمالي', 'Total amount', numeric: true),
                      column('مرحلة العمل', 'Workflow stage'),
                      column('العمليات', 'Actions'),
                    ],
                    rows: [
                      for (final order in widget.orders)
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                _text(
                                  _first(order, const [
                                    'orderNumber',
                                    'order_number',
                                    'number',
                                  ]),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _dateTime(
                                  _first(order, const [
                                    'orderDate',
                                    'effectiveAt',
                                    'effective_at',
                                    'createdAt',
                                    'created_at',
                                  ]),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _text(
                                  _first(
                                    order,
                                    widget.purchase
                                        ? const [
                                            'supplierName',
                                            'supplier_name',
                                          ]
                                        : const [
                                            'customerName',
                                            'customer_name',
                                          ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _text(
                                  _first(order, const [
                                    'createdByName',
                                    'createdBy',
                                    'created_by_name',
                                    'creatorName',
                                  ]),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _text(
                                  _first(order, const [
                                    'currency',
                                    'currencyCode',
                                    'currency_code',
                                  ]),
                                ),
                              ),
                            ),
                            DataCell(
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  _amount(
                                    _first(order, const [
                                      'total',
                                      'grandTotal',
                                      'grand_total',
                                      'netTotal',
                                    ]),
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(_statusChip(context, order)),
                            DataCell(_actions(context, order)),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
