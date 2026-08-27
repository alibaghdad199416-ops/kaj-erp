import 'package:quality_line_erp/core/filtering/unified_query_state.dart';

class ReportExportOptions {
  const ReportExportOptions({
    this.title = 'تقرير خط الجودة',
    this.includeSummary = true,
    this.includeMonthly = true,
    this.includeExecutors = true,
    this.includeOperational = true,
    this.landscape = false,
    this.language = 'ar',
    this.includeGeneratedAt = true,
    this.includeModuleDetails = true,
    this.selectedColumns = const {},
    this.sectionQueries = const {},
    this.sectionFilters = const {},
    this.sortColumns = const {},
    this.sortAscending = const {},
    this.sectionEnabled = const {},
    this.sectionRowLimits = const {},
  });

  final String title;
  final bool includeSummary;
  final bool includeMonthly;
  final bool includeExecutors;
  final bool includeOperational;
  final bool landscape;
  final String language;
  final bool includeGeneratedAt;
  final bool includeModuleDetails;
  final Map<String, List<String>> selectedColumns;
  final Map<String, String> sectionQueries;

  /// Persisted unified filter tokens. Older presets simply omit this key.
  final Map<String, List<UnifiedFilterToken>> sectionFilters;

  final Map<String, String> sortColumns;
  final Map<String, bool> sortAscending;
  final Map<String, bool> sectionEnabled;
  final Map<String, int> sectionRowLimits;

  ReportExportOptions copyWith({
    String? title,
    bool? includeSummary,
    bool? includeMonthly,
    bool? includeExecutors,
    bool? includeOperational,
    bool? landscape,
    String? language,
    bool? includeGeneratedAt,
    bool? includeModuleDetails,
    Map<String, List<String>>? selectedColumns,
    Map<String, String>? sectionQueries,
    Map<String, List<UnifiedFilterToken>>? sectionFilters,
    Map<String, String>? sortColumns,
    Map<String, bool>? sortAscending,
    Map<String, bool>? sectionEnabled,
    Map<String, int>? sectionRowLimits,
  }) => ReportExportOptions(
    title: title ?? this.title,
    includeSummary: includeSummary ?? this.includeSummary,
    includeMonthly: includeMonthly ?? this.includeMonthly,
    includeExecutors: includeExecutors ?? this.includeExecutors,
    includeOperational: includeOperational ?? this.includeOperational,
    landscape: landscape ?? this.landscape,
    language: language ?? this.language,
    includeGeneratedAt: includeGeneratedAt ?? this.includeGeneratedAt,
    includeModuleDetails: includeModuleDetails ?? this.includeModuleDetails,
    selectedColumns: selectedColumns ?? this.selectedColumns,
    sectionQueries: sectionQueries ?? this.sectionQueries,
    sectionFilters: sectionFilters ?? this.sectionFilters,
    sortColumns: sortColumns ?? this.sortColumns,
    sortAscending: sortAscending ?? this.sortAscending,
    sectionEnabled: sectionEnabled ?? this.sectionEnabled,
    sectionRowLimits: sectionRowLimits ?? this.sectionRowLimits,
  );

  Map<String, Object?> toJson() => {
    'title': title,
    'includeSummary': includeSummary,
    'includeMonthly': includeMonthly,
    'includeExecutors': includeExecutors,
    'includeOperational': includeOperational,
    'landscape': landscape,
    'language': language,
    'includeGeneratedAt': includeGeneratedAt,
    'includeModuleDetails': includeModuleDetails,
    'selectedColumns': selectedColumns,
    'sectionQueries': sectionQueries,
    'sectionFilters': {
      for (final entry in sectionFilters.entries)
        entry.key: [
          for (final token in entry.value)
            {
              'key': token.key,
              'label': token.label,
              'value': token.value,
              'valueLabel': token.valueLabel,
            },
        ],
    },
    'sortColumns': sortColumns,
    'sortAscending': sortAscending,
    'sectionEnabled': sectionEnabled,
    'sectionRowLimits': sectionRowLimits,
  };

  factory ReportExportOptions.fromJson(Map<String, Object?> json) {
    final rawFilters = json['sectionFilters'] as Map? ?? const {};
    final filters = <String, List<UnifiedFilterToken>>{};
    for (final entry in rawFilters.entries) {
      final values = entry.value as List? ?? const [];
      filters[entry.key.toString()] = [
        for (final raw in values)
          if (raw is Map)
            UnifiedFilterToken(
              key: raw['key']?.toString() ?? '',
              label: raw['label']?.toString() ?? '',
              value: raw['value'] ?? '',
              valueLabel:
                  raw['valueLabel']?.toString() ??
                  raw['value']?.toString() ??
                  '',
            ),
      ];
    }

    return ReportExportOptions(
      title: json['title'] as String? ?? 'تقرير خط الجودة',
      includeSummary: json['includeSummary'] as bool? ?? true,
      includeMonthly: json['includeMonthly'] as bool? ?? true,
      includeExecutors: json['includeExecutors'] as bool? ?? true,
      includeOperational: json['includeOperational'] as bool? ?? true,
      landscape: json['landscape'] as bool? ?? false,
      language: json['language'] as String? ?? 'ar',
      includeGeneratedAt: json['includeGeneratedAt'] as bool? ?? true,
      includeModuleDetails: json['includeModuleDetails'] as bool? ?? true,
      selectedColumns: (json['selectedColumns'] as Map? ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          List<String>.from(value as List? ?? const []),
        ),
      ),
      sectionQueries: Map<String, String>.from(
        json['sectionQueries'] as Map? ?? const {},
      ),
      sectionFilters: filters,
      sortColumns: Map<String, String>.from(
        json['sortColumns'] as Map? ?? const {},
      ),
      sortAscending: Map<String, bool>.from(
        json['sortAscending'] as Map? ?? const {},
      ),
      sectionEnabled: (json['sectionEnabled'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
      sectionRowLimits: (json['sectionRowLimits'] as Map? ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          value is num ? value.toInt() : int.tryParse('$value') ?? 0,
        ),
      ),
    );
  }
}

class SavedReportPreset {
  const SavedReportPreset({required this.name, required this.options});
  final String name;
  final ReportExportOptions options;
  Map<String, Object?> toJson() => {'name': name, 'options': options.toJson()};
  factory SavedReportPreset.fromJson(Map<String, Object?> json) =>
      SavedReportPreset(
        name: json['name'] as String? ?? 'إعداد محفوظ',
        options: ReportExportOptions.fromJson(
          Map<String, Object?>.from(json['options'] as Map? ?? const {}),
        ),
      );
}
