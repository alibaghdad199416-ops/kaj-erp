from pathlib import Path

root = Path(__file__).resolve().parents[1]
release = (root / 'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
pubspec = (root / 'pubspec.yaml').read_text(encoding='utf-8')
route = (root / 'lib/core/widgets/app_full_page_route.dart').read_text(encoding='utf-8')
theme = (root / 'lib/app/theme.dart').read_text(encoding='utf-8')
localization = (root / 'lib/core/localization/app_localizations.dart').read_text(encoding='utf-8')
formatter = (root / 'lib/core/utils/display_number_formatter.dart').read_text(encoding='utf-8')

assert ('version: 18.9.' in pubspec) or ('version: 22.9.8+229008' in pubspec)
assert ("static const String version = '18.9." in release) or ("static const String version = '22.9.8'" in release)
assert 'Desktop workspaces intentionally remain bounded' in route
assert 'double maxWidth = 1320' in route and 'double maxHeight = 840' in route
assert 'module-workspace-window' in route
assert 'class _WorkspaceHeader' in route
assert 'height: compact ? 54 : 58' in route
assert 'Expanded(child: presentation.content)' in route
assert 'minWidth:' in theme and 'maxWidth:' in theme and 'dialogTheme: DialogThemeData(' in theme
assert 'DisplayNumberFormatter.formatText(translated)' in localization
assert '_translateTechnicalIdentifier' in localization
assert "NumberFormat('#,##0'" in formatter
assert 'Document identifiers, dates, times, versions and account codes' in formatter
print('PASS V7.6.4 bounded adaptive workspace, unified close header, localized technical terms, and thousands separators')
