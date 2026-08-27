import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/incremental_list_view.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/legacy_commercial_document_pdf_service.dart';

import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/sales/controllers/sales_controller.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';
import 'package:quality_line_erp/features/sales/widgets/sale_card.dart';
import 'package:quality_line_erp/features/sales/widgets/sales_statistics.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/design_system/kaj_query_toolbar.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  late final UnifiedQueryController _queryController = UnifiedQueryController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SalesController>();
    final cars = context.watch<CarsController>().cars;
    final customers = context.watch<CustomersController>().customers;
    final carNames = {
      for (final car in cars)
        car.id: '${car.brand} ${car.model} ${car.year} — ${car.chassis}',
    };
    final customerNames = {
      for (final customer in customers) customer.id: customer.name,
    };

    final filteredSales = UnifiedQueryExecutor<SaleModel>(
      criteriaBuilder: (state) =>
          UnifiedFilterCriteria(searchText: state.search),
      filterAdapter: UnifiedFilterAdapter<SaleModel>(
        searchableText: (sale) => <Object?>[
          sale.invoiceNumber,
          carNames[sale.carId],
          customerNames[sale.customerId],
          sale.paymentMethod,
          sale.notes,
          sale.createdByUserName,
        ],
        partnerId: (sale) => sale.customerId,
        type: (sale) => sale.saleType,
        currency: (sale) => sale.currencyCode,
        userId: (sale) => sale.createdByUserId,
        date: (sale) => DateTime.tryParse(sale.saleDate),
      ),
      sort: (left, right, field) {
        switch (field) {
          case 'date':
            final l = DateTime.tryParse(left.saleDate);
            final r = DateTime.tryParse(right.saleDate);
            if (l == null && r == null) return 0;
            if (l == null) return 1;
            if (r == null) return -1;
            return l.compareTo(r);
          case 'invoice':
            return left.invoiceNumber.compareTo(right.invoiceNumber);
          case 'customer':
            return (customerNames[left.customerId] ?? '').compareTo(
              customerNames[right.customerId] ?? '',
            );
          case 'total':
            return left.total.compareTo(right.total);
          default:
            return 0;
        }
      },
    ).execute(controller.sales, _queryController.state);

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        body: Column(
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: const ListTile(
                leading: Icon(Icons.history_outlined),
                title: AppText('سجل الفواتير القديمة'),
                subtitle: AppText(
                  'هذا السجل للعرض والطباعة فقط. إنشاء وتعديل المبيعات يتم من تبويب أوامر البيع لضمان التجهيز والفوترة وCOGS والإيراد والتحصيل المترابط.',
                ),
              ),
            ),
            SalesStatistics(
              totalSales: controller.totalSales,
              revenueByCurrency: controller.revenueByCurrency,
              paidByCurrency: controller.paidByCurrency,
              remainingByCurrency: controller.remainingByCurrency,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: KajQueryToolbar(
                controller: _queryController,
                hintText: context.l10n.isArabic
                    ? 'البحث برقم الفاتورة أو العميل أو السيارة أو طريقة الدفع'
                    : 'Search invoice, customer, vehicle or payment method',
                sortBuilder: (context) => PopupMenuButton<String>(
                  tooltip: context.l10n.isArabic ? 'الفرز' : 'Sort',
                  icon: const Icon(Icons.sort_rounded),
                  onSelected: (field) {
                    const labels = <String, String>{
                      'date': 'التاريخ',
                      'invoice': 'رقم الفاتورة',
                      'customer': 'العميل',
                      'total': 'الإجمالي',
                    };
                    final existing = _queryController.state.sorts
                        .where((item) => item.field == field)
                        .firstOrNull;
                    _queryController.addSort(
                      UnifiedSortRule(
                        field: field,
                        label: labels[field] ?? field,
                        descending: existing == null
                            ? true
                            : !existing.descending,
                      ),
                    );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'date', child: AppText('التاريخ')),
                    PopupMenuItem(
                      value: 'invoice',
                      child: AppText('رقم الفاتورة'),
                    ),
                    PopupMenuItem(value: 'customer', child: AppText('العميل')),
                    PopupMenuItem(value: 'total', child: AppText('الإجمالي')),
                  ],
                ),
              ),
            ),
            Expanded(
              child: filteredSales.isEmpty
                  ? Center(
                      child: AppText(
                        AppTranslation.translate('لا توجد مبيعات'),
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : IncrementalListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                      itemCount: filteredSales.length,
                      itemBuilder: (context, index) {
                        final sale = filteredSales[index];
                        return SaleCard(
                          sale: sale,
                          carName: carNames[sale.carId],
                          customerName: customerNames[sale.customerId],
                          onPrint: () async {
                            try {
                              await const LegacyCommercialDocumentPdfService()
                                  .printSale(
                                    sale: sale,
                                    customerName:
                                        customerNames[sale.customerId] ??
                                        'عميل غير محدد',
                                    carName:
                                        carNames[sale.carId] ??
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
                            ))
                              return;
                            if (!context.mounted) return;
                            final confirmed = await showAppConfirmDialog(
                              context,
                              title: 'حذف فاتورة البيع',
                              message:
                                  'سيتم عكس الارتباطات المحاسبية والمخزنية المرتبطة قبل حذف الفاتورة. هل تريد المتابعة؟',
                              confirmLabel: 'حذف الفاتورة',
                              destructive: true,
                            );
                            if (confirmed != true || !context.mounted) return;
                            try {
                              await controller.removeSale(sale.id);
                            } catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: AppText(
                                    userFacingError(
                                      error,
                                      isArabic: context.l10n.isArabic,
                                      arabicFallback: 'تعذر حذف فاتورة البيع.',
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
