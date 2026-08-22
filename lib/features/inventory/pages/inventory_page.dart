import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/core/printing/product_maintenance_card_pdf_service.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:flutter/material.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:intl/intl.dart';
import 'package:quality_line_erp/core/widgets/app_floating_window.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/utils/base64_image_cache.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/features/inventory/pages/inventory_movements_page.dart';
import 'package:quality_line_erp/features/inventory/asset_history/pages/asset_history_page.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_group_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_stock_model.dart';
import 'package:quality_line_erp/features/inventory/widgets/inventory_card.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'add_inventory_page.dart';
import 'planned_stock_page.dart';
import 'product_warehouse_transfers_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<InventoryController>().loadInventory();
    });
  }

  Future<void> _open(Widget page) async {
    final changed = await showAppWorkspaceDialog<bool>(
      context: context,
      child: page,
    );
    if (changed == true && mounted) {
      await context.read<InventoryController>().loadInventory();
    }
  }

  Future<void> _openProductHistory(InventoryModel item) async {
    await showAppWorkspaceDialog<void>(
      context: context,
      child: AssetHistoryPage.product(assetId: item.id),
    );
  }

  Future<void> _editProduct(
    InventoryController controller,
    InventoryModel item,
  ) async {
    List<String> images = const <String>[];
    try {
      images = await controller.getProductImages(item.id);
    } catch (_) {
      // Editing the product itself must remain available even when an optional
      // image lookup fails.
    }
    if (!mounted) return;
    await _open(AddInventoryPage(item: item, initialImages: images));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InventoryController>();
    final items = controller.filteredItems;

    return AppEntityPage(
      hideHeader: true,
      title: context.l10n.isArabic ? 'إدارة المنتجات' : 'Product management',
      subtitle: context.l10n.isArabic
          ? 'إدارة المنتجات والأرصدة والكلفة وسعر البيع حسب المستندات التجارية.'
          : 'Manage products, stock balances, cost and selling prices from commercial documents.',
      leading: const Icon(Icons.inventory_2_outlined, size: 20),
      showBackButton: false,
      actions: [
        OutlinedButton.icon(
          onPressed: () => _showGroupsManager(controller),
          icon: const Icon(Icons.category_outlined, size: 16),
          label: AppText(
            context.l10n.isArabic ? 'المجموعات المخزنية' : 'Inventory groups',
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _showWarehousesManager(controller),
          icon: const Icon(Icons.warehouse_outlined, size: 16),
          label: AppText(
            context.l10n.isArabic ? 'إدارة المخازن' : 'Warehouses',
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _open(InventoryMovementsPage()),
          icon: const Icon(Icons.history_rounded, size: 16),
          label: AppText(context.l10n.isArabic ? 'سجل الحركة' : 'Movement log'),
        ),
        if (context.watch<AccessController>().hasPermission('inventory.adjust'))
          OutlinedButton.icon(
            onPressed: () => _open(const PlannedStockPage()),
            icon: const Icon(Icons.insights_outlined, size: 16),
            label: AppText(
              context.l10n.isArabic ? 'الحركات المتوقعة' : 'Planned movements',
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _open(const ProductWarehouseTransfersPage()),
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: AppText(
            context.l10n.isArabic ? 'نقل مخزني' : 'Warehouse transfer',
          ),
        ),
        FilledButton.icon(
          onPressed: () => _open(const AddInventoryPage()),
          icon: const Icon(Icons.add, size: 16),
          label: AppText(
            context.l10n.isArabic ? 'إنشاء منتج' : 'Create product',
          ),
        ),
      ],
      statistics: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompactMetricPill(
            icon: Icons.inventory_2_outlined,
            label: context.l10n.isArabic ? 'المنتجات' : 'Products',
            value: '${controller.totalItems}',
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.layers_outlined,
            label: context.l10n.isArabic
                ? 'الوحدات المتوفرة'
                : 'Available units',
            value: '${controller.totalQuantity}',
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.insights_outlined,
            label: context.l10n.isArabic
                ? 'الرصيد المتوقع'
                : 'Expected balance',
            value: '${controller.expectedQuantity}',
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.warning_amber_rounded,
            label: context.l10n.isArabic ? 'منخفض المخزون' : 'Low stock',
            value: '${controller.lowStockItems}',
          ),
          const SizedBox(width: 7),
          CompactMetricPill(
            icon: Icons.account_balance_wallet_outlined,
            label: context.l10n.isArabic ? 'قيمة المخزون' : 'Inventory value',
            value: CurrencyTotalsFormatter.format(
              controller.totalValueByCurrency,
            ),
          ),
        ],
      ),
      toolbar: _filters(controller),
      body: controller.isLoading
          ? const KajInventoryLoadingState()
          : items.isEmpty
          ? _emptyState()
          : LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                const minimumCardWidth = 330.0;
                final columns =
                    ((constraints.maxWidth + gap) / (minimumCardWidth + gap))
                        .floor()
                        .clamp(1, 4)
                        .toInt();
                return GridView.builder(
                  padding: const EdgeInsets.all(6),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                    mainAxisExtent: columns >= 3
                        ? 142
                        : columns == 2
                        ? 146
                        : 150,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return InventoryCard(
                      item: item,
                      onView: () => _showProductDetails(controller, item),
                      onEdit: () => _editProduct(controller, item),
                      onHistory: () => _openProductHistory(item),
                      onDelete: () async {
                        if (!await PermissionAction.require(
                          context,
                          'inventory.delete',
                        )) {
                          return;
                        }
                        final impact = await controller.inventoryDeleteImpact(
                          item.id,
                        );
                        if (!context.mounted) return;
                        final stock = impact['stockQuantity'] ?? 0;
                        final opening = impact['openingQuantity'] ?? 0;
                        final sales = impact['salesOrderLinks'] ?? 0;
                        final purchases = impact['purchaseOrderLinks'] ?? 0;
                        final transfers = impact['transferLinks'] ?? 0;
                        final fifo = impact['activeFifoConsumptions'] ?? 0;
                        final mismatches =
                            impact['warehouseOpeningMismatches'] ?? 0;
                        final orphanMovements =
                            impact['orphanMovementCount'] ?? 0;
                        final canDelete = impact['canDelete'] == true;
                        final returnedToOpening =
                            impact['returnedToOpeningState'] == true;
                        final arabic = context.l10n.isArabic;
                        final policyMessage = canDelete
                            ? (arabic
                                  ? 'عادت المادة إلى حالتها الافتتاحية ويمكن حذفها مع رصيدها الافتتاحي وسجلها المخزني إلى سلة المحذوفات.'
                                  : 'The product returned to its opening state and can be deleted together with its opening balance and inventory history.')
                            : returnedToOpening
                            ? (arabic
                                  ? 'الرصيد عاد إلى الحالة الافتتاحية، لكن ما زالت هناك روابط فعالة يجب حذفها أولًا.'
                                  : 'The balance returned to its opening state, but active links still need to be removed first.')
                            : (arabic
                                  ? 'يوجد فرق بين الرصيد الحالي والرصيد الافتتاحي في مخزن واحد أو أكثر. اعكس العمليات المرتبطة ثم أعد التحقق.'
                                  : 'One or more warehouses differ from their opening balance. Reverse the linked operations, then verify again.');
                        final accepted = await showAppConfirmDialog(
                          context,
                          title: arabic
                              ? 'حذف المادة المخزنية'
                              : 'Delete product',
                          message: arabic
                              ? 'المادة: ${item.name}\n'
                                    'الرصيد الحالي: $stock • الرصيد الافتتاحي: $opening\n'
                                    'روابط البيع: $sales، الشراء: $purchases، النقل الفعال: $transfers\n'
                                    'استهلاكات FIFO: $fifo • فروقات المخازن: $mismatches\n'
                                    'حركات قديمة بلا مستند فعال: $orphanMovements\n\n'
                                    '$policyMessage'
                              : 'Product: ${item.name}\n'
                                    'Current balance: $stock • Opening balance: $opening\n'
                                    'Sales links: $sales • Purchase links: $purchases • Active transfers: $transfers\n'
                                    'FIFO consumptions: $fifo • Warehouse mismatches: $mismatches\n'
                                    'Legacy movements without an active document: $orphanMovements\n\n'
                                    '$policyMessage',
                          confirmLabel: canDelete
                              ? (arabic
                                    ? 'حذف المادة وسجلها الافتتاحي'
                                    : 'Delete product and opening history')
                              : (arabic
                                    ? 'إعادة التحقق ومحاولة الحذف'
                                    : 'Recheck and try deletion'),
                          destructive: true,
                        );
                        if (!accepted || !context.mounted) return;
                        try {
                          await controller.deleteInventory(item.id);
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
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _filters(InventoryController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final search = TextField(
          onChanged: controller.setSearchQuery,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: AppTranslation.translate('بحث باسم المنتج...'),
          ),
        );
        final warehouse = DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: controller.selectedWarehouseId ?? '__all__',
          decoration: InputDecoration(
            labelText: AppTranslation.translate('المخزن'),
          ),
          items: [
            DropdownMenuItem<String>(
              value: '__all__',
              child: AppText(
                context.l10n.isArabic ? 'جميع المخازن' : 'All warehouses',
              ),
            ),
            ...controller.warehouses.map(
              (item) => DropdownMenuItem<String>(
                value: item.id,
                child: AppText(item.name),
              ),
            ),
          ],
          onChanged: (value) =>
              controller.setWarehouseFilter(value == '__all__' ? null : value),
        );
        final group = DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: controller.selectedGroupId ?? '__all__',
          decoration: InputDecoration(
            labelText: AppTranslation.translate('المجموعة'),
          ),
          items: [
            DropdownMenuItem<String>(
              value: '__all__',
              child: AppText(
                context.l10n.isArabic ? 'جميع المجموعات' : 'All groups',
              ),
            ),
            ...controller.groups.map(
              (item) => DropdownMenuItem<String>(
                value: item.id,
                child: AppText(item.name),
              ),
            ),
          ],
          onChanged: (value) =>
              controller.setGroupFilter(value == '__all__' ? null : value),
        );
        if (compact) {
          return Column(
            children: [
              search,
              const SizedBox(height: 8),
              warehouse,
              const SizedBox(height: 8),
              group,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 8),
            SizedBox(width: 210, child: warehouse),
            const SizedBox(width: 8),
            SizedBox(width: 210, child: group),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 58, color: Colors.grey),
          const SizedBox(height: 12),
          AppText(
            context.l10n.isArabic
                ? 'لا توجد منتجات مطابقة'
                : 'No matching products',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          AppText(
            context.l10n.isArabic
                ? 'أضف منتجاً جديداً أو غيّر مرشحات البحث.'
                : 'Create a product or change the search filters.',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _open(const AddInventoryPage()),
            icon: const Icon(Icons.add),
            label: AppText(
              context.l10n.isArabic ? 'إضافة منتج' : 'Add product',
            ),
          ),
        ],
      ),
    );
  }

  ExportDocument _productExportDocument(
    InventoryController controller,
    InventoryModel item,
    List<WarehouseStockModel> stocks,
  ) {
    final user = context.read<AccessController>().currentUser;
    final generatedAt = DateTime.now();
    final rows = stocks.isEmpty
        ? <List<Object?>>[
            <Object?>[
              item.name,
              item.category,
              '',
              item.quantity,
              item.availableQuantity,
              item.expectedQuantity,
              item.unit,
              item.purchasePrice,
              item.landedCost,
              item.unitCost,
              item.salePrice,
              item.costCurrency ?? item.currency,
              item.saleCurrency ?? item.currency,
              user?.fullName ?? user?.username ?? '',
              generatedAt,
            ],
          ]
        : stocks
              .map((stock) {
                final match = controller.warehouses.where(
                  (w) => w.id == stock.warehouseId,
                );
                final warehouseName = match.isEmpty
                    ? stock.warehouseId
                    : match.first.name;
                return <Object?>[
                  item.name,
                  item.category,
                  warehouseName,
                  stock.quantity,
                  stock.availableQuantity,
                  stock.projectedQuantity,
                  item.unit,
                  item.purchasePrice,
                  item.landedCost,
                  stock.averageUnitCost,
                  item.salePrice,
                  item.costCurrency ?? item.currency,
                  item.saleCurrency ?? item.currency,
                  user?.fullName ?? user?.username ?? '',
                  generatedAt,
                ];
              })
              .toList(growable: false);
    return ExportDocument(
      title: 'Product Details',
      subtitle:
          'Warehouse balances, quantities, pricing and execution metadata',
      language: 'en',
      generatedAt: generatedAt,
      metadata: <String, Object?>{
        'Product ID': item.id,
        'Product': item.name,
        'Generated by': user?.fullName ?? user?.username ?? '',
      },
      columns: const <ExportColumn>[
        ExportColumn(key: 'product', label: 'Product', width: 1.6),
        ExportColumn(key: 'group', label: 'Group'),
        ExportColumn(key: 'warehouse', label: 'Warehouse', width: 1.4),
        ExportColumn(
          key: 'quantity',
          label: 'Quantity',
          type: ExportValueType.decimal,
        ),
        ExportColumn(
          key: 'available',
          label: 'Available',
          type: ExportValueType.decimal,
        ),
        ExportColumn(
          key: 'projected',
          label: 'Projected',
          type: ExportValueType.decimal,
        ),
        ExportColumn(key: 'unit', label: 'Unit'),
        ExportColumn(
          key: 'purchasePrice',
          label: 'Purchase price',
          type: ExportValueType.money,
        ),
        ExportColumn(
          key: 'landedCost',
          label: 'Landed cost',
          type: ExportValueType.money,
        ),
        ExportColumn(
          key: 'averageCost',
          label: 'Average cost',
          type: ExportValueType.money,
        ),
        ExportColumn(
          key: 'salePrice',
          label: 'Sale price',
          type: ExportValueType.money,
        ),
        ExportColumn(key: 'costCurrency', label: 'Cost currency'),
        ExportColumn(key: 'saleCurrency', label: 'Sale currency'),
        ExportColumn(key: 'performedBy', label: 'Performed by'),
        ExportColumn(
          key: 'exportedAt',
          label: 'Date / time',
          type: ExportValueType.dateTime,
        ),
      ],
      rows: rows,
    );
  }

  Future<void> _showProductDetails(
    InventoryController controller,
    InventoryModel item,
  ) async {
    List<String> images = const <String>[];
    List<WarehouseStockModel> stocks = const <WarehouseStockModel>[];
    Map<String, Object?> maintenanceCard = const <String, Object?>{};
    var imagesLoadFailed = false;
    var stocksLoadFailed = false;
    var maintenanceLoadFailed = false;
    try {
      images = await controller.getProductImages(item.id);
    } catch (_) {
      imagesLoadFailed = true;
    }
    try {
      stocks = await controller.getProductStocks(item.id);
    } catch (_) {
      stocksLoadFailed = true;
    }
    try {
      maintenanceCard = await controller.getProductMaintenanceCard(item.id);
    } catch (_) {
      maintenanceLoadFailed = true;
    }
    if (!mounted) return;
    await showAppFloatingWindow<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(item.name),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 720),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (imagesLoadFailed ||
                    stocksLoadFailed ||
                    maintenanceLoadFailed) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AppText(
                      context.l10n.isArabic
                          ? 'تعذر تحميل بعض التفاصيل الإضافية. بيانات المنتج الأساسية ما زالت معروضة، ويمكن إعادة فتح النافذة للمحاولة مرة أخرى.'
                          : 'Some optional details could not be loaded. Core product data is still shown; reopen the dialog to retry.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _detailChip(
                      context.l10n.isArabic ? 'المجموعة' : 'Group',
                      item.category,
                    ),
                    _detailChip(
                      context.l10n.isArabic ? 'المتوفر' : 'Available',
                      '${item.quantity} ${item.unit}',
                    ),
                    _detailChip(
                      context.l10n.isArabic
                          ? 'الرصيد المتوقع'
                          : 'Projected balance',
                      '${item.expectedQuantity} ${item.unit}',
                    ),
                    _detailChip(
                      context.l10n.isArabic ? 'كلفة الشراء' : 'Purchase cost',
                      _money(
                        item.purchasePrice,
                        item.costCurrency ?? item.currency,
                      ),
                    ),
                    _detailChip(
                      context.l10n.isArabic
                          ? 'المصاريف المحمّلة'
                          : 'Landed expenses',
                      _money(
                        item.landedCost,
                        item.costCurrency ?? item.currency,
                      ),
                    ),
                    _detailChip(
                      context.l10n.isArabic ? 'الكلفة النهائية' : 'Final cost',
                      _money(item.unitCost, item.costCurrency ?? item.currency),
                    ),
                    _detailChip(
                      context.l10n.isArabic ? 'سعر البيع' : 'Sale price',
                      _money(
                        item.salePrice,
                        item.saleCurrency ?? item.currency,
                      ),
                    ),
                  ],
                ),
                if (stocks.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  AppText(
                    context.l10n.isArabic
                        ? 'الأرصدة حسب المخزن'
                        : 'Warehouse balances',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic ? 'المخزن' : 'Warehouse',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic ? 'الفعلية' : 'On hand',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic ? 'المحجوزة' : 'Reserved',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic ? 'المتاحة' : 'Available',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic
                                ? 'وارد متوقع'
                                : 'Expected in',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic
                                ? 'صادر متوقع'
                                : 'Expected out',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic
                                ? 'الرصيد المتوقع'
                                : 'Projected',
                          ),
                        ),
                        DataColumn(
                          label: AppText(
                            context.l10n.isArabic
                                ? 'متوسط الكلفة'
                                : 'Average cost',
                          ),
                        ),
                      ],
                      rows: stocks.map((stock) {
                        final warehouseMatches = controller.warehouses.where(
                          (warehouse) => warehouse.id == stock.warehouseId,
                        );
                        final warehouseName = warehouseMatches.isEmpty
                            ? stock.warehouseId
                            : warehouseMatches.first.name;
                        return DataRow(
                          cells: [
                            DataCell(AppText(warehouseName)),
                            DataCell(AppText('${stock.quantity}')),
                            DataCell(AppText('${stock.reservedQuantity}')),
                            DataCell(AppText('${stock.availableQuantity}')),
                            DataCell(AppText('${stock.expectedIncoming}')),
                            DataCell(AppText('${stock.expectedOutgoing}')),
                            DataCell(AppText('${stock.projectedQuantity}')),
                            DataCell(
                              AppText(
                                _money(
                                  stock.averageUnitCost,
                                  item.costCurrency ?? item.currency,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
                if (maintenanceCard.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _productMaintenanceHistory(maintenanceCard),
                ],
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  AppText(
                    context.l10n.isArabic ? 'صور المنتج' : 'Product images',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 170,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (_, index) {
                        final bytes = Base64ImageCache.instance.decode(
                          images[index],
                        );
                        if (bytes == null) {
                          return const SizedBox(
                            width: 220,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            bytes,
                            width: 220,
                            height: 170,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if ((item.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  AppText(
                    context.l10n.isArabic ? 'ملاحظات' : 'Notes',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  AppText(item.notes!),
                ],
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () async {
              final document = _productExportDocument(controller, item, stocks);
              final bytes = await ExcelExportService().build(document);
              await BinaryDownloadService.save(
                fileName:
                    'product_${item.id}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
                bytes: bytes,
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              );
            },
            icon: const Icon(Icons.table_view_outlined, size: 16),
            label: const AppText('Excel'),
          ),
          OutlinedButton.icon(
            onPressed: () => PdfExportService().save(
              _productExportDocument(controller, item, stocks),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const AppText('PDF'),
          ),
          OutlinedButton.icon(
            onPressed: maintenanceCard.isEmpty
                ? null
                : () => const ProductMaintenanceCardPdfService().printCard(
                    card: maintenanceCard,
                    arabic: context.l10n.isArabic,
                  ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: AppText(
              context.l10n.isArabic
                  ? 'طباعة بطاقة المادة'
                  : 'Print product card',
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _editProduct(controller, item);
            },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: AppText(context.l10n.isArabic ? 'تعديل' : 'Edit'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: AppText(context.l10n.isArabic ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Widget _productMaintenanceHistory(Map<String, Object?> card) {
    final arabic = context.l10n.isArabic;
    final history = _maintenanceMapRows(card['maintenanceHistory']);
    String t(String ar, String en) => arabic ? ar : en;
    String value(Object? raw) {
      final text = raw?.toString().trim() ?? '';
      return text.isEmpty || text.toLowerCase() == 'null' ? '—' : text;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.car_repair_outlined, size: 19),
            const SizedBox(width: 7),
            AppText(
              t('سجل الصيانة حسب السيارة', 'Maintenance history by vehicle'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AppText(
              t(
                'لا توجد سجلات صيانة مرتبطة بهذه المادة.',
                'No maintenance records are linked to this product.',
              ),
            ),
          )
        else
          ...history.map((order) {
            final warehouses = _maintenanceMapRows(
              order['warehouseContributions'],
            );
            final services = _maintenanceMapRows(order['relatedServices']);
            final carTitle = <String>[
              value(order['carNumber']),
              value(order['carName']),
            ].where((item) => item != '—').join(' • ');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: const Icon(Icons.directions_car_outlined),
                title: AppText(
                  '${value(order['orderNumber'])} • ${carTitle.isEmpty ? '—' : carTitle}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: AppText(
                  '${value(order['maintenanceDate'])} • ${value(order['customerName'])} • ${value(order['workflowStage'])}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _detailChip(
                        t('الشاصي', 'Chassis'),
                        value(order['chassis']),
                      ),
                      _detailChip(
                        t('اللوحة', 'Plate'),
                        value(order['plateNumber']),
                      ),
                      _detailChip(
                        t('المطلوب', 'Requested'),
                        value(order['requestedQuantity']),
                      ),
                      _detailChip(
                        t('المصروف', 'Issued'),
                        value(order['issuedQuantity']),
                      ),
                      _detailChip(
                        t('المرتجع', 'Reversed'),
                        value(order['reversedQuantity']),
                      ),
                      _detailChip(
                        t('المتبقي', 'Remaining'),
                        value(order['remainingQuantity']),
                      ),
                      _detailChip(
                        t('إذن الصرف', 'Stock issue'),
                        '${value(order['stockIssueNumber'])} / ${value(order['stockIssueStatus'])}',
                      ),
                      _detailChip(
                        t('الفاتورة', 'Invoice'),
                        '${value(order['invoiceNumber'])} / ${value(order['invoiceStatus'])}',
                      ),
                      _detailChip(
                        t('الدفع', 'Payment'),
                        value(order['paymentStatus']),
                      ),
                    ],
                  ),
                  if (warehouses.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppText(
                        t('مساهمة المخازن', 'Warehouse contributions'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: warehouses
                          .map(
                            (warehouse) => _detailChip(
                              value(warehouse['warehouseName']),
                              '${t('مصروف', 'Issued')}: ${value(warehouse['issuedQuantity'])} • ${t('مرتجع', 'Reversed')}: ${value(warehouse['reversedQuantity'])}',
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  if (services.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppText(
                        t('الخدمات المرتبطة', 'Related services'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    ...services.map(
                      (service) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.miscellaneous_services_outlined,
                          size: 18,
                        ),
                        title: AppText(value(service['name'])),
                        subtitle: AppText(
                          '${t('الكمية', 'Quantity')}: ${value(service['quantity'])}',
                        ),
                      ),
                    ),
                  ],
                  if (value(order['notes']) != '—')
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppText(
                        '${t('ملاحظات', 'Notes')}: ${value(order['notes'])}',
                      ),
                    ),
                  if (value(order['cancelReason']) != '—')
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppText(
                        '${t('سبب الإلغاء', 'Cancellation reason')}: ${value(order['cancelReason'])}',
                      ),
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  static List<Map<String, Object?>> _maintenanceMapRows(Object? raw) =>
      raw is List
      ? raw
            .whereType<Map>()
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false)
      : const <Map<String, Object?>>[];

  Widget _detailChip(String label, String value) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          AppText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _money(num value, [String? currency]) {
    final formatted = NumberFormat('#,##0.##').format(value);
    return currency == null || currency.trim().isEmpty
        ? formatted
        : '$formatted ${currency.trim().toUpperCase()}';
  }

  Future<void> _showCreateWarehouse(
    InventoryController controller, {
    WarehouseModel? warehouse,
  }) async {
    final name = TextEditingController(text: warehouse?.name ?? '');
    final code = TextEditingController(text: warehouse?.code ?? '');
    final address = TextEditingController(text: warehouse?.address ?? '');
    final saved = await showAppFloatingWindow<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          warehouse == null
              ? (context.l10n.isArabic ? 'إضافة مخزن' : 'Add warehouse')
              : (context.l10n.isArabic ? 'تعديل المخزن' : 'Edit warehouse'),
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('اسم المخزن'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('رمز المخزن'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: address,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('العنوان'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(context.l10n.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: AppText(context.l10n.isArabic ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (saved == true &&
        name.text.trim().isNotEmpty &&
        code.text.trim().isNotEmpty) {
      final value = WarehouseModel(
        id: warehouse?.id ?? const Uuid().v4(),
        code: code.text.trim().toUpperCase(),
        name: name.text.trim(),
        address: address.text.trim(),
        isActive: warehouse?.isActive ?? true,
      );
      if (warehouse == null) {
        await controller.createWarehouse(value);
      } else {
        await controller.updateWarehouse(value);
      }
    }
  }

  Future<void> _showCreateGroup(
    InventoryController controller, {
    InventoryGroupModel? group,
  }) async {
    final name = TextEditingController(text: group?.name ?? '');
    final code = TextEditingController(text: group?.code ?? '');
    final saved = await showAppFloatingWindow<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          group == null
              ? (context.l10n.isArabic
                    ? 'إضافة مجموعة مخزنية'
                    : 'Add inventory group')
              : (context.l10n.isArabic
                    ? 'تعديل المجموعة المخزنية'
                    : 'Edit inventory group'),
        ),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('اسم المجموعة'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: code,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('رمز المجموعة'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(context.l10n.isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: AppText(context.l10n.isArabic ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (saved == true &&
        name.text.trim().isNotEmpty &&
        code.text.trim().isNotEmpty) {
      final value = InventoryGroupModel(
        id: group?.id ?? const Uuid().v4(),
        code: code.text.trim().toUpperCase(),
        name: name.text.trim(),
      );
      if (group == null) {
        await controller.createGroup(value);
      } else {
        await controller.updateGroup(value);
      }
    }
  }

  Future<void> _showWarehousesManager(InventoryController controller) async {
    await showAppFloatingWindow<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          context.l10n.isArabic ? 'إدارة المخازن' : 'Warehouse management',
        ),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 620),
          height: 420,
          child: ListView(
            children: controller.warehouses
                .map(
                  (warehouse) => ListTile(
                    leading: const Icon(Icons.warehouse_outlined),
                    title: AppText(warehouse.name),
                    subtitle: AppText(
                      '${warehouse.code} • ${warehouse.address}',
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: AppTranslation.translate('تعديل'),
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await _showCreateWarehouse(
                              controller,
                              warehouse: warehouse,
                            );
                          },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: AppTranslation.translate('حذف'),
                          onPressed: () async {
                            try {
                              await controller.deleteWarehouse(warehouse.id);
                              if (dialogContext.mounted)
                                Navigator.pop(dialogContext);
                            } catch (error) {
                              if (mounted)
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
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: AppText(context.l10n.isArabic ? 'إغلاق' : 'Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _showCreateWarehouse(controller);
            },
            icon: const Icon(Icons.add),
            label: AppText(
              context.l10n.isArabic ? 'إضافة مخزن' : 'Add warehouse',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupsManager(InventoryController controller) async {
    await showAppFloatingWindow<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          context.l10n.isArabic
              ? 'إدارة المجموعات المخزنية'
              : 'Inventory group management',
        ),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 620),
          height: 420,
          child: ListView(
            children: controller.groups
                .map(
                  (group) => ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: AppText(group.name),
                    subtitle: AppText(group.code),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: AppTranslation.translate('تعديل'),
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await _showCreateGroup(controller, group: group);
                          },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: AppTranslation.translate('حذف'),
                          onPressed: () async {
                            try {
                              await controller.deleteGroup(group.id);
                              if (dialogContext.mounted)
                                Navigator.pop(dialogContext);
                            } catch (error) {
                              if (mounted)
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
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: AppText(context.l10n.isArabic ? 'إغلاق' : 'Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _showCreateGroup(controller);
            },
            icon: const Icon(Icons.add),
            label: AppText(
              context.l10n.isArabic ? 'إضافة مجموعة' : 'Add group',
            ),
          ),
        ],
      ),
    );
  }
}
