import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/features/business_partners/shared/data/business_partner_card_service.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class BusinessPartnerProfileField {
  const BusinessPartnerProfileField(this.label, this.value, {this.icon});
  final String label;
  final Object? value;
  final IconData? icon;
}

Future<void> showBusinessPartnerProfileDialog({
  required BuildContext context,
  required String title,
  required String accountingSectionTitle,
  required String paymentsSectionTitle,
  required String documentsSectionTitle,
  required String partnerId,
  required String partnerName,
  required String partnerType,
  required IconData icon,
  required Map<String, Object?> summary,
  String? photoBase64,
  List<BusinessPartnerProfileField> contactFields = const [],
  List<BusinessPartnerProfileField> identityFields = const [],
  String? notes,
  Future<void> Function(Map<String, Object?> record)? onOpenRecord,
}) => showAppWorkspaceDialogBuilder<void>(
  context: context,
  builder: (_) => _BusinessPartnerProfileDialog(
    title: title,
    accountingSectionTitle: accountingSectionTitle,
    paymentsSectionTitle: paymentsSectionTitle,
    documentsSectionTitle: documentsSectionTitle,
    partnerId: partnerId,
    partnerName: partnerName,
    partnerType: partnerType,
    icon: icon,
    summary: summary,
    photoBase64: photoBase64,
    contactFields: contactFields,
    identityFields: identityFields,
    notes: notes,
    onOpenRecord: onOpenRecord,
  ),
);

class _BusinessPartnerProfileDialog extends StatelessWidget {
  const _BusinessPartnerProfileDialog({
    required this.title,
    required this.accountingSectionTitle,
    required this.paymentsSectionTitle,
    required this.documentsSectionTitle,
    required this.partnerId,
    required this.partnerName,
    required this.partnerType,
    required this.icon,
    required this.summary,
    required this.photoBase64,
    required this.contactFields,
    required this.identityFields,
    required this.notes,
    required this.onOpenRecord,
  });

  final String title;
  final String accountingSectionTitle;
  final String paymentsSectionTitle;
  final String documentsSectionTitle;
  final String partnerId;
  final String partnerName;
  final String partnerType;
  final IconData icon;
  final Map<String, Object?> summary;
  final String? photoBase64;
  final List<BusinessPartnerProfileField> contactFields;
  final List<BusinessPartnerProfileField> identityFields;
  final String? notes;
  final Future<void> Function(Map<String, Object?> record)? onOpenRecord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final documents = BusinessPartnerCardService.documents(summary);
    final currencies = BusinessPartnerCardService.currencies(summary);
    return AlertDialog(
      insetPadding: const EdgeInsets.all(18),
      titlePadding: EdgeInsets.zero,
      contentPadding: EdgeInsets.zero,
      actionsPadding: const EdgeInsets.all(14),
      title: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.primaryContainer],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Row(
          children: [
            _Avatar(photoBase64: photoBase64, icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    AppTranslation.translate(title),
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: .78),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    partnerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  AppText(
                    '$partnerType • $partnerId',
                    style: TextStyle(
                      color: scheme.onPrimary.withValues(alpha: .8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: AppTranslation.translate('إغلاق'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, 1080),
        height: AppResponsive.dialogHeight(context, 700),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  'إجمالي التعامل',
                  _moneyByCurrency(summary['transactionTotalByCurrency']),
                  Icons.analytics_outlined,
                ),
                _Metric(
                  'إجمالي المدفوع',
                  _moneyByCurrency(summary['paidTotalByCurrency']),
                  Icons.payments_outlined,
                ),
                _Metric(
                  'الرصيد المستحق',
                  _moneyByCurrency(summary['outstandingTotalByCurrency']),
                  Icons.account_balance_wallet_outlined,
                  warning: _moneyMapHasPositive(
                    summary['outstandingTotalByCurrency'],
                  ),
                ),
                _Metric(
                  AppTranslation.translate('عدد العمليات'),
                  _integer(summary['transactionCount']),
                  Icons.receipt_long_outlined,
                ),
                _Metric(
                  AppTranslation.translate(paymentsSectionTitle),
                  _integer(summary['paymentCount']),
                  Icons.price_check_outlined,
                ),
                _Metric(
                  AppTranslation.translate('المستندات'),
                  _integer(summary['linkedDocumentCount']),
                  Icons.folder_copy_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (_, constraints) {
                final basic = _InfoCard(
                  title: AppTranslation.translate('الهوية والبيانات الأساسية'),
                  icon: Icons.badge_outlined,
                  fields: [
                    BusinessPartnerProfileField('نوع الشريك', partnerType),
                    BusinessPartnerProfileField(
                      AppTranslation.translate('معرّف السجل'),
                      partnerId,
                    ),
                    ...identityFields,
                  ],
                );
                final contact = _InfoCard(
                  title: AppTranslation.translate(accountingSectionTitle),
                  icon: Icons.contact_phone_outlined,
                  fields: [
                    ...contactFields,
                    BusinessPartnerProfileField(
                      'حساب الأستاذ المساعد',
                      summary['accountId'],
                    ),
                    BusinessPartnerProfileField(
                      'الرصيد الافتتاحي',
                      summary['openingBalance'],
                    ),
                    BusinessPartnerProfileField('العملات', currencies),
                  ],
                );
                if (constraints.maxWidth < 780) {
                  return Column(
                    children: [basic, const SizedBox(height: 10), contact],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: basic),
                    const SizedBox(width: 10),
                    Expanded(child: contact),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _Documents(title: documentsSectionTitle, documents: documents),
            if (partnerType.toLowerCase().contains('customer') ||
                partnerType.contains('عميل')) ...[
              const SizedBox(height: 14),
              _RelatedRecords(
                title: AppTranslation.translate('الفرص وإدارة علاقات العملاء'),
                icon: Icons.handshake_outlined,
                records: _records(summary['crmOpportunities']),
                primaryKeys: const ['opportunityNumber', 'title', 'id'],
                onOpenRecord: onOpenRecord,
              ),
              const SizedBox(height: 14),
              _RelatedRecords(
                title: AppTranslation.translate('سجل الصيانة'),
                icon: Icons.car_repair_outlined,
                records: _records(summary['maintenanceHistory']),
                primaryKeys: const ['orderNumber', 'carName', 'id'],
                onOpenRecord: onOpenRecord,
              ),
            ],
            const SizedBox(height: 14),
            _RelatedRecords(
              title: AppTranslation.translate(
                partnerType.toLowerCase().contains('supplier') ||
                        partnerType.contains('مورد')
                    ? 'سلسلة المشتريات'
                    : 'سلسلة المبيعات',
              ),
              icon: Icons.account_tree_outlined,
              records: _records(summary['commercialChain']),
              primaryKeys: const ['orderNumber', 'documentNumber', 'id'],
              onOpenRecord: onOpenRecord,
            ),
            const SizedBox(height: 14),
            _RelatedRecords(
              title: AppTranslation.translate(
                'Ø§Ù„Ø­Ø³Ø§Ø¨Ø§Øª Ø­Ø³Ø¨ Ø§Ù„Ø¹Ù…Ù„Ø©',
              ),
              icon: Icons.account_balance_outlined,
              records: _records(summary['accountsByCurrency']),
              primaryKeys: const ['accountName', 'currencyCode', 'accountId'],
            ),
            const SizedBox(height: 14),
            _RelatedRecords(
              title: AppTranslation.translate('Ø­Ø±ÙƒØ§Øª Ø§Ù„Ø£Ø³ØªØ§Ø°'),
              icon: Icons.menu_book_outlined,
              records: _records(summary['ledgerMovements']),
              primaryKeys: const ['entryNumber', 'description', 'entryId'],
            ),
            if ((notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        AppTranslation.translate('ملاحظات الشريك'),
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      AppSelectableText(notes!.trim()),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.check),
          label: AppText(AppTranslation.translate('إغلاق البطاقة')),
        ),
      ],
    );
  }

  static double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  static String _integer(Object? value) => _number(value).round().toString();
  static bool _moneyMapHasPositive(Object? raw) {
    if (raw is! Map) return false;
    return raw.values.any((value) => _number(value) > 0);
  }

  static String _moneyByCurrency(Object? raw) {
    if (raw is! Map || raw.isEmpty) return '—';
    final rows =
        raw.entries
            .where((entry) => entry.key.toString().trim().isNotEmpty)
            .map(
              (entry) => MapEntry(
                entry.key.toString().trim().toUpperCase(),
                _number(entry.value),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key));
    if (rows.isEmpty) return '—';
    return rows
        .map((entry) => MoneyFormatter.withCurrency(entry.value, entry.key))
        .join(' • ');
  }

  static List<Map<String, Object?>> _records(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList(growable: false)
      : const [];
}

class _RelatedRecords extends StatelessWidget {
  const _RelatedRecords({
    required this.title,
    required this.icon,
    required this.records,
    required this.primaryKeys,
    this.onOpenRecord,
  });
  final String title;
  final IconData icon;
  final List<Map<String, Object?>> records;
  final List<String> primaryKeys;
  final Future<void> Function(Map<String, Object?> record)? onOpenRecord;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: Icon(icon),
          title: AppText(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          trailing: Chip(label: AppText('${records.length}')),
        ),
        const Divider(height: 1),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: AppText(AppTranslation.translate('لا توجد سجلات مرتبطة.')),
          )
        else
          ...records.take(30).map((record) {
            final titleValue = primaryKeys
                .map((key) => record[key]?.toString().trim() ?? '')
                .firstWhere((value) => value.isNotEmpty, orElse: () => '—');
            final status = record['workflowStage'] ?? record['status'] ?? '';
            final date = record['maintenanceDate'] ?? record['createdAt'] ?? '';
            return ListTile(
              key: ValueKey(
                'related-${record['entityType'] ?? 'record'}-${record['id'] ?? record['accountId'] ?? titleValue}',
              ),
              leading: Icon(
                onOpenRecord == null
                    ? Icons.description_outlined
                    : Icons.open_in_new_outlined,
                size: 19,
              ),
              onTap: onOpenRecord == null
                  ? null
                  : () async => onOpenRecord!(record),
              title: AppSelectableText(
                titleValue,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: AppText(
                [date, status]
                    .map((value) => value.toString().trim())
                    .where((value) => value.isNotEmpty)
                    .join(' • '),
              ),
            );
          }),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoBase64, required this.icon});
  final String? photoBase64;
  final IconData icon;

  Uint8List? get bytes {
    var value = photoBase64?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('data:') && value.contains(',')) {
      value = value.substring(value.indexOf(',') + 1);
    }
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white, width: 3),
    ),
    child: bytes == null
        ? Icon(icon, size: 38)
        : Image.memory(
            bytes!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(icon, size: 38),
          ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.icon, {this.warning = false});
  final String title;
  final String value;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 168,
      child: Card(
        color: warning ? scheme.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: warning ? scheme.error : scheme.primary),
              const SizedBox(height: 8),
              AppText(
                title,
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
              AppText(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.fields,
  });
  final String title;
  final IconData icon;
  final List<BusinessPartnerProfileField> fields;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 7),
              AppText(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const Divider(height: 22),
          ...fields
              .where((f) => (f.value?.toString().trim() ?? '').isNotEmpty)
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(f.icon ?? Icons.chevron_right, size: 16),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 135,
                        child: AppText(
                          f.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: AppSelectableText(
                          f.value?.toString() ?? '—',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}

class _Documents extends StatelessWidget {
  const _Documents({required this.title, required this.documents});
  final String title;
  final List<Map<String, Object?>> documents;

  @override
  Widget build(BuildContext context) {
    const keys = [
      'document_number',
      'document_date',
      'status',
      'currency',
      'total_amount',
      'paid_amount',
      'outstanding_amount',
    ];
    final labels = [
      'المستند',
      'التاريخ',
      'الحالة',
      'العملة',
      'الإجمالي',
      'المدفوع',
      'المتبقي',
    ].map(AppTranslation.translate).toList(growable: false);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: AppText(
              AppTranslation.translate(title),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: AppText(
              AppTranslation.translate('عرض منظم للمستندات والدفعات المرتبطة.'),
            ),
          ),
          const Divider(height: 1),
          if (documents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: AppText(
                  AppTranslation.translate('لا توجد مستندات مرتبطة.'),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: labels
                    .map(
                      (label) => DataColumn(
                        label: AppText(
                          label,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    )
                    .toList(),
                rows: documents
                    .take(30)
                    .map(
                      (document) => DataRow(
                        cells: [
                          for (final key in keys)
                            DataCell(
                              AppText(
                                _value(
                                  document[key],
                                  numeric: const {
                                    'total_amount',
                                    'paid_amount',
                                    'outstanding_amount',
                                  }.contains(key),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  static String _value(Object? value, {bool numeric = false}) {
    if (numeric) {
      final number = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0;
      return NumberFormat('#,##0.##').format(number);
    }
    final text = value?.toString().trim() ?? '';
    return text.contains('T')
        ? text.split('T').first
        : (text.isEmpty ? '—' : text);
  }
}
