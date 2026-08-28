import 'package:flutter/foundation.dart';

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
      other is UnifiedFilterToken && other.key == key && other.value == value;

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
  }) {
    final canonicalFilters = _canonicalizeFilters(filters ?? this.filters);
    final canonicalSorts = _canonicalizeSorts(sorts ?? this.sorts);
    return UnifiedQueryState(
      search: (search ?? this.search).trim(),
      filters: List.unmodifiable(canonicalFilters),
      sorts: List.unmodifiable(canonicalSorts),
    );
  }

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

  static List<UnifiedFilterToken> _canonicalizeFilters(
    Iterable<UnifiedFilterToken> values,
  ) {
    final byKey = <String, UnifiedFilterToken>{};
    for (final token in values) {
      final key = token.key.trim();
      if (key.isEmpty) continue;
      byKey[key] = token;
    }
    return byKey.values.toList(growable: false);
  }

  static List<UnifiedSortRule> _canonicalizeSorts(
    Iterable<UnifiedSortRule> values,
  ) {
    final byField = <String, UnifiedSortRule>{};
    for (final rule in values) {
      final field = rule.field.trim();
      if (field.isEmpty) continue;
      byField[field] = rule;
    }
    return byField.values.toList(growable: false);
  }

  @override
  bool operator ==(Object other) =>
      other is UnifiedQueryState &&
      other.search == search &&
      listEquals(other.filters, filters) &&
      listEquals(other.sorts, sorts);

  @override
  int get hashCode =>
      Object.hash(search, Object.hashAll(filters), Object.hashAll(sorts));
}
