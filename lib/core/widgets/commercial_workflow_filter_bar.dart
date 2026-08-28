import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/core/widgets/app_horizontal_strip.dart';

class CommercialWorkflowFilterBar extends StatelessWidget {
  const CommercialWorkflowFilterBar({
    super.key,
    this.queryController,
    required this.searchController,
    required this.status,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onCreate,
    required this.createLabel,
    required this.resultCount,
  });

  /// Preferred query-state owner for newly migrated workflow screens.
  /// When supplied, search and status changes are written directly to the
  /// shared Unified Query controller instead of introducing another state
  /// channel in the widget itself.
  final UnifiedQueryController? queryController;
  final TextEditingController searchController;
  final String status;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onCreate;
  final String createLabel;
  final int resultCount;

  void _setStatus(String value, BuildContext context) {
    final controller = queryController;
    if (controller == null) {
      onStatusChanged(value);
      return;
    }
    controller.removeFilterKey('status');
    if (value == 'all') return;
    final label = switch (value) {
      'draft' => context.l10n.isArabic ? 'مسودة' : 'Draft',
      'approved' => context.l10n.isArabic ? 'مصدق' : 'Approved',
      'invoiced' => context.l10n.isArabic ? 'مفوتر' : 'Invoiced',
      'paid' => context.l10n.isArabic ? 'مسدد' : 'Paid',
      _ => value,
    };
    controller.addFilter(
      UnifiedFilterToken(
        key: 'status',
        label: context.l10n.isArabic ? 'الحالة' : 'Status',
        value: value,
        valueLabel: label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filterButtons = <Widget>[
      ...<(String, String)>[
        ('all', context.l10n.isArabic ? 'الكل' : 'All'),
        ('draft', context.l10n.isArabic ? 'مسودة' : 'Draft'),
        ('approved', context.l10n.isArabic ? 'مصدق' : 'Approved'),
        ('invoiced', context.l10n.isArabic ? 'مفوتر' : 'Invoiced'),
        ('paid', context.l10n.isArabic ? 'مسدد' : 'Paid'),
      ].map(
        (entry) => ChoiceChip(
          label: AppText(
            entry.$2,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
          selected: status == entry.$1,
          showCheckmark: false,
          shape: const StadiumBorder(),
          visualDensity: VisualDensity.compact,
          onSelected: (_) => _setStatus(entry.$1, context),
          selectedColor: KajDesignTokens.electricBlue.withValues(alpha: .20),
          side: BorderSide(
            color: status == entry.$1
                ? KajDesignTokens.electricBlue.withValues(alpha: .48)
                : scheme.outlineVariant,
          ),
        ),
      ),
      Chip(
        avatar: const Icon(
          Icons.format_list_numbered_rounded,
          size: 14,
          color: KajDesignTokens.champagne,
        ),
        label: AppText(
          '${AppTranslation.translateForLocale('النتائج', Localizations.localeOf(context).languageCode)}: $resultCount',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: AppText(
          createLabel,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          visualDensity: VisualDensity.compact,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final search = TextField(
            controller: searchController,
            onChanged: (value) {
              queryController?.setSearch(value);
              onSearchChanged(value);
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              hintText: AppTranslation.translateForLocale(
                'بحث برقم الأمر أو اسم الشريك',
                Localizations.localeOf(context).languageCode,
              ),
              filled: true,
              fillColor: scheme.surfaceContainerLowest.withValues(alpha: .54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          );
          final strip = AppHorizontalStrip(spacing: 6, children: filterButtons);
          if (constraints.maxWidth < 780) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[search, const SizedBox(height: 8), strip],
            );
          }
          return Row(
            children: <Widget>[
              SizedBox(width: 310, child: search),
              const SizedBox(width: 10),
              Expanded(child: strip),
            ],
          );
        },
      ),
    );
  }
}
