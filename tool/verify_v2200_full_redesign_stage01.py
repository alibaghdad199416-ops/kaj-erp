from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
checks={
 'universal components': root/'lib/design_system/kaj_universal_components.dart',
 'responsive workspace top bar': root/'lib/core/widgets/app_workspace_top_bar.dart',
 'release info': root/'lib/core/release/app_release_info.dart',
}
for label,path in checks.items():
    if not path.exists():
        raise SystemExit(f'FAIL missing {label}: {path}')
text=(root/'lib/design_system/kaj_universal_components.dart').read_text(encoding='utf-8')
for token in ['KajPageFrame','KajStatePanel','KajLoadingPanel','KajResponsiveActionBar']:
    if token not in text: raise SystemExit(f'FAIL missing {token}')
top=(root/'lib/core/widgets/app_workspace_top_bar.dart').read_text(encoding='utf-8')
for token in ['LayoutBuilder','final compact = constraints.maxWidth < 1180','colorScheme.onSurface']:
    if token not in top: raise SystemExit(f'FAIL top bar contract {token}')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
if 'version: 22.0.0+220000' not in pub: raise SystemExit('FAIL version')
rel=(root/'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
for token in ["version = '22.0.0'",'buildNumber = 220000',"channel = 'preview'"]:
    if token not in rel: raise SystemExit(f'FAIL release {token}')
print('PASS V22.0 full redesign stage 01 foundation verification')
