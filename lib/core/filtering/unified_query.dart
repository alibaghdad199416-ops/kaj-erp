import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query_state.dart';

export 'unified_query_executor.dart';
export 'unified_query_state.dart';

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

/// Shared null-safe access to the first item of an iterable.
///
/// This belongs in the query core because migrated module pages use it while
/// reading optional filter tokens. Keeping one implementation avoids each
/// feature introducing its own helper or depending on a collection package.
extension UnifiedIterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class UnifiedQueryController extends ChangeNotifier {
  UnifiedQueryController([
    UnifiedQueryState initial = const UnifiedQueryState(),
  ]) : _state = initial;

  UnifiedQueryState _state;
  UnifiedQueryState get state => _state;

  /// Canonical mutation boundary for module query state.
  ///
  /// Modules should update search, filters and sorts through this controller
  /// rather than keeping parallel page-local query state.
  void setState(UnifiedQueryState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void setSearch(String value) {
    final normalized = value.trim();
    if (_state.search == normalized) return;
    setState(_state.copyWith(search: normalized));
  }

  void setFilters(Iterable<UnifiedFilterToken> values) {
    // A query can have at most one active value per filter key. This keeps
    // all module query state canonical even when callers replace the list
    // directly instead of going through addFilter().
    final byKey = <String, UnifiedFilterToken>{};
    for (final token in values) {
      byKey[token.key] = token;
    }
    final next = List<UnifiedFilterToken>.unmodifiable(byKey.values);
    if (listEquals(_state.filters, next)) return;
    setState(_state.copyWith(filters: next));
  }

  void addFilter(UnifiedFilterToken token) {
    final next = _state.filters
        .where((item) => item.key != token.key)
        .toList(growable: false);
    setFilters([...next, token]);
  }

  void removeFilter(UnifiedFilterToken token) =>
      setState(_state.removeFilter(token));

  void removeFilterKey(String key) => setState(_state.removeFilterKey(key));

  void setSorts(Iterable<UnifiedSortRule> values) {
    final byField = <String, UnifiedSortRule>{};
    for (final rule in values) {
      byField[rule.field] = rule;
    }
    final next = List<UnifiedSortRule>.unmodifiable(byField.values);
    if (listEquals(_state.sorts, next)) return;
    setState(_state.copyWith(sorts: next));
  }

  void addSort(UnifiedSortRule rule) {
    final next = List<UnifiedSortRule>.from(_state.sorts);
    final index = next.indexWhere((item) => item.field == rule.field);
    if (index >= 0) {
      final existing = next[index];
      next[index] = existing.copyWith(descending: !existing.descending);
    } else {
      next.add(rule);
    }
    setSorts(next);
  }

  void removeSort(String field) => setState(_state.removeSort(field));

  void removeSortAt(int index) => setState(_state.removeSortAt(index));

  void clear() => setState(const UnifiedQueryState());
}
