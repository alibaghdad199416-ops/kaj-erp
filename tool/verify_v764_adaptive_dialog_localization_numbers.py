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
assert 'final aspectRatio = widget.preferredSize.aspectRatio;' in route
assert 'height: 56,' in route and 'Expanded(child: child)' in route
assert 'minWidth:' in theme and 'maxWidth:' in theme and 'dialogTheme: DialogThemeData(' in theme
assert 'DisplayNumberFormatter.formatText(translated)' in localization
assert '_translateTechnicalIdentifier' in localization
assert "NumberFormat('#,##0'" in formatter
assert 'Document identifiers, dates, times, versions and account codes' in formatter
print('PASS V7.6.4 adaptive dialog proportions, unified close rail, localized technical terms, and thousands separators')
