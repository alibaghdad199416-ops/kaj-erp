from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
LIB=ROOT/'lib'
assert LIB.exists(), 'lib missing'

files=list(LIB.rglob('*.dart'))
assert files, 'no Dart files'

patterns={
 'todo_fixme': re.compile(r'\b(TODO|FIXME|HACK|XXX)\b', re.I),
 'placeholder': re.compile(r'\b(coming soon|not implemented|placeholder)\b', re.I),
 'print': re.compile(r'\bprint\s*\('),
}
counts={k:0 for k in patterns}
for p in files:
    text=p.read_text(encoding='utf-8', errors='ignore')
    for k,pat in patterns.items():
        counts[k]+=len(pat.findall(text))

print('dart_files=',len(files))
for k,v in counts.items(): print(f'{k}={v}')

# Hard structural checks for obvious accidental stubs.
stubs=[]
for p in files:
    text=p.read_text(encoding='utf-8', errors='ignore')
    if re.search(r'(?m)^\s*throw\s+UnimplementedError', text): stubs.append(str(p))
print('unimplemented_error_files=',len(stubs))
for x in stubs: print(x)

# Entry-point sanity.
main=LIB/'main.dart'
assert main.exists(), 'lib/main.dart missing'
mt=main.read_text(encoding='utf-8', errors='ignore')
assert 'void main' in mt or 'Future<void> main' in mt, 'main() missing'
print('main_entrypoint=PASS')
