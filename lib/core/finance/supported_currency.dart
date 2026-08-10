class SupportedCurrency {
  const SupportedCurrency._();

  static const String defaultCode = 'USD';
  static const Set<String> codes = <String>{'USD', 'IQD'};

  static String? normalize(Object? value) {
    final code = value?.toString().trim().toUpperCase() ?? '';
    return codes.contains(code) ? code : null;
  }

  static bool isSupported(Object? value) => normalize(value) != null;

  /// New records may start with the application default. Existing records must
  /// never silently change currency when the stored value is missing/corrupt.
  static String initial({required bool isNew, Object? stored}) =>
      normalize(stored) ?? (isNew ? defaultCode : '');
}
