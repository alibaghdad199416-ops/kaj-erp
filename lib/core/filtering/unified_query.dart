import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query_state.dart';

export 'unified_filter_engine.dart';
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

/// Null-safe access to the first item of an iterable without requiring
/// the collection package. Kept in the shared query layer so every module
/// using Unified Query can use the same convenience API.
extension UnifiedIterableFirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class UnifiedQueryController extends ChangeNotifier {
  UnifiedQueryController([
    UnifiedQueryState initial = const UnifiedQueryState(),
  ]) : _state = initial;

  UnifiedQueryState _state;
  UnifiedQueryState get state => _state;

  void setSearch(String value) {
    final normalized = value.trim();
    if (_state.search == normalized) return;
    _state = _state.copyWith(search: normalized);
    notifyListeners();
  }

  void setFilters(Iterable<UnifiedFilterToken> values) {
    final next = List<UnifiedFilterToken>.unmodifiable(values);
    if (listEquals(_state.filters, next)) return;
    _state = _state.copyWith(filters: next);
    notifyListeners();
  }

  void addFilter(UnifiedFilterToken token) {
    final next = _state.filters
        .where((item) => item.key != token.key)
        .toList(growable: false);
    setFilters([...next, token]);
  }

  void removeFilter(UnifiedFilterToken token) {
    final next = _state.removeFilter(token);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  void removeFilterKey(String key) {
    final next = _state.removeFilterKey(key);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  void setSorts(Iterable<UnifiedSortRule> values) {
    final next = List<UnifiedSortRule>.unmodifiable(values);
    if (listEquals(_state.sorts, next)) return;
    _state = _state.copyWith(sorts: next);
    notifyListeners();
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

  void removeSort(String field) {
    final next = _state.removeSort(field);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  void removeSortAt(int index) {
    final next = _state.removeSortAt(index);
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  void clear() {
    if (_state.isEmpty) return;
    _state = const UnifiedQueryState();
    notifyListeners();
  }
}
