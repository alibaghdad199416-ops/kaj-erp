import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/design_system/kaj_phase4_components.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/business_partners/shared/widgets/partner_compact_card_parts.dart';

class CustomerCard extends StatelessWidget {
  const CustomerCard({
    super.key,
    required this.customer,
    this.onView,
    this.onEdit,
    this.onDelete,
  });
  final CustomerModel customer;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  Widget _visible(String field, Widget child) => FieldPermissionVisibility(
    resource: 'customers',
    field: field,
    viewPermission: 'customers.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String t(String ar, String en) => context.l10n.isArabic ? ar : en;
    return KajPartnerCardShell(
      accent: scheme.primary,
      onTap: onView ?? onEdit,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 480;
            final avatar = _visible(
              'photo',
              ClipOval(
                child: SizedBox(
                  width: compact ? 42 : 48,
                  height: compact ? 42 : 48,
                  child: _photoBytes == null
                      ? ColoredBox(
                          color: scheme.primary.withValues(alpha: .08),
                          child: Center(
                            child: AppText(
                              _initials,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        )
                      : Image.memory(
                          _photoBytes!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
              ),
            );
            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _visible(
                  'name',
                  AppText(
                    customer.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                PartnerStatusBadge(
                  label: t('عميل تجاري', 'Customer'),
                  color: scheme.primary,
                ),
              ],
            );
            final info = Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                _visible(
                  'phone',
                  PartnerCompactValue(t('الهاتف', 'Phone'), customer.phone),
                ),
                _visible(
                  'nationalId',
                  PartnerCompactValue(
                    t('الهوية', 'National ID'),
                    customer.nationalId,
                  ),
                ),
                _visible(
                  'address',
                  PartnerCompactValue(
                    t('العنوان', 'Address'),
                    customer.address,
                  ),
                ),
                _visible(
                  'createdAt',
                  PartnerCompactValue(
                    t('تاريخ الإنشاء', 'Created at'),
                    customer.createdAt,
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                if (onView != null)
                  PartnerCompactAction(
                    Icons.visibility_outlined,
                    t('البطاقة', 'Details'),
                    onView!,
                  ),
                if (onEdit != null)
                  PartnerCompactAction(
                    Icons.edit_outlined,
                    t('تعديل', 'Edit'),
                    onEdit!,
                  ),
                if (onDelete != null)
                  PartnerCompactAction(
                    Icons.delete_outline,
                    t('حذف', 'Delete'),
                    onDelete!,
                    destructive: true,
                  ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 8),
                      Expanded(child: identity),
                    ],
                  ),
                  const SizedBox(height: 6),
                  info,
                  const SizedBox(height: 4),
                  actions,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar,
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, const SizedBox(height: 5), info],
                  ),
                ),
                const SizedBox(width: 8),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Uint8List? get _photoBytes {
    final value = customer.photoBase64;
    if (value == null || value.trim().isEmpty) return null;
    try {
      return base64Decode(
        value.contains(',') ? value.substring(value.indexOf(',') + 1) : value,
      );
    } catch (_) {
      return null;
    }
  }

  String get _initials {
    final parts = customer.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}
