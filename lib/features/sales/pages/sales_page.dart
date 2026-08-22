import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/incremental_list_view.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/legacy_commercial_document_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/legacy_commercial_archive_toolbar.dart';

import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';

import 'package:quality_line_erp/features/sales/controllers/sales_controller.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';
import 'package:quality_line_erp/features/sales/models/sales_workflow_order_model.dart';
import 'package:quality_line_erp/features/sales/widgets/sale_card.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/design_system/kaj_phase5_components.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final TextEditingController _searchController = TextEditingController();

  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SalesController>();
    final workflowOrders = controller.salesWorkflowOrders;
    final sales = controller.sales;
    final cars = context.watch<CarsController>().cars;
    final customers = context.watch<CustomersController>().customers;
    final carNames = {
      for (final car in cars)
        car.id: '${car.brand} ${car.model} ${car.year} — ${car.chassis}',
    };
    final customerNames = {
      for (final customer in customers) customer.id: customer.name,
    };

    final latestSequenceByCar = <String, int>{};
    for (final sale in sales) {
      final current = latestSequenceByCar[sale.carId] ?? 0;
      if (sale.saleSequence > current) {
        latestSequenceByCar[sale.carId] = sale.saleSequence;
      }
    }

    final List<SalesWorkflowOrder> filteredOrders = UnifiedFilterEngine.apply<SalesWorkflowOrder>(
      workflowOrders,
      criteria: UnifiedFilterCriteria(searchText: _search),
      adapter: UnifiedFilterAdapter<SalesWorkflowOrder>(
        searchableText: (order) => <Object?>[
          order.id,
          order.orderNumber,
          order.customerId,
          carNames[order.customerId] ?? '',
          order.customerId,
          customerNames[order.customerId] ?? '',
          order.status,
          order.currency,
          order.total,
          order.notes,
          order.createdAt,
        ],
        partnerId: (order) => order.customerId,
        type: (order) => order.status.contains('approved') ? 'primary' : 'resale',
        currency: (order) => order.currency,
        userId: (order) => order.customerId,
        date: (order) => order.createdAt,
      ),
    );

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 7),
              child: KajCommercialHero(
                title: AppTranslation.translate('مركز المبيعات'),
                subtitle: AppTranslation.translate(
                  'إدارة أوامر البيع والفواتير والتحصيلات وإعادة البيع ضمن تجربة تجارية موحدة.',
                ),
                icon: Icons.trending_up_rounded,
                metrics: <KajCommercialMetricData>[
                  KajCommercialMetricData(
                    label: AppTranslation.translate('المعاملات'),
                    value: controller.totalSales.toString(),
                    icon: Icons.receipt_long_outlined,
                    accent: const Color(0xFF62BEC1),
                  ),
                  KajCommercialMetricData(
                    label: AppTranslation.translate('الإيراد'),
                    value: CurrencyTotalsFormatter.format(
                      controller.revenueByCurrency,
                    ),
                    icon: Icons.payments_outlined,
                    accent: const Color(0xFFCEB686),
                  ),
                  KajCommercialMetricData(
                    label: AppTranslation.translate('المحصل'),
                    value: CurrencyTotalsFormatter.format(
                      controller.paidByCurrency,
                    ),
                    icon: Icons.verified_outlined,
                    accent: const Color(0xFF00D17D),
                  ),
                  KajCommercialMetricData(
                    label: AppTranslation.translate('المتبقي'),
                    value: CurrencyTotalsFormatter.format(
                      controller.remainingByCurrency,
                    ),
                    icon: Icons.schedule_outlined,
                    accent: const Color(0xFFE6A95C),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: LegacyCommercialArchiveToolbar(
                title: AppTranslation.translate('سجل الفواتير القديمة'),
                message: AppTranslation.translate(
                  'هذا السجل للعرض والطباعة فقط. إنشاء وتعديل المبيعات يتم من تبويب أوامر البيع لضمان التجهيز والفوترة وCOGS والإيراد والتحصيل المترابط.',
                ),
                searchHint: AppTranslation.translate(
                  'ابحث برقم الفاتورة أو السيارة...',
                ),
                searchController: _searchController,
                onSearchChanged: (value) => setState(() => _search = value),
              ),
            ),
            Expanded(
              child: filteredOrders.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 30,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 6),
                            AppText(
                              AppTranslation.translate('لا توجد'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : IncrementalListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = filteredOrders[index];

                        return SaleCard(
                          order: order,
                          carName: carNames[order.customerId],
                          customerName: customerNames[order.customerId],
                          onPrint: () async {
                            try {
                              await const LegacyCommercialDocumentPdfService()
                                  .printSale(
                                    sale: SaleModel(
                                      id: order.id,
                                      carId: order.customerId,
                                      customerId: order.customerId,
                                      salePrice: order.total,
                                      paidAmount: (order.total - (order.invoiceRemaining ?? 0)).clamp(0, order.total).toDouble(),
                                      remainingAmount: order.invoiceRemaining ?? 0,
                                      paymentMethod: '',
                                      saleDate: order.createdAt.toString(),
                                      notes: order.notes ?? '',
                                      invoiceNumber: order.orderNumber,
                                      currencyCode: order.currency,
                                      createdByUserName: order.customerName,
                                      saleType: 'primary',
                                    ),
                                    customerName:
                                        customerNames[order.customerId] ??
                                            'عميل غير محدد',
                                    carName:
                                        carNames[order.customerId] ??
                                            'سيارة غير محددة',
                                    language: context.l10n.isArabic
                                        ? 'ar'
                                        : 'en',
                                  );
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: AppText(
                                    userFacingError(
                                      error,
                                      isArabic: context.l10n.isArabic,
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          onDelete: () async {
                            if (!await PermissionAction.require(
                              context,
                              'sales.delete',
                            )) {
                              return;
                            }
                            if (!context.mounted) return;
                            final confirmed = await showAppConfirmDialog(
                              context,
                              title: 'حذف أمر البيع',
                              message:
                                  'سيتم عكس الارتباطات المحاسبية والمخزنية المرتبطة قبل حذف أمر البيع. هل تريد المتابعة؟',
                              confirmLabel: 'حذف أمر البيع',
                              destructive: true,
                            );
                            if (confirmed != true || !context.mounted) return;
                            try {
                              await controller.removeSale(order.id);
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: AppText(
                                    userFacingError(
                                      error,
                                      isArabic: context.l10n.isArabic,
                                      arabicFallback: 'تعذر حذف أمر البيع.',
                                      englishFallback:
                                          'Unable to delete the sales invoice.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}