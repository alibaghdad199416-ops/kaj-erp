abstract final class DefinitionCurrencyResolver {
  static const _keys = <String>[
    'definitionCurrency',
    'definition_currency',
    'currency',
    'costCurrency',
    'cost_currency',
    'saleCurrency',
    'sale_currency',
  ];

  static String resolve(Map<String, Object?> row, {String fallback = ''}) {
    final sources = <Map<String, Object?>>[row];
    for (final key in const ['details', 'data']) {
      final value = row[key];
      if (value is Map) sources.add(Map<String, Object?>.from(value));
    }
    for (final source in sources) {
      for (final key in _keys) {
        final value = source[key]?.toString().trim().toUpperCase();
        if (value == 'USD' || value == 'IQD') return value!;
      }
    }
    return fallback.trim().toUpperCase();
  }

  static bool matches(String definitionCurrency, String orderCurrency) =>
      definitionCurrency.trim().toUpperCase() ==
      orderCurrency.trim().toUpperCase();
}
