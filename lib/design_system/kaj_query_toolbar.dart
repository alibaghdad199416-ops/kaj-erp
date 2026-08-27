import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';

export 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart'
    show UnifiedQueryFilterOption, UnifiedQuerySortOption;

/// Backwards-compatible design-system entry point for the canonical unified
/// query surface. The implementation lives in [UnifiedQueryToolbar] so there
/// is only one search/filter/sort UI and one query-state contract.
class KajQueryToolbar extends StatelessWidget {
  const KajQueryToolbar({
    super.key,
    required this.controller,
    this.hintText = 'بحث في السجلات...',
    this.filters = const <UnifiedQueryFilterOption>[],
    this.sorts = const <UnifiedQuerySortOption>[],
    this.filterBuilder,
    this.sortBuilder,
    this.compact = false,
    this.padding = EdgeInsets.zero,
    this.filterButtonLabel = 'فلترة',
    this.sortButtonLabel = 'فرز',
    this.clearAllLabel = 'مسح الكل',
    this.clearSearchTooltip = 'مسح البحث',
    this.ascendingLabel = 'تصاعدي',
    this.descendingLabel = 'تنازلي',
  });

  final UnifiedQueryController controller;
  final String hintText;
  final List<UnifiedQueryFilterOption> filters;
  final List<UnifiedQuerySortOption> sorts;
  final WidgetBuilder? filterBuilder;
  final WidgetBuilder? sortBuilder;
  final bool compact;
  final EdgeInsetsGeometry padding;
  final String filterButtonLabel;
  final String sortButtonLabel;
  final String clearAllLabel;
  final String clearSearchTooltip;
  final String ascendingLabel;
  final String descendingLabel;

  @override
  Widget build(BuildContext context) {
    return UnifiedQueryToolbar(
      controller: controller,
      searchHint: hintText,
      filters: filters,
      sorts: sorts,
      filterBuilder: filterBuilder,
      sortBuilder: sortBuilder,
      compact: compact,
      padding: padding,
      filterButtonLabel: filterButtonLabel,
      sortButtonLabel: sortButtonLabel,
      clearAllLabel: clearAllLabel,
      clearSearchTooltip: clearSearchTooltip,
      ascendingLabel: ascendingLabel,
      descendingLabel: descendingLabel,
    );
  }
}
