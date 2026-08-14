#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
pending: dict[Path, str] = {}
failures: list[str] = []
changes: list[str] = []


def load(rel: str) -> str:
    path = root / rel
    if not path.exists():
        failures.append(f"missing file: {rel}")
        return ""
    return path.read_text(encoding="utf-8")


def stage(rel: str, text: str) -> None:
    pending[root / rel] = text


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        failures.append(f"{label}: expected one anchor, found {count}")
        return text
    changes.append(label)
    return text.replace(old, new, 1)


def insert_before_once(text: str, anchor: str, insertion: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(anchor)
    if count != 1:
        failures.append(f"{label}: expected one anchor, found {count}")
        return text
    changes.append(label)
    return text.replace(anchor, insertion + anchor, 1)


def patch_pdf_text(rel: str, import_line: str | None = None) -> None:
    text = load(rel)
    if not text:
        return
    if import_line and "pdf_text_support.dart" not in text:
        anchor = "import 'package:pdf/widgets.dart' as pw;\n"
        if anchor not in text:
            failures.append(f"{rel}: cannot add PdfTextSupport import")
            return
        text = text.replace(anchor, anchor + import_line + "\n", 1)
        changes.append(f"{rel}: add PdfTextSupport import")
    count = text.count("pw.Text(")
    if count:
        text = text.replace("pw.Text(", "PdfTextSupport.text(")
        changes.append(f"{rel}: route {count} text widgets through explicit RTL helper")
    stage(rel, text)


# ---------------------------------------------------------------------------
# Repository/controller product-maintenance-card read path.
# ---------------------------------------------------------------------------
rel = "lib/features/inventory/data/inventory_repository.dart"
text = load(rel)
method = """  Future<Map<String, Object?>> getProductMaintenanceCard(
    String productId,
  ) async {
    final result = await _client.rpc(
      'erp_r57_product_maintenance_card',
      params: <String, Object?>{
        'p_company_id': _companyId,
        'p_product_id': productId,
      },
    );
    return result is Map
        ? Map<String, Object?>.from(result)
        : const <String, Object?>{};
  }

"""
text = insert_before_once(
    text,
    "  Future<List<WarehouseModel>> getWarehouses({\n",
    method,
    "getProductMaintenanceCard(",
    f"{rel}: add product maintenance card RPC",
)
stage(rel, text)

rel = "lib/features/inventory/controllers/inventory_controller.dart"
text = load(rel)
method = """  Future<Map<String, Object?>> getProductMaintenanceCard(
    String productId,
  ) {
    return _repository.getProductMaintenanceCard(productId);
  }

"""
text = insert_before_once(
    text,
    "  Future<List<WarehouseStockModel>> getProductStocks(String productId) {\n",
    method,
    "getProductMaintenanceCard(",
    f"{rel}: expose product maintenance card",
)
stage(rel, text)

# ---------------------------------------------------------------------------
# Product details: load rich maintenance history, display it, print safe card.
# ---------------------------------------------------------------------------
rel = "lib/features/inventory/pages/inventory_page.dart"
text = load(rel)
if "product_maintenance_card_pdf_service.dart" not in text:
    text = replace_once(
        text,
        "import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';\n",
        "import 'package:quality_line_erp/core/printing/product_maintenance_card_pdf_service.dart';\n",
        f"{rel}: switch product PDF to safe maintenance card",
    )
elif "pdf_export_service.dart" in text:
    text = text.replace(
        "import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';\n",
        "",
        1,
    )

old = """    List<String> images = const <String>[];
    List<WarehouseStockModel> stocks = const <WarehouseStockModel>[];
    var imagesLoadFailed = false;
    var stocksLoadFailed = false;
"""
new = """    List<String> images = const <String>[];
    List<WarehouseStockModel> stocks = const <WarehouseStockModel>[];
    Map<String, Object?> maintenanceCard = const <String, Object?>{};
    var imagesLoadFailed = false;
    var stocksLoadFailed = false;
    var maintenanceLoadFailed = false;
"""
text = replace_once(text, old, new, f"{rel}: add maintenance-card load state")

old = """    try {
      stocks = await controller.getProductStocks(item.id);
    } catch (_) {
      stocksLoadFailed = true;
    }
    if (!mounted) return;
"""
new = """    try {
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
"""
text = replace_once(text, old, new, f"{rel}: load product maintenance history")

text = replace_once(
    text,
    "                if (imagesLoadFailed || stocksLoadFailed) ...[\n",
    "                if (imagesLoadFailed || stocksLoadFailed || maintenanceLoadFailed) ...[\n",
    f"{rel}: surface optional maintenance load failure",
)

history_insert = """                if (maintenanceCard.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _productMaintenanceHistory(maintenanceCard),
                ],
"""
text = insert_before_once(
    text,
    "                if (images.isNotEmpty) ...[\n",
    history_insert,
    "_productMaintenanceHistory(maintenanceCard)",
    f"{rel}: render product maintenance history",
)

old = """          OutlinedButton.icon(
            onPressed: () => PdfExportService().save(
              _productExportDocument(controller, item, stocks),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const AppText('PDF'),
          ),
"""
new = """          OutlinedButton.icon(
            onPressed: maintenanceCard.isEmpty
                ? null
                : () => const ProductMaintenanceCardPdfService().printCard(
                    card: maintenanceCard,
                    arabic: context.l10n.isArabic,
                  ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: AppText(
              context.l10n.isArabic ? 'طباعة بطاقة المادة' : 'Print product card',
            ),
          ),
"""
text = replace_once(text, old, new, f"{rel}: print privacy-safe product maintenance card")

helper = r"""  Widget _productMaintenanceHistory(Map<String, Object?> card) {
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

"""
text = insert_before_once(
    text,
    "  Widget _detailChip(String label, String value) {\n",
    helper,
    "Widget _productMaintenanceHistory(",
    f"{rel}: add maintenance history widgets",
)
stage(rel, text)

# ---------------------------------------------------------------------------
# Car-card RenderFlex stripe: the old fixed grid height was smaller than the
# content (chips + actions). Keep cards fixed for scroll performance but give
# them enough height at every responsive column count.
# ---------------------------------------------------------------------------
rel = "lib/features/inventory/cars/pages/cars_page.dart"
text = load(rel)
old = """                    mainAxisExtent: columns == 3
                        ? 168
                        : columns == 2
                        ? 176
                        : 188,
"""
new = """                    mainAxisExtent: columns == 3
                        ? 260
                        : columns == 2
                        ? 235
                        : 215,
"""
text = replace_once(text, old, new, f"{rel}: remove car-card RenderFlex overflow stripe")
stage(rel, text)

# ---------------------------------------------------------------------------
# Inventory movement labels for reversals/returns.
# ---------------------------------------------------------------------------
rel = "lib/features/inventory/models/inventory_movement_model.dart"
text = load(rel)
old = """      case 'purchase_in':
        return 'شراء / إدخال';
      case 'sale_out':
        return 'بيع منتج';
      case 'maintenance_out':
        return 'سحب للصيانة';
"""
new = """      case 'purchase_in':
      case 'purchase':
      case 'purchase_receipt':
        return 'شراء / إدخال';
      case 'purchase_cancel':
      case 'purchase_return':
      case 'purchase_reversal':
        return 'عكس / مرتجع شراء';
      case 'sale_out':
      case 'sale':
      case 'sales_out':
        return 'بيع منتج';
      case 'sale_cancel':
      case 'sale_return':
      case 'sale_reversal':
        return 'عكس / مرتجع بيع';
      case 'maintenance_out':
        return 'سحب للصيانة';
      case 'maintenance_return':
        return 'عكس / مرتجع صيانة';
"""
text = replace_once(text, old, new, f"{rel}: label operational reversals")
stage(rel, text)

# ---------------------------------------------------------------------------
# Arabic PDF: force every normal text widget in the main PDF surfaces through
# PdfTextSupport.text(), which sets RTL/LTR per string and uses bundled Arabic
# fonts. This preserves all local layout/branding modifications.
# ---------------------------------------------------------------------------
patch_pdf_text(
    "lib/core/printing/maintenance_document_pdf_service.dart",
    "import 'package:quality_line_erp/core/printing/pdf_text_support.dart';",
)
patch_pdf_text(
    "lib/core/printing/enterprise_document_pdf_service.dart",
    "import 'package:quality_line_erp/core/printing/pdf_text_support.dart';",
)
patch_pdf_text(
    "lib/core/printing/warehouse_transfer_pdf_service.dart",
    "import 'package:quality_line_erp/core/printing/pdf_text_support.dart';",
)
patch_pdf_text(
    "lib/core/printing/vehicle_service_card_pdf_service.dart",
    "import 'package:quality_line_erp/core/printing/pdf_text_support.dart';",
)
patch_pdf_text(
    "lib/core/exporting/pdf_export_service.dart",
    "import '../printing/pdf_text_support.dart';",
)
patch_pdf_text(
    "lib/core/exporting/adaptive_pdf_table.dart",
    "import '../printing/pdf_text_support.dart';",
)

# If warehouse-transfer still contains the known RichText label/value helper,
# collapse that one Arabic-sensitive span to the shaping helper.
rel = "lib/core/printing/warehouse_transfer_pdf_service.dart"
text = pending.get(root / rel, load(rel))
old = """      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(font: bold),
            ),
            pw.TextSpan(text: value),
          ],
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
"""
new = """      child: PdfTextSupport.text(
        '$label: $value',
        style: pw.TextStyle(font: bold, fontSize: 8),
      ),
"""
if old in text:
    text = text.replace(old, new, 1)
    changes.append(f"{rel}: shape Arabic warehouse label/value rows")
stage(rel, text)

# ---------------------------------------------------------------------------
# Validation: fail before writing if any core anchor was missing.
# ---------------------------------------------------------------------------
if failures:
    print("R57 patch NOT applied. Nothing was written.", file=sys.stderr)
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    sys.exit(1)

# Validate privacy boundary and new artifacts before touching the tree.
migration = root / "supabase/migrations/20260813013000_r57_inventory_movement_product_maintenance_card_semantics.sql"
service = root / "lib/core/printing/product_maintenance_card_pdf_service.dart"
for path in (migration, service):
    if not path.exists():
        print(f"R57 patch NOT applied: missing packaged artifact {path}", file=sys.stderr)
        sys.exit(1)

service_text = service.read_text(encoding="utf-8")
for forbidden in (
    "unitCost",
    "actualCost",
    "fifoCost",
    "laborCost",
    "partsCost",
    "totalCost",
    "profit",
    "purchasePrice",
    "maintenanceCost",
    "carCost",
):
    if f"'{forbidden}'" in service_text or f'"{forbidden}"' in service_text:
        print(
            f"R57 patch NOT applied: product maintenance PDF exposes forbidden field {forbidden}",
            file=sys.stderr,
        )
        sys.exit(1)

for path, text in pending.items():
    path.write_text(text, encoding="utf-8")

print("R57 inventory/product/PDF/UI patch applied.")
for change in changes:
    print(f"PASS {change}")
print(f"PASS files updated: {len(pending)}")
