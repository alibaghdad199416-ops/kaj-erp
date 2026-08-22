import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:flutter/material.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/unified_document_details_dialog.dart';
import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_movement_model.dart';
import 'package:quality_line_erp/features/inventory/pages/product_warehouse_transfers_page.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:provider/provider.dart';

class InventoryMovementsPage extends StatelessWidget {
  InventoryMovementsPage({super.key});

  final InventoryRepository _repository = InventoryRepository();

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'inventory',
    field: field,
    viewPermission: 'inventory.view',
    child: child,
  );

  bool _can(BuildContext context, String field) => context
      .read<AccessController>()
      .canViewField('inventory', field, viewPermission: 'inventory.view');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: AppText(
          context.l10n.isArabic
              ? 'سجل الحركات المخزنية'
              : 'Inventory movement log',
        ),
      ),
      body: FutureBuilder<List<InventoryMovementModel>>(
        future: _repository.getMovementHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const KajInventoryLoadingState();
          }
          if (snapshot.hasError) {
            return Center(
              child: AppText(
                userFacingError(
                  snapshot.error!,
                  isArabic: context.l10n.isArabic,
                  arabicFallback: 'تعذر تحميل الحركات.',
                  englishFallback: 'Unable to load inventory movements.',
                ),
              ),
            );
          }
          final movements = snapshot.data ?? const <InventoryMovementModel>[];
          final canViewDate = _can(context, 'operationalDate');
          final canViewReference = _can(context, 'movementReference');
          final canViewProduct = _can(context, 'transferItem');
          final canViewWarehouse = _can(context, 'warehouseId');
          final canViewQuantity = _can(context, 'quantity');
          final canViewCost = _can(context, 'movementCost');
          final canViewAudit = _can(context, 'auditMetadata');
          final canViewType = _can(context, 'movementType');
          final canViewNumber = _can(context, 'movementNumber');

          final exportDocument = ExportDocument(
            title: 'Inventory Movement Log',
            language: 'en',
            columns: <ExportColumn>[
              if (canViewDate)
                ExportColumn(
                  key: 'date',
                  label: 'Date / Time',
                  type: ExportValueType.dateTime,
                ),
              if (canViewNumber)
                ExportColumn(key: 'movement', label: 'Movement no.'),
              if (canViewType)
                ExportColumn(key: 'type', label: 'Movement type'),
              if (canViewReference)
                ExportColumn(key: 'reference', label: 'Source document'),
              if (canViewProduct) ...[
                ExportColumn(key: 'product', label: 'Product'),
                ExportColumn(key: 'code', label: 'Product code'),
              ],
              if (canViewWarehouse) ...[
                ExportColumn(key: 'from', label: 'From'),
                ExportColumn(key: 'to', label: 'To'),
              ],
              if (canViewQuantity)
                ExportColumn(
                  key: 'quantity',
                  label: 'Quantity',
                  type: ExportValueType.decimal,
                ),
              if (canViewCost) ...[
                ExportColumn(
                  key: 'unitCost',
                  label: 'Unit cost',
                  type: ExportValueType.money,
                ),
                ExportColumn(
                  key: 'totalCost',
                  label: 'Total value',
                  type: ExportValueType.money,
                ),
                ExportColumn(key: 'currency', label: 'Currency'),
              ],
              if (canViewAudit)
                ExportColumn(key: 'user', label: 'Performed by'),
            ],
            rows: movements
                .map(
                  (movement) => <Object?>[
                    if (canViewDate) DateTime.tryParse(movement.movementDate),
                    if (canViewNumber) movement.movementNumber,
                    if (canViewType) movement.typeLabel,
                    if (canViewReference)
                      movement.referenceDocumentNumber ??
                          movement.referenceId ??
                          '',
                    if (canViewProduct) ...[
                      movement.productName,
                      movement.productCode,
                    ],
                    if (canViewWarehouse) ...[
                      movement.sourceName ?? '',
                      movement.destinationName ?? movement.warehouseName,
                    ],
                    if (canViewQuantity) movement.quantity,
                    if (canViewCost) ...[
                      movement.unitCost,
                      movement.totalCost,
                      movement.currency,
                    ],
                    if (canViewAudit) movement.performedBy ?? '',
                  ],
                )
                .toList(growable: false),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: movements.isEmpty
                            ? null
                            : () => ExcelExportService().save(exportDocument),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const AppText('Excel'),
                      ),
                      OutlinedButton.icon(
                        onPressed: movements.isEmpty
                            ? null
                            : () => PdfExportService().save(exportDocument),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const AppText('PDF'),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.swap_horiz_rounded),
                    title: AppText(
                      context.l10n.isArabic
                          ? 'نقل المنتجات يظهر كسند واحد'
                          : 'Product transfers are shown as one document',
                    ),
                    subtitle: AppText(
                      context.l10n.isArabic
                          ? 'حركتا المصدر والمستلم محفوظتان للتدقيق فقط. افتح السندات الموحدة للتعديل والطباعة والحذف.'
                          : 'Source and destination movements remain audit rows only. Open unified documents to edit, print, or delete.',
                    ),
                    trailing: FilledButton.icon(
                      onPressed: () => showAppWorkspaceDialog<void>(
                        context: context,
                        child: const ProductWarehouseTransfersPage(),
                      ),
                      icon: const Icon(Icons.description_outlined),
                      label: AppText(
                        context.l10n.isArabic
                            ? 'السندات الموحدة'
                            : 'Unified documents',
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: movements.isEmpty
                    ? Center(
                        child: AppText(
                          context.l10n.isArabic
                              ? 'لا توجد حركات مخزنية مستقلة'
                              : 'No independent inventory movements',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: movements.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final movement = movements[index];
                          final color = movement.isIncoming
                              ? Colors.green
                              : Colors.orange;
                          return Card(
                            child: ListTile(
                              onTap: () =>
                                  _showMovementDetails(context, movement),
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: .12),
                                child: Icon(
                                  movement.isIncoming
                                      ? Icons.south_west_rounded
                                      : Icons.north_east_rounded,
                                  color: color,
                                ),
                              ),
                              title: _field(
                                'transferItem',
                                AppText(
                                  movement.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              subtitle: Wrap(
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  _field(
                                    'movementType',
                                    AppText(movement.typeLabel),
                                  ),
                                  _field(
                                    'warehouseId',
                                    AppText(
                                      '${movement.sourceName ?? '-'} → ${movement.destinationName ?? movement.warehouseName}',
                                    ),
                                  ),
                                  _field(
                                    'movementNumber',
                                    AppText(movement.movementNumber),
                                  ),
                                ],
                              ),
                              trailing: SizedBox(
                                width: 270,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _field(
                                      'quantity',
                                      _value(
                                        context.l10n.isArabic
                                            ? 'الكمية'
                                            : 'Quantity',
                                        movement.quantity.toString(),
                                      ),
                                    ),
                                    _field(
                                      'movementCost',
                                      _value(
                                        context.l10n.isArabic
                                            ? 'كلفة الوحدة'
                                            : 'Unit cost',
                                        MoneyFormatter.format(
                                          movement.unitCost,
                                          currency: movement.currency,
                                        ),
                                      ),
                                    ),
                                    _field(
                                      'movementCost',
                                      _value(
                                        context.l10n.isArabic
                                            ? 'الإجمالي'
                                            : 'Total',
                                        MoneyFormatter.format(
                                          movement.totalCost,
                                          currency: movement.currency,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMovementDetails(
    BuildContext context,
    InventoryMovementModel movement,
  ) {
    final arabic = context.l10n.isArabic;
    return showUnifiedDocumentDetails(
      context: context,
      title: arabic ? 'حركة مخزنية' : 'Inventory movement',
      documentNumber: _can(context, 'movementNumber')
          ? movement.movementNumber
          : '—',
      status: _can(context, 'movementType')
          ? (movement.isIncoming
                ? (arabic ? 'وارد' : 'Incoming')
                : (arabic ? 'صادر' : 'Outgoing'))
          : '—',
      icon: Icons.inventory_2_outlined,
      sections: [
        UnifiedDocumentSection(
          title: arabic ? 'بيانات الحركة' : 'Movement details',
          fields: [
            if (_can(context, 'movementType'))
              UnifiedDocumentField(
                arabic ? 'النوع' : 'Type',
                movement.typeLabel,
              ),
            if (_can(context, 'operationalDate'))
              UnifiedDocumentField(
                arabic ? 'التاريخ' : 'Date / Time',
                movement.movementDate,
              ),
            if (_can(context, 'warehouseId')) ...[
              UnifiedDocumentField(arabic ? 'من' : 'From', movement.sourceName),
              UnifiedDocumentField(
                arabic ? 'إلى' : 'To',
                movement.destinationName ?? movement.warehouseName,
              ),
            ],
            if (_can(context, 'quantity'))
              UnifiedDocumentField(
                arabic ? 'الكمية' : 'Quantity',
                movement.quantity,
              ),
          ],
        ),
        UnifiedDocumentSection(
          title: arabic ? 'بيانات المنتج والكلفة' : 'Product and cost',
          fields: [
            if (_can(context, 'transferItem'))
              UnifiedDocumentField(
                arabic ? 'اسم المنتج' : 'Product',
                movement.productName,
              ),
            if (_can(context, 'movementCost'))
              UnifiedDocumentField(
                arabic ? 'كلفة الوحدة' : 'Unit cost',
                MoneyFormatter.format(
                  movement.unitCost,
                  currency: movement.currency,
                ),
              ),
            if (_can(context, 'movementCost'))
              UnifiedDocumentField(
                arabic ? 'الإجمالي' : 'Total cost',
                MoneyFormatter.format(
                  movement.totalCost,
                  currency: movement.currency,
                ),
              ),
          ],
        ),
        UnifiedDocumentSection(
          title: arabic ? 'المرجع والملاحظات' : 'Reference and notes',
          fields: [
            if (_can(context, 'movementReference'))
              UnifiedDocumentField(
                arabic ? 'نوع المرجع' : 'Reference type',
                movement.referenceType,
              ),
            if (_can(context, 'movementReference')) ...[
              UnifiedDocumentField(
                arabic ? 'رقم المرجع' : 'Reference number',
                movement.referenceDocumentNumber ?? movement.referenceId,
              ),
              UnifiedDocumentField(
                arabic ? 'معرف المرجع' : 'Reference ID',
                movement.referenceId,
              ),
            ],
            if (_can(context, 'auditMetadata'))
              UnifiedDocumentField(
                arabic ? 'المستخدم' : 'Performed by',
                movement.performedBy,
              ),
            if (_can(context, 'notes'))
              UnifiedDocumentField(
                arabic ? 'الملاحظات' : 'Notes',
                movement.notes,
              ),
            if (_can(context, 'auditMetadata') &&
                movement.auditUpdatedAt != null)
              UnifiedDocumentField(
                arabic ? 'آخر تحديث سحابي' : 'Last cloud update',
                movement.auditUpdatedAt!.toLocal().toIso8601String(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _value(String label, String value) {
    return SizedBox(
      width: 86,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            label,
            style: const TextStyle(fontSize: 9.5, color: Colors.grey),
          ),
          AppText(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
