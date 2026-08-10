import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_brand_motif.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_signature_components.dart';
import 'package:quality_line_erp/features/settings/reports/pages/reports_page.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

import 'package:quality_line_erp/features/dashboard/controllers/dashboard_controller.dart';
import 'package:quality_line_erp/features/dashboard/models/dashboard_model.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardController>();
    final dashboard = controller.dashboard;
    final userName = context.select<AccessController, String>(
      (access) => access.currentUser?.fullName ?? '',
    );
    final access = context.watch<AccessController>();
    bool can(String field) => access.canViewField(
      'dashboard',
      field,
      viewPermission: 'dashboard.view',
    );

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              final pagePadding = viewport.maxWidth < 700 ? 12.0 : 22.0;
              return RefreshIndicator(
                onRefresh: controller.loadDashboard,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    18,
                    pagePadding,
                    28,
                  ),
                  children: [
                    const SizedBox(height: 2),
                    KajSignaturePageHero(
                      eyebrow: context.l10n.isArabic
                          ? 'مركز القيادة التنفيذي'
                          : 'EXECUTIVE COMMAND CENTER',
                      title: context.l10n.isArabic
                          ? 'مرحباً بك${userName.isEmpty ? '' : '، $userName'}'
                          : 'Welcome${userName.isEmpty ? '' : ', $userName'}',
                      subtitle: context.l10n.isArabic
                          ? 'نظرة تنفيذية لحظية على المبيعات والمخزون والصيانة والالتزامات المالية.'
                          : 'A live executive view of sales, inventory, maintenance and financial commitments.',
                      icon: Icons.space_dashboard_outlined,
                      metrics: <KajSignatureMetricData>[
                        if (can('todaySales'))
                          KajSignatureMetricData(
                            label: context.l10n.isArabic
                                ? 'مبيعات اليوم'
                                : 'TODAY SALES',
                            value: CurrencyTotalsFormatter.format(
                              dashboard.todaySalesByCurrency,
                            ),
                            icon: Icons.trending_up_rounded,
                          ),
                        if (can('availableCars'))
                          KajSignatureMetricData(
                            label: context.l10n.isArabic
                                ? 'السيارات المتوفرة'
                                : 'AVAILABLE VEHICLES',
                            value: '${dashboard.availableCars}',
                            icon: Icons.directions_car_filled_outlined,
                            accent: KajDesignTokens.champagne,
                          ),
                        if (can('overdueInstallments'))
                          KajSignatureMetricData(
                            label: context.l10n.isArabic
                                ? 'أقساط متأخرة'
                                : 'OVERDUE INSTALLMENTS',
                            value: '${dashboard.overdueInstallments}',
                            icon: Icons.schedule_rounded,
                            accent: dashboard.overdueInstallments > 0
                                ? KajDesignTokens.warning
                                : KajDesignTokens.success,
                          ),
                      ],
                    ),
                    if (controller.isLoading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      _ErrorCard(message: controller.errorMessage ?? ''),
                    ],
                    const SizedBox(height: 18),
                    _KpiGrid(dashboard: dashboard),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 960;
                        final chart = can('salesTrend')
                            ? _SalesTrendPanel(
                                points: dashboard.salesTrend,
                                mixedCurrencies: _hasMultipleCurrencies(
                                  dashboard.totalSalesByCurrency,
                                ),
                              )
                            : const SizedBox.shrink();
                        final showInstallments =
                            can('overdueInstallments') &&
                            can('dueSoonInstallments') &&
                            can('outstandingInstallments') &&
                            can('upcomingInstallments');
                        final installments = showInstallments
                            ? _InstallmentsPanel(
                                overdueCount: dashboard.overdueInstallments,
                                dueSoonCount: dashboard.dueSoonInstallments,
                                outstandingByCurrency:
                                    dashboard.outstandingInstallmentsByCurrency,
                                items: dashboard.upcomingInstallments,
                              )
                            : const SizedBox.shrink();
                        if (stacked) {
                          return Column(
                            children: [
                              chart,
                              const SizedBox(height: 14),
                              installments,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: chart),
                            const SizedBox(width: 14),
                            Expanded(flex: 2, child: installments),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 960;
                        final fleet = _FleetPanel(dashboard: dashboard);
                        final activity = can('recentActivities')
                            ? _ActivityPanel(items: dashboard.recentActivities)
                            : const SizedBox.shrink();
                        if (stacked) {
                          return Column(
                            children: [
                              fleet,
                              const SizedBox(height: 14),
                              activity,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 2, child: fleet),
                            const SizedBox(width: 14),
                            Expanded(flex: 3, child: activity),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _StatusBar(dashboard: dashboard),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({
    required this.userName,
    required this.todaySales,
    required this.availableCars,
  });
  final String userName;
  final double todaySales;
  final int availableCars;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[
            const Color(0xFF152126),
            const Color(0xFF0A1114),
            KajDesignTokens.bronze.withValues(alpha: .72),
          ],
          stops: const <double>[0, .72, 1],
        ),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(
          color: KajDesignTokens.champagne.withValues(alpha: .24),
        ),
        boxShadow: KajDesignTokens.accentShadow(
          Theme.of(context).brightness,
          accent: KajDesignTokens.champagne,
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: KajBrandMotif(
              opacity: .12,
              alignment: AlignmentDirectional.centerEnd,
              accent: KajDesignTokens.champagne,
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              final intro = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    context.l10n.isArabic
                        ? 'مرحباً بك${userName.isEmpty ? '' : '، $userName'}'
                        : 'Welcome${userName.isEmpty ? '' : ', $userName'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    context.l10n.isArabic
                        ? 'ملخص تنفيذي لحظي لأعمال خط الجودة اليوم'
                        : 'Live executive overview of Khat Al-Jawda operations',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              );
              final summary = Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _BannerChip(
                    label: context.l10n.isArabic
                        ? 'مبيعات اليوم'
                        : 'Today sales',
                    value: _money(todaySales),
                  ),
                  _BannerChip(
                    label: context.l10n.isArabic
                        ? 'سيارات متوفرة'
                        : 'Available vehicles',
                    value: '$availableCars',
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [intro, const SizedBox(height: 16), summary],
                );
              }
              return Row(
                children: [
                  Expanded(child: intro),
                  summary,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BannerChip extends StatelessWidget {
  const _BannerChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
        border: Border.all(
          color: KajDesignTokens.electricBlue.withValues(alpha: .20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 3),
          AppText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.dashboard});
  final DashboardModel dashboard;

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    bool can(String field) => access.canViewField(
      'dashboard',
      field,
      viewPermission: 'dashboard.view',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (can('totalSales') && can('todaySales'))
              _KpiCard(
                width: width,
                icon: Icons.point_of_sale_outlined,
                color: const Color(0xFF16A66A),
                title: 'إجمالي المبيعات',
                value: CurrencyTotalsFormatter.format(
                  dashboard.totalSalesByCurrency,
                ),
                detail:
                    'اليوم ${CurrencyTotalsFormatter.format(dashboard.todaySalesByCurrency)}',
                onTap: () => _openDashboardReport(
                  context,
                  'sales',
                  'تفاصيل إجمالي المبيعات',
                ),
              ),
            if (can('netProfit'))
              _KpiCard(
                width: width,
                icon: Icons.trending_up_rounded,
                color:
                    !dashboard.netProfitByCurrency.values.any(
                      (value) => value < 0,
                    )
                    ? const Color(0xFF7C5CE7)
                    : Colors.red,
                title: 'صافي الربح',
                value: CurrencyTotalsFormatter.format(
                  dashboard.netProfitByCurrency,
                ),
                detail:
                    !dashboard.netProfitByCurrency.values.any(
                      (value) => value < 0,
                    )
                    ? 'ربحية موجبة'
                    : 'تحتاج إلى مراجعة',
                onTap: () =>
                    _openDashboardReport(context, 'overview', 'تفاصيل الأرباح'),
              ),
            if (can('totalCars') && can('availableCars') && can('soldCars'))
              _KpiCard(
                width: width,
                icon: Icons.directions_car_outlined,
                color: const Color(0xFF2F80ED),
                title: 'أسطول السيارات',
                value: '${dashboard.totalCars}',
                detail:
                    '${dashboard.availableCars} متوفرة • ${dashboard.soldCars} مباعة',
                onTap: () => _openDashboardReport(
                  context,
                  'cars',
                  'تفاصيل أسطول السيارات',
                ),
              ),
            if (can('overdueInstallments') && can('dueSoonInstallments'))
              _KpiCard(
                width: width,
                icon: Icons.schedule_rounded,
                color: dashboard.overdueInstallments > 0
                    ? const Color(0xFFE05D5D)
                    : const Color(0xFFF2A900),
                title: 'الأقساط المستحقة',
                value: '${dashboard.overdueInstallments}',
                detail: '${dashboard.dueSoonInstallments} خلال 7 أيام',
                onTap: () => _openDashboardReport(
                  context,
                  'finance',
                  'تفاصيل التسويات والأقساط',
                ),
              ),
            if (can('inventoryValue') && can('lowStockItems'))
              _KpiCard(
                width: width,
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF0E8F9B),
                title: 'قيمة المخزون',
                value: CurrencyTotalsFormatter.format(
                  dashboard.inventoryValueByCurrency,
                ),
                detail: '${dashboard.lowStockItems} مواد عند الحد الأدنى',
                onTap: () => _openDashboardReport(
                  context,
                  'inventory',
                  'تفاصيل قيمة المخزون',
                ),
              ),
            if (can('totalReceivables') && can('totalPayables'))
              _KpiCard(
                width: width,
                icon: Icons.receipt_long_outlined,
                color: const Color(0xFF8A5CF5),
                title: 'الذمم المدينة',
                value: CurrencyTotalsFormatter.format(
                  dashboard.totalReceivablesByCurrency,
                ),
                detail:
                    'ذمم الموردين ${CurrencyTotalsFormatter.format(dashboard.totalPayablesByCurrency)}',
                onTap: () => _openDashboardReport(
                  context,
                  'finance',
                  'تفاصيل الذمم المدينة والدائنة',
                ),
              ),
            if (can('cashBalanceIqd') && can('cashBalanceUsd'))
              _KpiCard(
                width: width,
                icon: Icons.currency_exchange_rounded,
                color: const Color(0xFFB7791F),
                title: 'رصيد الصناديق IQD',
                value: _money(dashboard.cashBalanceIqd),
                detail: 'USD ${_money(dashboard.cashBalanceUsd)}',
                onTap: () => _openDashboardReport(
                  context,
                  'finance',
                  'تفاصيل الصناديق والتسويات',
                ),
              ),
            if (can('carsWithoutWarehouse') && can('pendingPurchaseCars'))
              _KpiCard(
                width: width,
                icon: Icons.warning_amber_rounded,
                color: dashboard.carsWithoutWarehouse > 0
                    ? const Color(0xFFE05D5D)
                    : const Color(0xFF16A66A),
                title: 'تنبيهات السيارات',
                value: '${dashboard.carsWithoutWarehouse}',
                detail: '${dashboard.pendingPurchaseCars} قيد الشراء',
                onTap: () => _openDashboardReport(
                  context,
                  'cars',
                  'تفاصيل حالات السيارات',
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.width,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.detail,
    this.onTap,
  });
  final double width;
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: _Panel(
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AppText(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AppText(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_left_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openDashboardReport(
  BuildContext context,
  String module,
  String title,
) {
  return showAppModuleDialog<void>(
    context: context,
    title: title,
    windowKey: 'dashboard-report-$module',
    singleInstance: true,
    maxWidth: 1220,
    maxHeight: 840,
    builder: (_) => ReportsPage(initialModule: module),
  );
}

class _SalesTrendPanel extends StatelessWidget {
  const _SalesTrendPanel({required this.points, required this.mixedCurrencies});
  final List<DashboardSalesPoint> points;
  final bool mixedCurrencies;

  @override
  Widget build(BuildContext context) {
    final maxValue = points.fold<double>(
      0,
      (value, point) => math.max(value, point.amount),
    );
    final total = points.fold<double>(
      0,
      (value, point) => value + point.amount,
    );
    if (mixedCurrencies) {
      return _Panel(
        child: ListTile(
          leading: const Icon(Icons.currency_exchange_outlined),
          title: AppText(
            context.l10n.isArabic
                ? 'اتجاه المبيعات حسب العملة'
                : 'Sales trend by currency',
          ),
          subtitle: AppText(
            context.l10n.isArabic
                ? 'تم إخفاء الرسم الموحّد لأنه سيجمع عملات مختلفة في محور مالي واحد.'
                : 'The combined chart is hidden because it would mix different currencies on one monetary axis.',
          ),
        ),
      );
    }
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            icon: Icons.bar_chart_rounded,
            title: 'حركة المبيعات',
            trailing: 'آخر 7 أيام',
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 190,
            child: points.isEmpty
                ? const _EmptyState(
                    icon: Icons.bar_chart_rounded,
                    label: 'لا توجد بيانات مبيعات',
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: points.map((point) {
                      final ratio = maxValue <= 0
                          ? 0.04
                          : math.max(.04, point.amount / maxValue);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (point.amount > 0)
                                Tooltip(
                                  message: _money(point.amount),
                                  child: AppText(
                                    _compactMoney(point.amount),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 5),
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor: ratio,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Theme.of(context).colorScheme.primary,
                                          Theme.of(
                                            context,
                                          ).colorScheme.tertiary,
                                        ],
                                      ),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              AppText(
                                _weekday(point.date),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const Divider(height: 22),
          Row(
            children: [
              const AppText(
                'إجمالي الفترة',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              AppText(
                _money(total),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstallmentsPanel extends StatelessWidget {
  const _InstallmentsPanel({
    required this.overdueCount,
    required this.dueSoonCount,
    required this.outstandingByCurrency,
    required this.items,
  });
  final int overdueCount;
  final int dueSoonCount;
  final Map<String, double> outstandingByCurrency;
  final List<DashboardInstallment> items;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            icon: Icons.event_note_outlined,
            title: 'الأقساط والمتابعات',
            trailing: '7 أيام',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: 'متأخرة',
                  value: '$overdueCount',
                  color: const Color(0xFFE05D5D),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniMetric(
                  label: 'قريبة',
                  value: '$dueSoonCount',
                  color: const Color(0xFFF2A900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MiniMetric(
            label: 'إجمالي المتبقي',
            value: CurrencyTotalsFormatter.format(outstandingByCurrency),
            color: Theme.of(context).colorScheme.primary,
          ),
          const Divider(height: 24),
          if (items.isEmpty)
            const SizedBox(
              height: 100,
              child: _EmptyState(
                icon: Icons.task_alt_rounded,
                label: 'لا توجد أقساط قريبة',
              ),
            )
          else
            ...items.take(4).map((item) => _InstallmentRow(item: item)),
        ],
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  const _InstallmentRow({required this.item});
  final DashboardInstallment item;
  @override
  Widget build(BuildContext context) {
    final color = item.isOverdue
        ? const Color(0xFFE05D5D)
        : const Color(0xFFF2A900);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  item.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AppText(
                  'القسط ${item.installmentNo} • ${DateFormat('yyyy/MM/dd').format(item.dueDate)}',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppText(
            MoneyFormatter.withCurrency(
              item.remainingAmount,
              item.currencyCode,
            ),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FleetPanel extends StatelessWidget {
  const _FleetPanel({required this.dashboard});
  final DashboardModel dashboard;

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    bool can(String field) => access.canViewField(
      'dashboard',
      field,
      viewPermission: 'dashboard.view',
    );
    final total = math.max(1, dashboard.totalCars);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            icon: Icons.directions_car_filled_outlined,
            title: 'حالة الأسطول',
            trailing: 'السيارات',
          ),
          const SizedBox(height: 16),
          if (can('availableCars'))
            _ProgressRow(
              label: 'متوفرة',
              value: dashboard.availableCars,
              total: total,
              color: const Color(0xFF16A66A),
            ),
          if (can('reservedCars'))
            _ProgressRow(
              label: 'قيد البيع',
              value: dashboard.reservedCars,
              total: total,
              color: const Color(0xFFF2A900),
            ),
          if (can('soldCars'))
            _ProgressRow(
              label: 'مباعة',
              value: dashboard.soldCars,
              total: total,
              color: const Color(0xFF2F80ED),
            ),
          if (can('pendingPurchaseCars'))
            _ProgressRow(
              label: 'قيد الشراء',
              value: dashboard.pendingPurchaseCars,
              total: total,
              color: const Color(0xFF8A5CF5),
            ),
          const Divider(height: 24),
          if (can('totalCustomers'))
            _SimpleRow(label: 'العملاء', value: '${dashboard.totalCustomers}'),
          if (can('totalSuppliers'))
            _SimpleRow(label: 'الموردون', value: '${dashboard.totalSuppliers}'),
          if (can('activeReservations'))
            _SimpleRow(
              label: 'الحجوزات النشطة',
              value: '${dashboard.activeReservations}',
            ),
        ],
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.items});
  final List<DashboardActivity> items;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            icon: Icons.history_rounded,
            title: 'آخر النشاطات',
            trailing: 'سجل العمليات',
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const SizedBox(
              height: 190,
              child: _EmptyState(
                icon: Icons.history_toggle_off_rounded,
                label: 'لا توجد عمليات مسجلة بعد',
              ),
            )
          else
            ...items.take(6).map((item) => _ActivityRow(item: item)),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final DashboardActivity item;

  @override
  Widget build(BuildContext context) {
    final action = item.action.toLowerCase();
    final color = action.contains('delete')
        ? const Color(0xFFE05D5D)
        : action.contains('insert') || action.contains('create')
        ? const Color(0xFF16A66A)
        : const Color(0xFF2F80ED);
    final icon = action.contains('delete')
        ? Icons.delete_outline_rounded
        : action.contains('insert') || action.contains('create')
        ? Icons.add_circle_outline_rounded
        : Icons.edit_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  item.description.isEmpty
                      ? '${item.action} • ${item.module}'
                      : item.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                AppText(
                  '${item.userName} • ${_relativeTime(item.createdAt)}',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.dashboard});
  final DashboardModel dashboard;

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    bool can(String field) => access.canViewField(
      'dashboard',
      field,
      viewPermission: 'dashboard.view',
    );
    final synced = dashboard.pendingSyncOperations == 0;
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 9,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (can('generatedAt'))
            _StatusItem(
              icon: Icons.schedule_rounded,
              label: 'آخر تحديث',
              value: DateFormat('hh:mm a').format(dashboard.generatedAt),
            ),
          if (can('pendingSyncOperations'))
            _StatusItem(
              icon: synced
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_upload_outlined,
              label: 'المزامنة',
              value: synced
                  ? 'مكتملة'
                  : '${dashboard.pendingSyncOperations} معلقة',
              color: synced ? const Color(0xFF16A66A) : const Color(0xFFF2A900),
            ),
          if (can('cashBalanceUsd'))
            _StatusItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'الصندوق USD',
              value: _money(dashboard.cashBalanceUsd),
            ),
          if (can('cashBalanceIqd'))
            _StatusItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'الصندوق IQD',
              value: _money(dashboard.cashBalanceIqd),
            ),
          if (can('inventoryValue'))
            _StatusItem(
              icon: Icons.inventory_2_outlined,
              label: 'قيمة المخزون',
              value: CurrencyTotalsFormatter.format(
                dashboard.inventoryValueByCurrency,
              ),
            ),
          if (can('totalPurchases'))
            _StatusItem(
              icon: Icons.shopping_cart_outlined,
              label: 'المشتريات',
              value: CurrencyTotalsFormatter.format(
                dashboard.totalPurchasesByCurrency,
              ),
            ),
          if (can('totalExpenses'))
            _StatusItem(
              icon: Icons.payments_outlined,
              label: 'المصروفات',
              value: CurrencyTotalsFormatter.format(
                dashboard.totalExpensesByCurrency,
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C1623) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark ? const Color(0xFF1D2A3A) : const Color(0xFFE7E9EF),
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .035),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.trailing,
  });
  final IconData icon;
  final String title;
  final String trailing;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        AppText(
          title,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        AppText(
          trailing,
          style: TextStyle(
            fontSize: 9.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppText(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });
  final String label;
  final int value;
  final int total;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final ratio = (value / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AppText(
                '$value',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: .1),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: AppText(label, style: const TextStyle(fontSize: 11.5)),
          ),
          AppText(
            value,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: effective),
        const SizedBox(width: 6),
        AppText(
          '$label: ',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        AppText(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: effective,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 34,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: .45),
          ),
          const SizedBox(height: 8),
          AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(child: AppText(message)),
        ],
      ),
    );
  }
}

bool _hasMultipleCurrencies(Map<String, double> totals) =>
    totals.entries.where((entry) => entry.value.abs() > 0.0000001).length > 1;

String _money(double value) => NumberFormat('#,##0.00').format(value);
String _compactMoney(double value) {
  if (value.abs() >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value.abs() >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value.toStringAsFixed(0);
}

String _weekday(DateTime date) {
  const days = [
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];
  return days[date.weekday - 1].substring(
    0,
    math.min(3, days[date.weekday - 1].length),
  );
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) return 'الآن';
  if (difference.inMinutes < 60) return 'منذ ${difference.inMinutes} د';
  if (difference.inHours < 24) return 'منذ ${difference.inHours} س';
  if (difference.inDays < 7) return 'منذ ${difference.inDays} ي';
  return DateFormat('yyyy/MM/dd').format(value);
}
