from pathlib import Path

root = Path(__file__).resolve().parents[1]
read = lambda p: (root / p).read_text(encoding='utf-8')

pub = read('pubspec.yaml')
release = read('lib/core/release/app_release_info.dart')
full_page = read('lib/core/widgets/app_full_page_route.dart')
theme = read('lib/app/theme.dart')
l10n = read('lib/core/localization/app_localizations.dart')
formatter = read('lib/core/utils/display_number_formatter.dart')

assert ('version: 18.9.' in pub) or ('version: 22.9.8+229008' in pub)
assert ("static const String version = '18.9." in release) or ("static const String version = '22.9.8'" in release)
assert 'BoxFit.contain' in full_page and 'BoxFit.fill' not in full_page
assert 'effectiveMaxWidth' in full_page and 'preferredSize.aspectRatio' in full_page
assert "class AppSelectableText extends StatelessWidget" in l10n
assert 'DisplayNumberFormatter.formatText(translated)' in l10n
assert "NumberFormat('#,##0'" in formatter
assert 'minWidth: 380' in theme and 'maxWidth: 720' in theme
assert 'closeDock' in full_page and "ValueKey('module-page-close')" in full_page

# Runtime design-system text must pass through AppText so technical tokens and
# embedded quantities follow the active locale and number formatter.
for target in (
    'lib/design_system/kaj_v4_components.dart',
    'lib/core/widgets/app_top_navigation.dart',
    'lib/core/widgets/app_workspace_top_bar.dart',
):
    text = read(target)
    assert 'AppText(' in text, target

print('PASS V7.6.5 proportional module windows, unified close rail, localized selectable values, and thousands formatting')
