import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/localization/operational_status_label.dart';
import 'package:quality_line_erp/design_system/kaj_finance_stage7_components.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

import 'package:quality_line_erp/features/accounting/installments/controllers/installments_controller.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class InstallmentsPage extends StatefulWidget {
  const InstallmentsPage({super.key});

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
      return KajFinanceState(
        icon: Icons.sync_rounded,
        title: isArabic ? 'جارٍ تحميل الأقساط' : 'Loading installments',
        message: isArabic
            ? 'تتم مزامنة الاستحقاقات والدفعات الحالية.'
            : 'Synchronizing current schedules and payments.',
      );
    }

    return KajFinanceWorkspace(
      eyebrow: isArabic ? 'إدارة الاستحقاقات' : 'RECEIVABLES CONTROL',
      title: isArabic ? 'الأقساط والدفعات' : 'Installments & Payments',
      subtitle: isArabic
          ? 'متابعة الاستحقاقات والمدفوع والمتبقي من شاشة مالية موحدة.'
          : 'Track due dates, paid amounts and outstanding balances from one workspace.',
      icon: Icons.calendar_month_outlined,
      metrics: <KajFinanceMetricData>[
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
            value: CurrencyTotalsFormatter.format(
              controller.totalPaidByCurrency,
            ),
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
      ],
      child: controller.installments.isEmpty
          ? KajFinanceState(
              icon: Icons.event_available_outlined,
              title: isArabic ? 'لا توجد أقساط' : 'No installments',
              message: isArabic
                  ? 'لا توجد استحقاقات مالية مسجلة حاليًا.'
                  : 'There are no registered financial schedules yet.',
            )
          : KajFinanceSection(
              title: isArabic ? 'جدول الاستحقاقات' : 'Payment schedule',
              subtitle: isArabic
                  ? 'قائمة مرتبة حسب رقم القسط وتاريخ الاستحقاق.'
                  : 'Ordered by installment number and due date.',
              icon: Icons.view_timeline_outlined,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.installments.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = controller.installments[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    leading: can('installmentNo')
                        ? CircleAvatar(
                            child: AppText(item.installmentNo.toString()),
                          )
                        : null,
                    title: can('installmentNo')
                        ? AppText(
                            isArabic
                                ? 'القسط رقم ${item.installmentNo}'
                                : 'Installment ${item.installmentNo}',
                          )
                        : const AppText('قسط'),
                    subtitle: AppText(
                      [
                        if (can('dueDate'))
                          '${isArabic ? 'الاستحقاق' : 'Due'}: ${item.dueDate.toLocal().toString().split(' ').first}',
                        if (can('amount'))
                          '${isArabic ? 'المبلغ' : 'Amount'}: ${MoneyFormatter.format(item.amount, currency: item.currencyCode)}',
                        if (can('paidAmount'))
                          '${isArabic ? 'المدفوع' : 'Paid'}: ${MoneyFormatter.format(item.paidAmount, currency: item.currencyCode)}',
                        if (can('remainingAmount'))
                          '${isArabic ? 'المتبقي' : 'Remaining'}: ${MoneyFormatter.format(item.remainingAmount, currency: item.currencyCode)}',
                        if (can('paymentDate') && item.paymentDate != null)
                          '${isArabic ? 'تاريخ الدفع' : 'Payment date'}: ${item.paymentDate!.toLocal().toString().split(' ').first}',
                        if (can('notes') && item.notes.trim().isNotEmpty)
                          item.notes.trim(),
                      ].join(' • '),
                    ),
                    trailing: can('status')
                        ? Chip(
                            label: AppText(operationalStatusLabel(item.status)),
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }
}
