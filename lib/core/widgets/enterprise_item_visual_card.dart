import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

class EnterpriseItemVisualCard extends StatelessWidget {
  const EnterpriseItemVisualCard({
    super.key,
    required this.title,
    required this.kind,
    required this.details,
    this.image,
  });

  final String title;
  final String kind;
  final Map<String, Object?> details;
  final String? image;

  bool get _isCar => kind == 'car';

  static const _ignoredKeys = <String>{
    'image',
    'imagePath',
    'imageBase64',
    'rawData',
    'payload',
    'id',
    'vehicleId',
    'vehicle_id',
    'productId',
    'product_id',
    'companyId',
    'company_id',
    'groupId',
    'group_id',
    'warehouseId',
    'warehouse_id',
  };

  String _valueFor(List<String> keys) {
    for (final key in keys) {
      final direct = details[key];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString().trim();
      }
      for (final entry in details.entries) {
        if (entry.key.toLowerCase() == key.toLowerCase() &&
            entry.value != null &&
            entry.value.toString().trim().isNotEmpty) {
          return entry.value.toString().trim();
        }
      }
    }
    return '';
  }

  String get _primaryNumber => _valueFor(
    _isCar
        ? const ['carNumber', 'vehicleNumber', 'registrationNumber']
        : const ['code', 'productCode', 'itemCode', 'sku', 'barcode'],
  );

  String get _secondaryNumber => _valueFor(
    _isCar ? const ['chassis', 'chassisNumber', 'vin'] : const <String>[],
  );

  String get _salePrice =>
      _valueFor(const ['salePrice', 'sellingPrice', 'price', 'unitPrice']);

  String get _costPrice => _valueFor(const [
    'purchasePrice',
    'unitCost',
    'costPrice',
    'baseCost',
    'cost',
  ]);

  List<MapEntry<String, Object?>> get _extraEntries =>
      details.entries
          .where((entry) {
            if (_ignoredKeys.contains(entry.key)) return false;
            if (!_isCar &&
                {
                  'code',
                  'productcode',
                  'itemcode',
                  'description',
                  'englishname',
                }.contains(entry.key.toLowerCase())) {
              return false;
            }
            final value = entry.value?.toString().trim() ?? '';
            if (value.isEmpty) return false;
            final normalized = entry.key.toLowerCase();
            return !{
              'platenumber',
              'plate',
              'registrationnumber',
              'carnumber',
              'chassis',
              'chassisnumber',
              'vin',
              'barcode',
              'sku',
              'internalcode',
              'serialnumber',
              'saleprice',
              'sellingprice',
              'price',
              'unitprice',
              'purchaseprice',
              'unitcost',
              'costprice',
              'basecost',
              'cost',
              'id',
              'warehouseid',
              'groupid',
              'supplierid',
              'customerid',
              'vehicleid',
              'productid',
              'invoiceid',
              'branchid',
              'imagepath',
              'filepath',
              'uuid',
            }.contains(normalized);
          })
          .toList(growable: false)
        ..sort((a, b) => _labelForKey(a.key).compareTo(_labelForKey(b.key)));

  static String _labelForKey(String key) {
    const labels = <String, String>{
      'code': 'الرمز',
      'name': 'الاسم',
      'brand': 'الماركة',
      'model': 'الموديل',
      'year': 'السنة',
      'color': 'اللون',
      'status': 'الحالة',
      'warehouseName': 'المخزن',
      'category': 'المجموعة',
      'unit': 'وحدة القياس',
      'quantity': 'الكمية الفعلية',
      'available': 'الكمية المتاحة',
      'availableQuantity': 'الكمية المتاحة',
      'expectedIncoming': 'الوارد المتوقع',
      'expectedOutgoing': 'الصادر المتوقع',
      'expectedQuantity': 'الرصيد المتوقع',
      'minQuantity': 'حد إعادة الطلب',
      'notes': 'ملاحظات',
      'createdAt': 'تاريخ الإنشاء',
      'updatedAt': 'تاريخ التعديل',
      'isActive': 'فعال',
      'active': 'فعال',
      'description': 'الوصف',
      'currency': 'العملة',
      'exchangeRate': 'سعر الصرف',
      'purchaseCurrency': 'عملة الشراء',
      'saleCurrency': 'عملة البيع',
      'engineNumber': 'رقم المحرك',
      'origin': 'المنشأ',
      'location': 'الموقع',
      'reservedQuantity': 'الكمية المحجوزة',
      'averageUnitCost': 'متوسط الكلفة',
      'totalValue': 'القيمة الإجمالية',
    };
    return labels[key] ?? AppTranslation.translate(key);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final border = KajDesignTokens.border(brightness);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: KajDesignTokens.space8),
      padding: const EdgeInsets.all(KajDesignTokens.space12),
      decoration: BoxDecoration(
        gradient: KajDesignTokens.surfaceGradient(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        border: Border.all(color: border),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final visual = ClipRRect(
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
            child: Container(
              width: compact ? double.infinity : 124,
              height: compact ? 150 : 94,
              decoration: BoxDecoration(
                color: KajDesignTokens.highestSurface(brightness),
                border: Border.all(
                  color: KajDesignTokens.electricBlue.withValues(alpha: .18),
                ),
              ),
              child: _VisualImage(image: image, isCar: _isCar),
            ),
          );

          final detailsPanel = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: AppText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: KajDesignTokens.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: KajDesignTokens.electricBlue.withValues(
                        alpha: .09,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: KajDesignTokens.electricBlue.withValues(
                          alpha: .22,
                        ),
                      ),
                    ),
                    child: AppText(
                      _isCar ? 'سيارة' : 'قطعة غيار',
                      style: const TextStyle(
                        color: KajDesignTokens.electricBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KajDesignTokens.space10),
              Wrap(
                spacing: KajDesignTokens.space6,
                runSpacing: KajDesignTokens.space6,
                children: <Widget>[
                  if (_primaryNumber.isNotEmpty)
                    _HighlightPill(
                      label: _isCar ? 'رقم السيارة' : 'رقم المادة',
                      value: _primaryNumber,
                      tone: KajDesignTokens.champagne,
                    ),
                  if (_secondaryNumber.isNotEmpty)
                    _HighlightPill(
                      label: 'رقم الشاصي',
                      value: _secondaryNumber,
                      tone: KajDesignTokens.electricBlue,
                    ),
                  if (_salePrice.isNotEmpty)
                    _HighlightPill(
                      label: 'سعر البيع',
                      value: _salePrice,
                      tone: KajDesignTokens.success,
                    ),
                  if (_costPrice.isNotEmpty)
                    _HighlightPill(
                      label: 'الكلفة',
                      value: _costPrice,
                      tone: KajDesignTokens.warning,
                    ),
                  ..._extraEntries
                      .take(6)
                      .map(
                        (entry) => _DetailTile(
                          label: _labelForKey(entry.key),
                          value: AppTranslation.translate(
                            entry.value?.toString() ?? '-',
                          ),
                        ),
                      ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                visual,
                const SizedBox(height: KajDesignTokens.space12),
                detailsPanel,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              visual,
              const SizedBox(width: KajDesignTokens.space12),
              Expanded(child: detailsPanel),
            ],
          );
        },
      ),
    );
  }
}

class _VisualImage extends StatelessWidget {
  const _VisualImage({required this.image, required this.isCar});

  final String? image;
  final bool isCar;

  @override
  Widget build(BuildContext context) {
    final value = image?.trim() ?? '';
    final fallback = Center(
      child: Icon(
        isCar ? Icons.directions_car_filled_rounded : Icons.inventory_2_rounded,
        size: 56,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    final Uint8List? bytes = AppImageService.decodeBase64(value);
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _HighlightPill extends StatelessWidget {
  const _HighlightPill({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 104),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(KajDesignTokens.radiusXs),
      border: Border.all(color: tone.withValues(alpha: .24)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppText(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: tone.withValues(alpha: .92),
          ),
        ),
        const SizedBox(height: 2),
        AppSelectableText(
          value,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.15,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    ),
  );
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 108, maxWidth: 210),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .36),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        AppSelectableText(
          value,
          style: TextStyle(
            fontSize: 10.5,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
