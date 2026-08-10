/// Defensive value conversion shared by cloud-backed models.
///
/// Supabase RPCs have historically returned a mix of camelCase and snake_case
/// keys. Every reader automatically checks both forms, so a forward-only
/// migration can rename an output alias without crashing older application
/// code. Missing optional values resolve to explicit defaults.
abstract final class ModelValueReader {
  static Object? raw(
    Map<String, dynamic> map,
    String key, {
    List<String> aliases = const <String>[],
  }) => _value(map, key, aliases);

  static String string(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    return value == null ? fallback : value.toString();
  }

  static String? nullableString(
    Map<String, dynamic> map,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    if (value == null || value.toString().trim().isEmpty) return null;
    return value.toString();
  }

  static int integer(
    Map<String, dynamic> map,
    String key, {
    int fallback = 0,
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double decimal(
    Map<String, dynamic> map,
    String key, {
    double fallback = 0,
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool boolean(
    Map<String, dynamic> map,
    String key, {
    bool fallback = false,
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    switch (value.toString().trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;
      default:
        return fallback;
    }
  }

  static DateTime? dateTime(
    Map<String, dynamic> map,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    if (value == null || value.toString().trim().isEmpty) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }

  static DateTime dateTimeOr(
    Map<String, dynamic> map,
    String key, {
    required DateTime fallback,
    List<String> aliases = const <String>[],
  }) => dateTime(map, key, aliases: aliases) ?? fallback;

  /// Reads a timestamp that is part of an authoritative server contract.
  ///
  /// Required operational/accounting dates must never be synthesized from the
  /// client clock because that silently changes ordering, reporting and audit
  /// traceability. Malformed rows fail explicitly and are handled by the
  /// surrounding repository/controller error state.
  static DateTime requiredDateTime(
    Map<String, dynamic> map,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final value = dateTime(map, key, aliases: aliases);
    if (value != null) return value;
    throw FormatException('Missing or invalid required timestamp: $key');
  }

  static List<dynamic> list(
    Map<String, dynamic> map,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    return value is List
        ? List<dynamic>.unmodifiable(value)
        : const <dynamic>[];
  }

  static Map<String, dynamic> objectMap(
    Map<String, dynamic> map,
    String key, {
    List<String> aliases = const <String>[],
  }) {
    final value = _value(map, key, aliases);
    return value is Map
        ? Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(value))
        : const <String, dynamic>{};
  }

  static Object? _value(
    Map<String, dynamic> map,
    String key,
    List<String> aliases,
  ) {
    for (final candidate in _candidateKeys(key, aliases)) {
      if (map.containsKey(candidate)) return map[candidate];
    }
    return null;
  }

  static Iterable<String> _candidateKeys(
    String key,
    List<String> aliases,
  ) sync* {
    final seen = <String>{};
    for (final candidate in <String>[key, ...aliases]) {
      final normalized = candidate.trim();
      if (normalized.isEmpty) continue;
      for (final variant in <String>[
        normalized,
        _toSnakeCase(normalized),
        _toCamelCase(normalized),
      ]) {
        if (variant.isNotEmpty && seen.add(variant)) yield variant;
      }
    }
  }

  static String _toSnakeCase(String value) {
    if (value.contains('_')) return value.toLowerCase();
    return value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)}_${match.group(2)}',
        )
        .toLowerCase();
  }

  static String _toCamelCase(String value) {
    if (!value.contains('_')) return value;
    final parts = value.split('_').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return value;
    return parts.first +
        parts
            .skip(1)
            .map(
              (part) => part.length == 1
                  ? part.toUpperCase()
                  : '${part[0].toUpperCase()}${part.substring(1)}',
            )
            .join();
  }
}
