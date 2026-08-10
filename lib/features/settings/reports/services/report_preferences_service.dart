import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';

class ReportPreferencesService {
  static const _optionsKey = 'reports.export.options.v1';
  static const _presetsKey = 'reports.export.presets.v1';

  Future<ReportExportOptions> loadOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_optionsKey);
    if (raw == null || raw.isEmpty) return const ReportExportOptions();
    try {
      return ReportExportOptions.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return const ReportExportOptions();
    }
  }

  Future<void> saveOptions(ReportExportOptions options) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_optionsKey, jsonEncode(options.toJson()));
  }

  Future<List<SavedReportPreset>> loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map(
            (item) => SavedReportPreset.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> savePresets(List<SavedReportPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _presetsKey,
      jsonEncode(presets.map((item) => item.toJson()).toList()),
    );
  }
}
