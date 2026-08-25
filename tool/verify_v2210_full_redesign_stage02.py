from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = {
    'shell components': ROOT / 'lib/design_system/kaj_shell_components.dart',
    'universal components': ROOT / 'lib/design_system/kaj_universal_components.dart',
    'module shell': ROOT / 'lib/core/widgets/app_module_shell.dart',
    'top bar': ROOT / 'lib/core/widgets/app_workspace_top_bar.dart',
    'navigation': ROOT / 'lib/core/widgets/app_top_navigation.dart',
    'module window': ROOT / 'lib/core/widgets/app_full_page_route.dart',
}
missing = [name for name, path in checks.items() if not path.exists()]
if missing:
    print('FAIL missing:', ', '.join(missing))
    sys.exit(1)

contracts = {
    'lib/design_system/kaj_shell_components.dart': [
        'class KajShellSurface', 'class KajPrimaryAction',
        'class KajSecondaryAction', 'class KajField',
        'class KajTableFrame', 'class KajSystemState',
    ],
    'lib/core/widgets/app_module_shell.dart': [
        'KajShellSurface', 'viewport.maxWidth < 840',
    ],
    'lib/core/widgets/app_workspace_top_bar.dart': [
        'veryCompact', 'KajDesignTokens.border(brightness)',
    ],
    'lib/core/widgets/app_full_page_route.dart': [
        'KajShellSurface', 'KajDesignTokens.radiusLg',
    ],
    'lib/core/release/app_release_info.dart': [
        "version = '22.1.0'", 'buildNumber = 221000',
        "operationalRevision = '22.1.0-full-redesign-stage02'",
    ],
}
for rel, needles in contracts.items():
    text = (ROOT / rel).read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            print(f'FAIL {rel}: missing {needle}')
            sys.exit(1)
print('PASS V22.1 full redesign stage 02 shell and shared controls verification')
print('PASS navigation, top bar, dialogs, buttons, fields, tables and system states contracts')
