import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/legacy_commercial_document_pdf_service.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/incremental_list_view.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_query_toolbar.dart';
import 'package:quality_line_erp/features/purchases/controllers/purchases_controller.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';
import 'package:quality_line_erp/features/purchases/widgets/purchase_card.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<PurchasesController>().loadPurchases();
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر طباعة فاتورة الشراء.',
              englishFallback: 'Unable to print the purchase invoice.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openDetails(PurchaseModel purchase) async {
    try {
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر تحميل تفاصيل فاتورة الشراء.',
              englishFallback: 'Unable to load purchase invoice details.',
            ),
          ),
        ),
      );
    }
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
    if (ok != true || !mounted) return;
    try {
      await context.read<PurchasesController>().deletePurchase(purchase.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حذف فاتورة الشراء.',
              englishFallback: 'Unable to delete the purchase invoice.',
            ),
          ),
        ),
      );
    }
  }

  List<UnifiedQueryFilterOption> _filters(BuildContext context) => [
    UnifiedQueryFilterOption(
      token: UnifiedFilterToken(
        key: 'paymentStatus',
        label: context.l10n.isArabic ? 'حالة الدفع' : 'Payment status',
        value: 'paid',
        valueLabel: context.l10n.isArabic ? 'مدفوعة' : 'Paid',
      ),
      icon: Icons.payments_outlined,
    ),
    UnifiedQueryFilterOption(
      token: UnifiedFilterToken(
        key: 'paymentStatus',
        label: context.l10n.isArabic ? 'حالة الدفع' : 'Payment status',
        value: 'partial',
        valueLabel: context.l10n.isArabic ? 'جزئية' : 'Partial',
      ),
      icon: Icons.timelapse_outlined,
    ),
    UnifiedQueryFilterOption(
      token: UnifiedFilterToken(
        key: 'paymentStatus',
        label: context.l10n.isArabic ? 'حالة الدفع' : 'Payment status',
        value: 'credit',
        valueLabel: context.l10n.isArabic ? 'آجلة' : 'Credit',
      ),
      icon: Icons.account_balance_wallet_outlined,
    ),
    for (final currency in const ['IQD', 'USD'])
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: 'currency',
          label: context.l10n.isArabic ? 'العملة' : 'Currency',
          value: currency,
          valueLabel: currency,
        ),
        icon: Icons.currency_exchange_outlined,
      ),
  ];

  List<UnifiedQuerySortOption> _sorts(BuildContext context) => [
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'date',
        label: context.l10n.isArabic ? 'التاريخ' : 'Date',
        descending: true,
      ),
      icon: Icons.event_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'invoiceNumber',
        label: context.l10n.isArabic ? 'رقم الفاتورة' : 'Invoice number',
      ),
      icon: Icons.tag_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'supplier',
        label: context.l10n.isArabic ? 'المورد' : 'Supplier',
      ),
      icon: Icons.business_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'total',
        label: context.l10n.isArabic ? 'الإجمالي' : 'Total',
        descending: true,
      ),
      icon: Icons.summarize_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'remaining',
        label: context.l10n.isArabic ? 'المتبقي' : 'Remaining',
        descending: true,
      ),
      icon: Icons.hourglass_bottom_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PurchasesController>();
    final arabic = context.l10n.isArabic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                avatar: const Icon(Icons.receipt_long_outlined, size: 17),
                label: AppText(arabic ? 'المشتريات' : 'Purchases'),
              ),
              Chip(
                avatar: const Icon(Icons.description_outlined, size: 17),
                label: AppText(
                  '${arabic ? 'الفواتير' : 'Invoices'}: ${controller.purchasesCount}',
                ),
              ),
              Chip(
                avatar: const Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 17,
                ),
                label: AppText(
                  '${arabic ? 'المتبقي' : 'Remaining'}: ${CurrencyTotalsFormatter.format(controller.totalRemainingByCurrency)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: AppText(
                arabic
                    ? 'سجل الفواتير القديمة للعرض والطباعة. إنشاء وتعديل المشتريات يتم من تبويب أوامر الشراء لضمان الاستلام والفوترة والقيود والمدفوعات المترابطة.'
                    : 'Legacy invoices are for viewing and printing. Create and edit purchases from Purchase Orders so receiving, invoicing, journals, and payments remain linked.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          KajQueryToolbar(
            controller: controller.query,
            hintText: arabic
                ? 'بحث برقم الفاتورة أو المورد أو الملاحظات...'
                : 'Search invoice number, supplier, or notes...',
            filters: _filters(context),
            sorts: _sorts(context),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: controller.isLoading && controller.purchases.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : controller.purchases.isEmpty
                ? Center(
                    child: AppText(
                      controller.errorMessage ??
                          AppTranslation.translate('لا توجد فواتير مشتريات'),
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
    );
  }
}
