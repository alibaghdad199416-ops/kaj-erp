import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/printing/legacy_commercial_document_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';

import 'package:quality_line_erp/core/widgets/incremental_list_view.dart';
import 'package:quality_line_erp/core/widgets/legacy_commercial_archive_toolbar.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_phase5_components.dart';

import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

import 'package:quality_line_erp/features/purchases/controllers/purchases_controller.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';
import 'package:quality_line_erp/features/purchases/widgets/purchase_card.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<PurchasesController>().loadPurchases();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _printPurchase(PurchaseModel purchase) async {
    final controller = context.read<PurchasesController>();
    final language = context.l10n.isArabic ? 'ar' : 'en';
    try {
      final items = await controller.loadPurchaseItems(
        purchase.id,
        forceRefresh: true,
      );
      await const LegacyCommercialDocumentPdfService().printPurchase(
        purchase: purchase,
        items: items,
        language: language,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: AppText(error.toString())));
    }
  }

  Future<void> _openDetails(PurchaseModel purchase) async {
    final items = await context.read<PurchasesController>().loadPurchaseItems(
      purchase.id,
      forceRefresh: true,
    );
    if (!mounted) return;
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText('تفاصيل فاتورة ${purchase.invoiceNumber}'),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 760),
          child: ListView(
            shrinkWrap: true,
            children: [
              AppText('المورد: ${purchase.supplierName}'),
              AppText('العملة: ${purchase.currencyCode}'),
              AppText(
                'الإجمالي: ${MoneyFormatter.withCurrency(purchase.totalAmount, purchase.currencyCode)}',
              ),
              AppText(
                'المدفوع: ${MoneyFormatter.withCurrency(purchase.paidAmount, purchase.currencyCode)}',
              ),
              AppText(
                'المتبقي: ${MoneyFormatter.withCurrency(purchase.remainingAmount, purchase.currencyCode)}',
              ),
              const Divider(height: 28),
              const AppText(
                'بنود الفاتورة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...items.map(
                (item) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText(
                          item.carName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        AppText('رقم الشاصي: ${item.chassisNumber}'),
                        AppText(
                          'الكلفة: ${MoneyFormatter.withCurrency(item.purchasePrice, purchase.currencyCode)}',
                        ),
                        AppText(
                          'التكاليف الإضافية: ${MoneyFormatter.withCurrency(item.additionalCosts, purchase.currencyCode)}',
                        ),
                        AppText(
                          'الكلفة النهائية: ${MoneyFormatter.withCurrency(item.totalCost, purchase.currencyCode)}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => _printPurchase(purchase),
            icon: const Icon(Icons.print_outlined),
            label: AppText(AppTranslation.translate('طباعة الحزمة الرسمية')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const AppText('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(PurchaseModel purchase) async {
    if (!await PermissionAction.require(context, 'purchases.delete')) return;
    if (!mounted) return;
    final ok = await showAppConfirmDialog(
      context,
      title: 'حذف فاتورة الشراء',
      message: 'هل تريد حذف الفاتورة ${purchase.invoiceNumber}؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (ok == true && mounted) {
      await context.read<PurchasesController>().deletePurchase(purchase.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PurchasesController>();
    return Directionality(
      textDirection: Directionality.of(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          children: [
            KajCommercialHero(
              title: AppTranslation.translate('مركز المشتريات'),
              subtitle: AppTranslation.translate(
                'إدارة أوامر الشراء والفواتير والاستلام والتكاليف والمدفوعات ضمن مسار موحد.',
              ),
              icon: Icons.shopping_cart_checkout_rounded,
              metrics: <KajCommercialMetricData>[
                KajCommercialMetricData(
                  label: AppTranslation.translate('الفواتير'),
                  value: controller.purchasesCount.toString(),
                  icon: Icons.description_outlined,
                  accent: const Color(0xFF62BEC1),
                ),
                KajCommercialMetricData(
                  label: AppTranslation.translate('إجمالي المشتريات'),
                  value: CurrencyTotalsFormatter.format(
                    controller.totalPurchasesByCurrency,
                  ),
                  icon: Icons.inventory_2_outlined,
                  accent: const Color(0xFFCEB686),
                ),
                KajCommercialMetricData(
                  label: AppTranslation.translate('المدفوع'),
                  value: CurrencyTotalsFormatter.format(
                    controller.totalPaidByCurrency,
                  ),
                  icon: Icons.account_balance_wallet_outlined,
                  accent: const Color(0xFF00D17D),
                ),
                KajCommercialMetricData(
                  label: AppTranslation.translate('المتبقي'),
                  value: CurrencyTotalsFormatter.format(
                    controller.totalRemainingByCurrency,
                  ),
                  icon: Icons.hourglass_bottom_rounded,
                  accent: const Color(0xFFE6A95C),
                ),
              ],
            ),
            const SizedBox(height: 7),
            LegacyCommercialArchiveToolbar(
              title: AppTranslation.translate('سجل الفواتير القديمة'),
              message: AppTranslation.translate(
                'هذا السجل للعرض والطباعة فقط. إنشاء وتعديل المشتريات يتم من تبويب أوامر الشراء لضمان الاستلام والفوترة والقيود والمدفوعات المترابطة.',
              ),
              searchHint: AppTranslation.translate(
                'بحث برقم الفاتورة أو المورد',
              ),
              searchController: _searchController,
              onSearchChanged: controller.searchPurchases,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: controller.isLoading && controller.purchases.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : controller.purchases.isEmpty
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
                              AppTranslation.translate(
                                'لا توجد فواتير مشتريات',
                              ),
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
                      itemCount: controller.purchases.length,
                      itemBuilder: (context, index) {
                        final purchase = controller.purchases[index];
                        return PurchaseCard(
                          purchase: purchase,
                          onView: () => _openDetails(purchase),
                          onDelete: () => _delete(purchase),
                          onPrint: () => _printPurchase(purchase),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _stat(String title, String value) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 6),
              AppText(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
