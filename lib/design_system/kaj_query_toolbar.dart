import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';

/// Shared search/filter/sort surface for ERP list pages.
///
/// Modules provide their own filter controls through [filterBuilder], while
/// the lifecycle and presentation of active conditions remains consistent.
class KajQueryToolbar extends StatelessWidget {
  const KajQueryToolbar({
    super.key,
    required this.controller,
    this.hintText = 'بحث في السجلات...',
    this.filterBuilder,
    this.showSort = true,
    this.compact = false,
  });

  final UnifiedQueryController controller;
  final String hintText;
  final WidgetBuilder? filterBuilder;
  final bool showSort;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: KajDesignTokens.space8,
              runSpacing: KajDesignTokens.space8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: compact ? 220 : 320,
                  child: TextField(
                    key: const ValueKey('kaj-unified-search'),
                    controller: TextEditingController(text: state.search)
                      ..selection = TextSelection.collapsed(
                        offset: state.search.length,
                      ),
                    onChanged: controller.setSearch,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      hintText: hintText,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: state.search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح البحث',
                              onPressed: () => controller.setSearch(''),
                              icon: const Icon(Icons.close_rounded),
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: KajDesignTokens.raisedSurface(
                        Theme.of(context).brightness,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          KajDesignTokens.radiusMd,
                        ),
                        borderSide: BorderSide(
                          color: KajDesignTokens.border(
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (filterBuilder != null) filterBuilder!(context),
                if (showSort && state.sorts.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.sort_rounded, size: 17),
                    label: Text('${state.sorts.length} فرز'),
                  ),
              ],
            ),
            if (state.filters.isNotEmpty || state.sorts.isNotEmpty) ...[
              const SizedBox(height: KajDesignTokens.space8),
              Wrap(
                spacing: KajDesignTokens.space6,
                runSpacing: KajDesignTokens.space6,
                children: [
                  ...state.filters.map(
                    (filter) => InputChip(
                      key: ValueKey(
                        'kaj-filter-${filter.key}-${filter.value}',
                      ),
                      label: Text('${filter.label}: ${filter.valueLabel}'),
                      onDeleted: () => controller.removeFilter(filter),
                    ),
                  ),
                  ...state.sorts.map(
                    (sort) => InputChip(
                      key: ValueKey('kaj-sort-${sort.field}'),
                      avatar: Icon(
                        sort.descending
                            ? Icons.south_rounded
                            : Icons.north_rounded,
                        size: 15,
                      ),
                      label: Text(sort.label),
                      onDeleted: () => controller.removeSort(sort.field),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: controller.clear,
                    icon: const Icon(Icons.clear_all_rounded, size: 17),
                    label: const Text('مسح الكل'),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
