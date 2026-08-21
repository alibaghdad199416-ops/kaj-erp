import 'dart:math' as math;

import 'package:flutter/foundation.dart';

typedef UnifiedValueReader<T> = Object? Function(T value);
typedef UnifiedNumericValueReader<T> = num? Function(T value);

/// Inclusive numeric range used for amount, quantity and other measurable
/// enterprise filters. Invalid ranges fail closed instead of silently widening
/// the result set.
@immutable
class UnifiedNumericRange {
  const UnifiedNumericRange({this.min, this.max});

  final num? min;
  final num? max;

  bool get isEmpty => min == null && max == null;
  bool get isValid => min == null || max == null || min! <= max!;

  bool contains(num? value) {
    if (isEmpty) return true;
    if (!isValid || value == null) return false;
    if (min != null && value < min!) return false;
    if (max != null && value > max!) return false;
    return true;
  }
}

enum UnifiedSortDirection { ascending, descending }

@immutable
class UnifiedSortSpec {
  const UnifiedSortSpec(
    this.key, {
    this.direction = UnifiedSortDirection.ascending,
  });

  final String key;
  final UnifiedSortDirection direction;
}

/// Canonical, composable filter/query criteria shared by ERP modules.
///
/// Every populated condition is combined with logical AND. Individual values
/// inside the same condition (for example several warehouses) are combined
/// with logical OR. [dimensions] and [numericRanges] extend the query without
/// growing this class every time a module adds a business field.
///
/// Sorting and paging are applied only after the same filtered dataset is
/// resolved. This keeps tables, charts and exports able to share one query
/// contract instead of independently filtering different row sets.
@immutable
class UnifiedFilterCriteria {
  const UnifiedFilterCriteria({
    this.searchText = '',
    this.warehouseIds = const <String>{},
    this.statuses = const <String>{},
    this.companyIds = const <String>{},
    this.types = const <String>{},
    this.partnerIds = const <String>{},
    this.currencies = const <String>{},
    this.userIds = const <String>{},
    this.groupIds = const <String>{},
    this.fromDate,
    this.toDate,
    this.dimensions = const {},
    this.numericRanges = const {},
    this.sort,
    this.offset = 0,
    this.limit,
  });

  final String searchText;
  final Set<String> warehouseIds;
  final Set<String> statuses;
  final Set<String> companyIds;
  final Set<String> types;
  final Set<String> partnerIds;
  final Set<String> currencies;
  final Set<String> userIds;
  final Set<String> groupIds;
  final DateTime? fromDate;
  final DateTime? toDate;

  /// Module-specific exact-match dimensions such as createdBy, assignedUser,
  /// approvedBy, customer, supplier, vehicle, product, cashbox, reference,
  /// documentType, transactionType, sourceModule, invoiceType, paymentType,
  /// account or deletionUser. The adapter owns how each key maps to a row.
  final Map<String, Set<String>> dimensions;

  /// Module-specific inclusive ranges such as amount or quantity.
  final Map<String, UnifiedNumericRange> numericRanges;

  final UnifiedSortSpec? sort;
  final int offset;
  final int? limit;

  bool get isEmpty =>
      searchText.trim().isEmpty &&
      warehouseIds.isEmpty &&
      statuses.isEmpty &&
      companyIds.isEmpty &&
      types.isEmpty &&
      partnerIds.isEmpty &&
      currencies.isEmpty &&
      userIds.isEmpty &&
      groupIds.isEmpty &&
      fromDate == null &&
      toDate == null &&
      dimensions.values.every((values) => values.isEmpty) &&
      numericRanges.values.every((range) => range.isEmpty);

  /// Stable keys for rendering/removing individual active filter chips.
  Set<String> get activeFilterKeys {
    final keys = <String>{};
    if (searchText.trim().isNotEmpty) keys.add('searchText');
    if (warehouseIds.isNotEmpty) keys.add('warehouse');
    if (statuses.isNotEmpty) keys.add('status');
    if (companyIds.isNotEmpty) keys.add('company');
    if (types.isNotEmpty) keys.add('type');
    if (partnerIds.isNotEmpty) keys.add('partner');
    if (currencies.isNotEmpty) keys.add('currency');
    if (userIds.isNotEmpty) keys.add('user');
    if (groupIds.isNotEmpty) keys.add('group');
    if (fromDate != null) keys.add('dateFrom');
    if (toDate != null) keys.add('dateTo');
    for (final entry in dimensions.entries) {
      if (entry.value.isNotEmpty) keys.add(entry.key);
    }
    for (final entry in numericRanges.entries) {
      if (!entry.value.isEmpty) keys.add(entry.key);
    }
    return Set<String>.unmodifiable(keys);
  }

  UnifiedFilterCriteria copyWith({
    String? searchText,
    Set<String>? warehouseIds,
    Set<String>? statuses,
    Set<String>? companyIds,
    Set<String>? types,
    Set<String>? partnerIds,
    Set<String>? currencies,
    Set<String>? userIds,
    Set<String>? groupIds,
    DateTime? fromDate,
    DateTime? toDate,
    bool clearFromDate = false,
    bool clearToDate = false,
    Map<String, Set<String>>? dimensions,
    Map<String, UnifiedNumericRange>? numericRanges,
    UnifiedSortSpec? sort,
    bool clearSort = false,
    int? offset,
    int? limit,
    bool clearLimit = false,
  }) => UnifiedFilterCriteria(
    searchText: searchText ?? this.searchText,
    warehouseIds: warehouseIds ?? this.warehouseIds,
    statuses: statuses ?? this.statuses,
    companyIds: companyIds ?? this.companyIds,
    types: types ?? this.types,
    partnerIds: partnerIds ?? this.partnerIds,
    currencies: currencies ?? this.currencies,
    userIds: userIds ?? this.userIds,
    groupIds: groupIds ?? this.groupIds,
    fromDate: clearFromDate ? null : fromDate ?? this.fromDate,
    toDate: clearToDate ? null : toDate ?? this.toDate,
    dimensions: dimensions ?? this.dimensions,
    numericRanges: numericRanges ?? this.numericRanges,
    sort: clearSort ? null : sort ?? this.sort,
    offset: offset ?? this.offset,
    limit: clearLimit ? null : limit ?? this.limit,
  );
}

/// Maps a module-specific entity into the canonical filter/query dimensions.
class UnifiedFilterAdapter<T> {
  const UnifiedFilterAdapter({
    required this.searchableText,
    this.warehouseId,
    this.status,
    this.companyId,
    this.type,
    this.partnerId,
    this.currency,
    this.userId,
    this.groupId,
    this.date,
    this.dimensions = const {},
    this.numericDimensions = const {},
    this.sortValues = const {},
  });

  final Iterable<Object?> Function(T value) searchableText;
  final Object? Function(T value)? warehouseId;
  final Object? Function(T value)? status;
  final Object? Function(T value)? companyId;
  final Object? Function(T value)? type;
  final Object? Function(T value)? partnerId;
  final Object? Function(T value)? currency;
  final Object? Function(T value)? userId;
  final Object? Function(T value)? groupId;
  final DateTime? Function(T value)? date;

  final Map<String, UnifiedValueReader<T>> dimensions;
  final Map<String, UnifiedNumericValueReader<T>> numericDimensions;
  final Map<String, UnifiedValueReader<T>> sortValues;
}

abstract final class UnifiedFilterEngine {
  static List<T> apply<T>(
    Iterable<T> values, {
    required UnifiedFilterCriteria criteria,
    required UnifiedFilterAdapter<T> adapter,
  }) {
    final compiled = _CompiledUnifiedFilterCriteria(criteria);
    final filtered = <_IndexedValue<T>>[];
    var index = 0;
    for (final value in values) {
      if (_matchesCompiled(value, compiled: compiled, adapter: adapter)) {
        filtered.add(_IndexedValue(index, value));
      }
      index++;
    }

    final sort = criteria.sort;
    if (sort != null) {
      final reader = adapter.sortValues[sort.key];
      if (reader == null) {
        throw ArgumentError.value(
          sort.key,
          'criteria.sort.key',
          'has no matching adapter sort reader',
        );
      }
      filtered.sort((left, right) {
        final leftValue = reader(left.value);
        final rightValue = reader(right.value);
        if (leftValue == null || rightValue == null) {
          if (identical(leftValue, rightValue)) {
            return left.index.compareTo(right.index);
          }
          return leftValue == null ? 1 : -1;
        }
        var comparison = _compareSortValues(leftValue, rightValue);
        if (sort.direction == UnifiedSortDirection.descending) {
          comparison = -comparison;
        }
        return comparison != 0 ? comparison : left.index.compareTo(right.index);
      });
    }

    final safeOffset = math.max<int>(0, criteria.offset);
    if (safeOffset >= filtered.length) return <T>[];
    final remaining = filtered.length - safeOffset;
    final safeLimit = criteria.limit == null
        ? remaining
        : math.max<int>(0, criteria.limit!);
    final end = safeOffset + math.min<int>(remaining, safeLimit);
    return filtered
        .sublist(safeOffset, end)
        .map((entry) => entry.value)
        .toList(growable: false);
  }

  static bool matches<T>(
    T value, {
    required UnifiedFilterCriteria criteria,
    required UnifiedFilterAdapter<T> adapter,
  }) => _matchesCompiled(
    value,
    compiled: _CompiledUnifiedFilterCriteria(criteria),
    adapter: adapter,
  );

  static bool _matchesCompiled<T>(
    T value, {
    required _CompiledUnifiedFilterCriteria compiled,
    required UnifiedFilterAdapter<T> adapter,
  }) {
    final matchesSearch =
        compiled.searchText.isEmpty ||
        adapter
            .searchableText(value)
            .map(normalize)
            .any((text) => text.contains(compiled.searchText));

    if (!matchesSearch ||
        !_matchesNormalizedSet(
          compiled.warehouseIds,
          adapter.warehouseId?.call(value),
        ) ||
        !_matchesNormalizedSet(
          compiled.statuses,
          adapter.status?.call(value),
        ) ||
        !_matchesNormalizedSet(
          compiled.companyIds,
          adapter.companyId?.call(value),
        ) ||
        !_matchesNormalizedSet(compiled.types, adapter.type?.call(value)) ||
        !_matchesNormalizedSet(
          compiled.partnerIds,
          adapter.partnerId?.call(value),
        ) ||
        !_matchesNormalizedSet(
          compiled.currencies,
          adapter.currency?.call(value),
        ) ||
        !_matchesNormalizedSet(
          compiled.userIds,
          adapter.userId?.call(value),
        ) ||
        !_matchesNormalizedSet(
          compiled.groupIds,
          adapter.groupId?.call(value),
        ) ||
        !_matchesDate(
          adapter.date?.call(value),
          compiled.fromDate,
          compiled.toDate,
        )) {
      return false;
    }

    for (final entry in compiled.dimensions.entries) {
      final reader = adapter.dimensions[entry.key];
      if (reader == null ||
          !_matchesNormalizedSet(entry.value, reader(value))) {
        return false;
      }
    }
    for (final entry in compiled.numericRanges.entries) {
      final reader = adapter.numericDimensions[entry.key];
      if (reader == null || !entry.value.contains(reader(value))) return false;
    }
    return true;
  }

  static bool _matchesNormalizedSet(Set<String> accepted, Object? rawValue) {
    if (accepted.isEmpty) return true;
    final value = normalize(rawValue);
    return value.isNotEmpty && accepted.contains(value);
  }

  static bool _matchesDate(
    DateTime? value,
    DateTime? fromDate,
    DateTime? toDate,
  ) {
    if (fromDate == null && toDate == null) return true;
    if (value == null) return false;
    final day = DateTime(value.year, value.month, value.day);
    if (fromDate != null && day.isBefore(fromDate)) return false;
    if (toDate != null && day.isAfter(toDate)) return false;
    return true;
  }

  static int _compareSortValues(Object left, Object right) {
    if (left is num && right is num) return left.compareTo(right);
    if (left is DateTime && right is DateTime) return left.compareTo(right);
    return normalize(left).compareTo(normalize(right));
  }

  /// Normalizes user-entered Arabic and Latin text before matching.
  static String normalize(Object? value) => (value?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ـ', '')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _CompiledUnifiedFilterCriteria {
  _CompiledUnifiedFilterCriteria(UnifiedFilterCriteria criteria)
    : searchText = UnifiedFilterEngine.normalize(criteria.searchText),
      warehouseIds = _normalizeSet(criteria.warehouseIds),
      statuses = _normalizeSet(criteria.statuses),
      companyIds = _normalizeSet(criteria.companyIds),
      types = _normalizeSet(criteria.types),
      partnerIds = _normalizeSet(criteria.partnerIds),
      currencies = _normalizeSet(criteria.currencies),
      userIds = _normalizeSet(criteria.userIds),
      groupIds = _normalizeSet(criteria.groupIds),
      fromDate = _dateOnly(criteria.fromDate),
      toDate = _dateOnly(criteria.toDate),
      dimensions = <String, Set<String>>{
        for (final entry in criteria.dimensions.entries)
          if (entry.value.isNotEmpty) entry.key: _normalizeSet(entry.value),
      },
      numericRanges = <String, UnifiedNumericRange>{
        for (final entry in criteria.numericRanges.entries)
          if (!entry.value.isEmpty) entry.key: entry.value,
      };

  final String searchText;
  final Set<String> warehouseIds;
  final Set<String> statuses;
  final Set<String> companyIds;
  final Set<String> types;
  final Set<String> partnerIds;
  final Set<String> currencies;
  final Set<String> userIds;
  final Set<String> groupIds;
  final DateTime? fromDate;
  final DateTime? toDate;
  final Map<String, Set<String>> dimensions;
  final Map<String, UnifiedNumericRange> numericRanges;

  static Set<String> _normalizeSet(Iterable<String> values) => values
      .map(UnifiedFilterEngine.normalize)
      .where((value) => value.isNotEmpty)
      .toSet();

  static DateTime? _dateOnly(DateTime? value) => value == null
      ? null
      : DateTime(value.year, value.month, value.day);
}

class _IndexedValue<T> {
  const _IndexedValue(this.index, this.value);

  final int index;
  final T value;
}
