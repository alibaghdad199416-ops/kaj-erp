import 'package:flutter/foundation.dart';

/// Describes one active filter in the shared ERP query model.
///
/// [key] is a stable module-specific field identifier while [label] and
/// [valueLabel] are presentation values. Keeping these separate lets the UI
/// remove one condition without rebuilding or clearing the remaining query.
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

/// One ordering rule. Multiple rules are applied in the supplied order.
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

/// Canonical state for module list queries.
///
/// The state is intentionally UI-agnostic. Modules can expose different
/// filter fields while sharing the same lifecycle: search + filters + sort.
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

  bool get isEmpty =>
      search.trim().isEmpty && filters.isEmpty && sorts.isEmpty;

  UnifiedQueryState copyWith({
    String? search,
    List<UnifiedFilterToken>? filters,
    List<UnifiedSortRule>? sorts,
  }) => UnifiedQueryState(
    search: search ?? this.search,
    filters: List.unmodifiable(filters ?? this.filters),
    sorts: List.unmodifiable(sorts ?? this.sorts),
  );

  UnifiedQueryState removeFilter(UnifiedFilterToken token) {
    return copyWith(
      filters: filters.where((item) => item != token).toList(growable: false),
    );
  }

  UnifiedQueryState removeFilterKey(String key) {
    return copyWith(
      filters: filters.where((item) => item.key != key).toList(growable: false),
    );
  }

  UnifiedQueryState removeSort(String field) {
    return copyWith(
      sorts: sorts.where((item) => item.field != field).toList(growable: false),
    );
  }

  UnifiedQueryState clear() => const UnifiedQueryState();

  @override
  bool operator ==(Object other) {
    if (other is! UnifiedQueryState ||
        other.search != search ||
        !listEquals(other.filters, filters) ||
        !listEquals(other.sorts, sorts)) {
      return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    search,
    Object.hashAll(filters),
    Object.hashAll(sorts),
  );
}

/// Small state holder for screens that need a single source of truth for
/// search/filter/sort changes. It deliberately does not perform I/O.
class UnifiedQueryController extends ChangeNotifier {
  UnifiedQueryController([UnifiedQueryState initial = const UnifiedQueryState()])
    : _state = initial;

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
    final withoutSameKey = _state.filters
        .where((item) => item.key != token.key)
        .toList(growable: false);
    setFilters([...withoutSameKey, token]);
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
    final next = [
      ..._state.sorts.where((item) => item.field != rule.field),
      rule,
    ];
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
