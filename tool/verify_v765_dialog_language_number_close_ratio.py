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
assert 'Desktop workspaces intentionally remain bounded' in full_page
assert 'double maxWidth = 1320' in full_page and 'double maxHeight = 840' in full_page
assert 'double minWidth = 760' in full_page and 'double minHeight = 520' in full_page
assert 'module-workspace-window' in full_page
assert 'class _WorkspaceHeader' in full_page and 'class _WorkspacePresentation' in full_page
assert "ValueKey('module-page-close')" in full_page
assert 'Clip.antiAlias' in full_page
assert 'closeDock' not in full_page and '_PlainContentAsWindow' not in full_page
assert "class AppSelectableText extends StatelessWidget" in l10n
assert 'DisplayNumberFormatter.formatText(translated)' in l10n
assert "NumberFormat('#,##0'" in formatter
assert 'minWidth: 380' in theme and 'maxWidth: 720' in theme

# Runtime design-system text must pass through AppText so technical tokens and
# embedded quantities follow the active locale and number formatter.
for target in (
    'lib/design_system/kaj_v4_components.dart',
    'lib/core/widgets/app_top_navigation.dart',
    'lib/core/widgets/app_workspace_top_bar.dart',
):
    text = read(target)
    assert 'AppText(' in text, target

print('PASS V7.6.5 bounded module workspaces, unified close header, localized selectable values, and thousands formatting')
