import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';

/// Single source of truth for a module list query.
///
/// A screen owns one instance of this state rather than separate search,
/// filter and sort states. Removing one condition therefore cannot clear the
/// other active conditions.
@immutable
class UnifiedQuery<T> {
  const UnifiedQuery({
    this.criteria = const UnifiedFilterCriteria(),
    this.sorts = const [],
  });

  final UnifiedFilterCriteria criteria;
  final List<UnifiedSortCriterion<T>> sorts;

  bool get isEmpty => criteria.isEmpty && sorts.isEmpty;

  UnifiedQuery<T> copyWith({
    UnifiedFilterCriteria? criteria,
    List<UnifiedSortCriterion<T>>? sorts,
  }) => UnifiedQuery<T>(
    criteria: criteria ?? this.criteria,
    sorts: sorts ?? this.sorts,
  );

  UnifiedQuery<T> removeSort(String key) => copyWith(
    sorts: sorts.where((sort) => sort.key != key).toList(growable: false),
  );

  UnifiedQuery<T> removeSortAt(int index) {
    if (index < 0 || index >= sorts.length) return this;
    final next = sorts.toList(growable: true)..removeAt(index);
    return copyWith(sorts: List<UnifiedSortCriterion<T>>.unmodifiable(next));
  }

  List<T> apply(Iterable<T> values, UnifiedFilterAdapter<T> adapter) =>
      UnifiedFilterEngine.apply(
        values,
        criteria: criteria,
        adapter: adapter,
        sorts: sorts,
      );
}
