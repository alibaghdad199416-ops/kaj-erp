from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
LIB=ROOT/'lib'
assert LIB.exists(), 'lib missing'
files=list(LIB.rglob('*.dart'))
assert files, 'no Dart files'
patterns={'todo_fixme': re.compile(r'\b(TODO|FIXME|HACK|XXX)\b', re.I),'placeholder': re.compile(r'\b(coming soon|not implemented|placeholder)\b', re.I),'print': re.compile(r'\bprint\s*\(')}
counts={k:0 for k in patterns}
for p in files:
    text=p.read_text(encoding='utf-8', errors='ignore')
    for k,pat in patterns.items(): counts[k]+=len(pat.findall(text))
print('dart_files=',len(files))
for k,v in counts.items(): print(f'{k}={v}')
main=LIB/'main.dart'
assert main.exists(), 'lib/main.dart missing'
assert re.search(r'\bmain\s*\(', main.read_text(encoding='utf-8', errors='ignore')), 'main() missing'
print('main_entrypoint=PASS')
