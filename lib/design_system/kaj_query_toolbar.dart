import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';

/// Backwards-compatible design-system entry point for the canonical unified
/// query surface. The implementation lives in [UnifiedQueryToolbar] so there
/// is only one search/filter/sort UI and one query-state contract.
class KajQueryToolbar extends StatelessWidget {
  const KajQueryToolbar({
    super.key,
    required this.controller,
    this.hintText = 'بحث في السجلات...',
    this.filterBuilder,
    this.sortBuilder,
    this.compact = false,
  });

  final UnifiedQueryController controller;
  final String hintText;
  final WidgetBuilder? filterBuilder;
  final WidgetBuilder? sortBuilder;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return UnifiedQueryToolbar(
      controller: controller,
      searchHint: hintText,
      filterBuilder: filterBuilder,
      sortBuilder: sortBuilder,
      compact: compact,
    );
  }
}
