import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/design_system/kaj_phase4_components.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/partner_compact_card_parts.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';

class SupplierCard extends StatelessWidget {
  const SupplierCard({super.key, required this.supplier, this.onView, required this.onEdit, required this.onDelete, required this.onToggleStatus});
  final SupplierModel supplier;
  final VoidCallback? onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleStatus;

  Widget _visible(String field, Widget child) => FieldPermissionVisibility(
    resource: 'suppliers', field: field, viewPermission: 'suppliers.view', child: child,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String t(String ar, String en) => context.l10n.isArabic ? ar : en;
    final statusColor = supplier.isActive ? Colors.green : scheme.outline;
    return KajPartnerCardShell(
      accent: statusColor,
      onTap: onView ?? onEdit,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 500;
          final avatar = _visible('photo', ClipOval(child: SizedBox(
            width: compact ? 42 : 48, height: compact ? 42 : 48,
            child: _photoBytes == null
                ? ColoredBox(color: scheme.secondary.withValues(alpha: .08), child: Center(child: AppText(_initials, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))))
                : Image.memory(_photoBytes!, fit: BoxFit.cover, gaplessPlayback: true),
          )));
          final identity = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _visible('name', AppText(supplier.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900))),
            const SizedBox(height: 3),
            _visible('isActive', PartnerStatusBadge(label: supplier.isActive ? t('مورد نشط', 'Active supplier') : t('مورد متوقف', 'Inactive supplier'), color: statusColor)),
          ]);
          final info = Wrap(spacing: 5, runSpacing: 4, children: [
            _visible('companyName', PartnerCompactValue(t('الشركة', 'Company'), supplier.companyName)),
            _visible('phone', PartnerCompactValue(t('الهاتف', 'Phone'), supplier.phone)),
            _visible('address', PartnerCompactValue(t('العنوان', 'Address'), supplier.address)),
            _visible('openingBalance', PartnerCompactValue(t('الرصيد', 'Balance'), '${_amount(supplier.openingBalance)} ${supplier.currency}')),
          ]);
          final actions = Wrap(spacing: 2, runSpacing: 2, children: [
            if (onView != null) PartnerCompactAction(Icons.visibility_outlined, t('البطاقة', 'Details'), onView!),
            PartnerCompactAction(Icons.edit_outlined, t('تعديل', 'Edit'), onEdit),
            PartnerCompactAction(supplier.isActive ? Icons.pause_circle_outline : Icons.check_circle_outline, supplier.isActive ? t('تعطيل', 'Disable') : t('تفعيل', 'Enable'), onToggleStatus),
            PartnerCompactAction(Icons.delete_outline, t('حذف', 'Delete'), onDelete, destructive: true),
          ]);
          if (compact) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar, const SizedBox(width: 8), Expanded(child: identity)]),
              const SizedBox(height: 6), info, const SizedBox(height: 4), actions,
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            avatar, const SizedBox(width: 9),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [identity, const SizedBox(height: 5), info])),
            const SizedBox(width: 8), actions,
          ]);
        }),
      ),
    );
  }

  String _amount(double value) {
    final result = value.toStringAsFixed(2);
    return result.endsWith('.00') ? result.substring(0, result.length - 3) : result;
  }

  Uint8List? get _photoBytes {
    final value = supplier.photoBase64;
    if (value == null || value.trim().isEmpty) return null;
    try { return base64Decode(value.contains(',') ? value.substring(value.indexOf(',') + 1) : value); } catch (_) { return null; }
  }

  String get _initials {
    final parts = supplier.name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'.toUpperCase();
  }
}
