import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';

/// One user-visible filter condition. [key] is stable and module-specific;
/// labels are presentation-only so the same state can be rendered in RTL/LTR.
@immutable
class UnifiedFilterToken {
  const UnifiedFilterToken({
    required this.key,
    required this.label,
    required this.value,
    required this.valueLabel,
  });

  final String key;
  final String label;
  final Object value;
  final String valueLabel;

  @override
  bool operator ==(Object other) =>
      other is UnifiedFilterToken &&
      other.key == key &&
      other.value == value;

  @override
  int get hashCode => Object.hash(key, value);
}

@immutable
class UnifiedSortRule {
  const UnifiedSortRule({
    required this.field,
    required this.label,
    this.descending = false,
  });

  final String field;
  final String label;
  final bool descending;

  UnifiedSortRule copyWith({bool? descending}) => UnifiedSortRule(
    field: field,
    label: label,
    descending: descending ?? this.descending,
  );

  @override
  bool operator ==(Object other) =>
      other is UnifiedSortRule &&
      other.field == field &&
      other.descending == descending;

  @override
  int get hashCode => Object.hash(field, descending);
}

/// UI-neutral canonical state for module list queries.
@immutable
class UnifiedQueryState {
  const UnifiedQueryState({
    this.search = '',
    this.filters = const <UnifiedFilterToken>[],
    this.sorts = const <UnifiedSortRule>[],
  });

  final String search;
  final List<UnifiedFilterToken> filters;
  final List<UnifiedSortRule> sorts;

  bool get isEmpty => search.trim().isEmpty && filters.isEmpty && sorts.isEmpty;

  UnifiedQueryState copyWith({
    String? search,
    List<UnifiedFilterToken>? filters,
    List<UnifiedSortRule>? sorts,
  }) => UnifiedQueryState(
    search: search ?? this.search,
    filters: List.unmodifiable(filters ?? this.filters),
    sorts: List.unmodifiable(sorts ?? this.sorts),
  );

  UnifiedQueryState removeFilter(UnifiedFilterToken token) => copyWith(
    filters: filters.where((item) => item != token).toList(growable: false),
  );

  UnifiedQueryState removeFilterKey(String key) => copyWith(
    filters: filters.where((item) => item.key != key).toList(growable: false),
  );

  UnifiedQueryState removeSort(String field) => copyWith(
    sorts: sorts.where((item) => item.field != field).toList(growable: false),
  );

  UnifiedQueryState removeSortAt(int index) {
    if (index < 0 || index >= sorts.length) return this;
    final next = sorts.toList(growable: true)..removeAt(index);
    return copyWith(sorts: next);
  }

  UnifiedQueryState clear() => const UnifiedQueryState();

  @override
  bool operator ==(Object other) =>
      other is UnifiedQueryState &&
      other.search == search &&
      listEquals(other.filters, filters) &&
      listEquals(other.sorts, sorts);

  @override
  int get hashCode => Object.hash(
    search,
    Object.hashAll(filters),
    Object.hashAll(sorts),
  );
}

/// Existing typed query model retained for callers that execute directly
/// against [UnifiedFilterEngine].
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

/// Single source of truth for interactive screen query state. It performs no
/// I/O; repositories remain responsible for Cloud access and RLS enforcement.
class UnifiedQueryController extends ChangeNotifier {
  UnifiedQueryController([
    UnifiedQueryState initial = const UnifiedQueryState(),
  ]) : _state = initial;

  UnifiedQueryState _state;

  UnifiedQueryState get state => _state;

  void setSearch(String value) {
    if (_state.search == value) return;
    _state = _state.copyWith(search: value);
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
      next[index] = rule;
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

  void clear() {
    if (_state.isEmpty) return;
    _state = const UnifiedQueryState();
    notifyListeners();
  }
}
