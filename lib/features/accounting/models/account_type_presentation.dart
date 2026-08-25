/// Canonical account-type presentation and ordering used by ledger reports.
class AccountTypePresentation {
  const AccountTypePresentation._();

  static const orderedTypes = <String>[
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense',
  ];

  static String normalize(Object? value) {
    final raw = value?.toString().trim().toLowerCase() ?? '';
    return switch (raw) {
      'receivable' ||
      'cash' ||
      'bank' ||
      'inventory' ||
      'fixed_asset' ||
      'clearing' => 'asset',
      'payable' => 'liability',
      'income' => 'revenue',
      'cost' || 'cogs' => 'expense',
      _ => orderedTypes.contains(raw) ? raw : 'asset',
    };
  }

  static int orderOf(Object? value) => orderedTypes.indexOf(normalize(value));

  static String arabicLabel(Object? value) => switch (normalize(value)) {
    'asset' => 'الأصول',
    'liability' => 'الخصوم',
    'equity' => 'حقوق الملكية',
    'revenue' => 'الإيرادات',
    'expense' => 'المصروفات',
    _ => 'الأصول',
  };

  static Map<String, List<Map<String, Object?>>> groupLedgerRows(
    List<Map<String, Object?>> rows,
  ) {
    final grouped = <String, List<Map<String, Object?>>>{
      for (final type in orderedTypes) type: <Map<String, Object?>>[],
    };
    for (final row in rows) {
      grouped[normalize(row['accountType'])]!.add(row);
    }
    for (final values in grouped.values) {
      values.sort((a, b) {
        final code = (a['accountCode']?.toString() ?? '').compareTo(
          b['accountCode']?.toString() ?? '',
        );
        if (code != 0) return code;
        return (a['entryDate']?.toString() ?? '').compareTo(
          b['entryDate']?.toString() ?? '',
        );
      });
    }
    grouped.removeWhere((_, values) => values.isEmpty);
    return grouped;
  }
}
