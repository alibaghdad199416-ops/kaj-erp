import 'package:flutter/foundation.dart';

/// Canonical, composable filter criteria shared by ERP modules.
///
/// Every populated condition is combined with logical AND. Individual values
/// inside the same condition (for example several warehouses) are combined
/// with logical OR. This prevents changing one control from accidentally
/// clearing or bypassing another active filter.
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
      toDate == null;

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
  );
}

/// Maps a module-specific entity into the canonical filter dimensions.
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
}

abstract final class UnifiedFilterEngine {
  static List<T> apply<T>(
    Iterable<T> values, {
    required UnifiedFilterCriteria criteria,
    required UnifiedFilterAdapter<T> adapter,
  }) => values
      .where((value) => matches(value, criteria: criteria, adapter: adapter))
      .toList(growable: false);

  static bool matches<T>(
    T value, {
    required UnifiedFilterCriteria criteria,
    required UnifiedFilterAdapter<T> adapter,
  }) {
    final query = normalize(criteria.searchText);
    final matchesSearch =
        query.isEmpty ||
        adapter
            .searchableText(value)
            .map(normalize)
            .any((text) => text.contains(query));

    final warehouseMatches = _matchesSet(
      criteria.warehouseIds,
      adapter.warehouseId?.call(value),
    );
    final statusMatches = _matchesSet(
      criteria.statuses,
      adapter.status?.call(value),
    );
    final companyMatches = _matchesSet(
      criteria.companyIds,
      adapter.companyId?.call(value),
    );
    final typeMatches = _matchesSet(criteria.types, adapter.type?.call(value));
    final partnerMatches = _matchesSet(
      criteria.partnerIds,
      adapter.partnerId?.call(value),
    );
    final currencyMatches = _matchesSet(
      criteria.currencies,
      adapter.currency?.call(value),
    );
    final userMatches = _matchesSet(
      criteria.userIds,
      adapter.userId?.call(value),
    );
    final groupMatches = _matchesSet(
      criteria.groupIds,
      adapter.groupId?.call(value),
    );
    final dateMatches = _matchesDate(
      adapter.date?.call(value),
      criteria.fromDate,
      criteria.toDate,
    );

    return matchesSearch &&
        warehouseMatches &&
        statusMatches &&
        companyMatches &&
        typeMatches &&
        partnerMatches &&
        currencyMatches &&
        userMatches &&
        groupMatches &&
        dateMatches;
  }

  static bool _matchesSet(Set<String> accepted, Object? rawValue) {
    if (accepted.isEmpty) return true;
    final value = normalize(rawValue);
    if (value.isEmpty) return false;
    return accepted.map(normalize).contains(value);
  }

  static bool _matchesDate(
    DateTime? value,
    DateTime? fromDate,
    DateTime? toDate,
  ) {
    if (fromDate == null && toDate == null) return true;
    if (value == null) return false;
    final day = DateTime(value.year, value.month, value.day);
    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day);
      if (day.isBefore(start)) return false;
    }
    if (toDate != null) {
      final end = DateTime(toDate.year, toDate.month, toDate.day);
      if (day.isAfter(end)) return false;
    }
    return true;
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
