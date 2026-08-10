from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
assert ('version: 19.3.0+193000' in pub) or ('version: 22.9.8+229008' in pub)
loc=(root/'lib/core/localization/app_localizations.dart').read_text(encoding='utf-8')
assert 'DisplayNumberFormatter.formatText(translated)' in loc
assert 'class AppSelectableText' in loc
fmt=(root/'lib/core/utils/display_number_formatter.dart').read_text(encoding='utf-8')
assert "NumberFormat('#,##0'" in fmt
full=(root/'lib/core/widgets/app_full_page_route.dart').read_text(encoding='utf-8')
assert 'fit: BoxFit.contain' in full
assert 'widget.preferredSize.aspectRatio' in full
# Close dock must be outside action scroll in both scaffold and alert window headers.
assert full.count('if (actions.isNotEmpty) const SizedBox(width: 8),') >= 2
assert full.count('closeDock,') >= 3
# Global dialog proportions.
theme=(root/'lib/app/theme.dart').read_text(encoding='utf-8')
for marker in ('minWidth: 380','maxWidth: 720','minHeight: 180','maxHeight: 720'):
    assert marker in theme, marker
# Every ordinary visible Text/SelectableText in lib must flow through localization/number formatting.
viol=[]
for p in (root/'lib').rglob('*.dart'):
    if p.as_posix().endswith('core/localization/app_localizations.dart'):
        continue
    text=p.read_text(encoding='utf-8')
    if re.search(r'(?<![A-Za-z0-9_.])Text\(', text): viol.append(f'{p}:Text')
    if re.search(r'(?<![A-Za-z0-9_.])SelectableText\(', text): viol.append(f'{p}:SelectableText')
assert not viol, '\n'.join(viol)
print('PASS V7.6.6 complete dialog sizing, fixed top close rail, proportional resize, localization and thousands formatting')
