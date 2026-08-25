from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
migrations = root / 'supabase' / 'migrations'
files = sorted(p for p in migrations.glob('*.sql'))
versions = {}
for path in files:
    match = re.match(r'^(\d+)_', path.name)
    if not match:
        raise SystemExit(f'FAIL invalid migration filename: {path.name}')
    version = match.group(1)
    versions.setdefault(version, []).append(path.name)

duplicates = {v:n for v,n in versions.items() if len(n)>1}
if duplicates:
    details = '; '.join(f"{v}: {', '.join(n)}" for v,n in sorted(duplicates.items()))
    raise SystemExit(f'FAIL duplicate Supabase migration versions: {details}')

required = {
    '20260807023000_v761_strict_no_capitalization_ledger_balance.sql',
    '20260807024500_v761_operational_invoice_diagnostics.sql',
    '20260807030000_v762_workflow_posting_payment_integrity.sql',
}
missing = sorted(required - {p.name for p in files})
if missing:
    raise SystemExit('FAIL missing required migrations: ' + ', '.join(missing))

print('PASS V22.9.3 R2 Supabase migration ordering verification')
print(f'- {len(files)} migration files checked')
print('- no duplicate migration versions')
print('- operational diagnostics migration moved to 20260807024500')
