import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/localization/operational_status_label.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/features/accounting/installments/controllers/installments_controller.dart';
import 'package:quality_line_erp/features/accounting/installments/models/installment_model.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({
    super.key,
    this.embedded = false,
    this.continuous = false,
  });

  final bool embedded;
  final bool continuous;

  @override
  State<InstallmentsPage> createState() => _InstallmentsPageState();
}

class _InstallmentsPageState extends State<InstallmentsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (!mounted) return;
        await context.read<InstallmentsController>().loadInstallments();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InstallmentsController>();
    final isArabic = context.l10n.isArabic;
    final access = context.watch<AccessController>();
    bool can(String field) => access.canViewField(
      'installments',
      field,
      viewPermission: 'installments.view',
    );

    if (controller.isLoading) {
      return Center(
        child: KajFinanceState(
          icon: Icons.sync_rounded,
          title: isArabic ? 'جارٍ تحميل الأقساط' : 'Loading installments',
          message: isArabic
              ? 'تتم مزامنة الاستحقاقات والدفعات الحالية.'
              : 'Synchronizing current schedules and payments.',
        ),
      );
    }

    final metrics = <KajFinanceMetricData>[
      if (can('installmentNo'))
        KajFinanceMetricData(
          label: isArabic ? 'عدد الأقساط' : 'Installments',
          value: controller.totalInstallments.toString(),
          icon: Icons.list_alt_outlined,
          accent: KajDesignTokens.electricBlue,
        ),
      if (can('amount'))
        KajFinanceMetricData(
          label: isArabic ? 'إجمالي المبلغ' : 'Total amount',
          value: CurrencyTotalsFormatter.format(
            controller.totalAmountByCurrency,
          ),
          icon: Icons.account_balance_wallet_outlined,
          accent: KajDesignTokens.champagneGold,
        ),
      if (can('paidAmount'))
        KajFinanceMetricData(
          label: isArabic ? 'المدفوع' : 'Paid',
          value: CurrencyTotalsFormatter.format(controller.totalPaidByCurrency),
          icon: Icons.check_circle_outline,
          accent: KajDesignTokens.staticGreen,
        ),
      if (can('remainingAmount'))
        KajFinanceMetricData(
          label: isArabic ? 'المتبقي' : 'Outstanding',
          value: CurrencyTotalsFormatter.format(
            controller.totalRemainingByCurrency,
          ),
          icon: Icons.pending_actions_outlined,
          accent: KajDesignTokens.warningAmber,
        ),
    ];

    if (widget.embedded) {
      final scheme = Theme.of(context).colorScheme;
      final metricStrip = _compactMetricStrip(metrics);
      final schedule = controller.installments.isEmpty
          ? Center(
              child: KajFinanceState(
                icon: Icons.event_available_outlined,
                title: isArabic ? 'لا توجد أقساط' : 'No installments',
                message: isArabic
                    ? 'لا توجد استحقاقات مالية مسجلة حاليًا.'
                    : 'There are no registered financial schedules yet.',
              ),
            )
          : ListView.separated(
              key: const ValueKey('installments-full-height-list'),
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 8),
              itemCount: controller.installments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, index) => _installmentRow(
                controller.installments[index],
                isArabic: isArabic,
                can: can,
              ),
            );

      if (widget.continuous) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            metricStrip,
            if (metrics.isNotEmpty) const SizedBox(height: 8),
            _schedule(
              controller: controller,
              isArabic: isArabic,
              can: can,
              embedded: true,
            ),
          ],
        );
      }

      return Column(
        key: const ValueKey('installments-full-height-column'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          metricStrip,
          if (metrics.isNotEmpty) const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.view_timeline_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              AppText(
                isArabic
                    ? 'جدول الاستحقاقات والدفعات'
                    : 'Installment & payment schedule',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (can('status')) ...[
                _CountPill(
                  label: isArabic ? 'مدفوع' : 'Paid',
                  value: controller.paidCount,
                ),
                const SizedBox(width: 6),
                _CountPill(
                  label: isArabic ? 'جزئي' : 'Partial',
                  value: controller.partialCount,
                ),
                const SizedBox(width: 6),
                _CountPill(
                  label: isArabic ? 'غير مدفوع' : 'Unpaid',
                  value: controller.unpaidCount,
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
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
                child: schedule,
              ),
            ),
          ),
        ],
      );
    }

    return KajFinanceWorkspace(
      eyebrow: isArabic ? 'إدارة الاستحقاقات' : 'RECEIVABLES CONTROL',
      title: isArabic ? 'الأقساط والدفعات' : 'Installments & Payments',
      subtitle: isArabic
          ? 'متابعة الاستحقاقات والمدفوع والمتبقي من شاشة مالية موحدة.'
          : 'Track due dates, paid amounts and outstanding balances from one workspace.',
      icon: Icons.calendar_month_outlined,
      metrics: metrics,
      child: _schedule(
        controller: controller,
        isArabic: isArabic,
        can: can,
        embedded: false,
      ),
    );
  }

  Widget _compactMetricStrip(List<KajFinanceMetricData> metrics) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      key: const ValueKey('installments-responsive-metric-strip'),
      builder: (context, constraints) {
        const gap = 8.0;
        const minWidth = 190.0;
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, 4);
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: CompactMetricPill(
                    icon: metric.icon,
                    label: metric.label,
                    value: metric.value,
                    color: metric.accent,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _installmentRow(
    InstallmentModel item, {
    required bool isArabic,
    required bool Function(String field) can,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final scheme = Theme.of(context).colorScheme;
        final title = can('installmentNo')
            ? AppText(
                isArabic
                    ? 'القسط ${item.installmentNo}'
                    : 'Installment ${item.installmentNo}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : AppText(isArabic ? 'قسط' : 'Installment');
        final status = can('status')
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .65),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: AppText(
                  operationalStatusLabel(item.status),
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              )
            : const SizedBox.shrink();

        Widget fact(String label, String value, {bool emphasize = false}) =>
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  '$label: ',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            );

        final financialFacts = <Widget>[
          if (can('amount'))
            fact(
              isArabic ? 'المبلغ' : 'Amount',
              MoneyFormatter.format(item.amount, currency: item.currencyCode),
            ),
          if (can('paidAmount'))
            fact(
              isArabic ? 'المدفوع' : 'Paid',
              MoneyFormatter.format(
                item.paidAmount,
                currency: item.currencyCode,
              ),
            ),
          if (can('remainingAmount'))
            fact(
              isArabic ? 'المتبقي' : 'Remaining',
              MoneyFormatter.format(
                item.remainingAmount,
                currency: item.currencyCode,
              ),
              emphasize: true,
            ),
        ];

        final dateFacts = <Widget>[
          if (can('dueDate'))
            fact(
              isArabic ? 'الاستحقاق' : 'Due',
              item.dueDate.toLocal().toString().split(' ').first,
            ),
          if (can('paymentDate') && item.paymentDate != null)
            fact(
              isArabic ? 'الدفع' : 'Payment',
              item.paymentDate!.toLocal().toString().split(' ').first,
            ),
        ];

        return Container(
          key: ValueKey(
            desktop ? 'installment-desktop-row' : 'installment-compact-column',
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .62),
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: desktop
              ? Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: .55,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: can('installmentNo')
                                ? AppText('${item.installmentNo}')
                                : const Icon(Icons.payments_outlined, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: title),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: dateFacts,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: financialFacts,
                      ),
                    ),
                    const SizedBox(width: 12),
                    status,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: title),
                        status,
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 10, runSpacing: 4, children: dateFacts),
                    const SizedBox(height: 4),
                    Wrap(spacing: 10, runSpacing: 4, children: financialFacts),
                    if (can('notes') && item.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      AppText(
                        item.notes.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _schedule({
    required InstallmentsController controller,
    required bool isArabic,
    required bool Function(String field) can,
    required bool embedded,
  }) {
    if (controller.installments.isEmpty) {
      return KajFinanceState(
        icon: Icons.event_available_outlined,
        title: isArabic ? 'لا توجد أقساط' : 'No installments',
        message: isArabic
            ? 'لا توجد استحقاقات مالية مسجلة حاليًا.'
            : 'There are no registered financial schedules yet.',
      );
    }

    final list = ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: controller.installments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 5),
      itemBuilder: (context, index) => _installmentRow(
        controller.installments[index],
        isArabic: isArabic,
        can: can,
      ),
    );

    if (embedded) return list;

    return KajFinanceSection(
      title: isArabic ? 'جدول الاستحقاقات' : 'Payment schedule',
      subtitle: isArabic
          ? 'قائمة مرتبة حسب رقم القسط وتاريخ الاستحقاق.'
          : 'Ordered by installment number and due date.',
      icon: Icons.view_timeline_outlined,
      child: Padding(padding: const EdgeInsets.all(8), child: list),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AppText(
        '$label: $value',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
