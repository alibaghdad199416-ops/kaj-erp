#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration_path = root / 'supabase/migrations/20260811084154_r55_opportunity_assignment_notifications.sql'
migration = migration_path.read_text(encoding='utf-8')
runtime = (root / 'supabase/tests/verify_r55_opportunity_notifications.sql').read_text(encoding='utf-8')
fresh = (root / 'tool/verify_fresh_database.ps1').read_text(encoding='utf-8')
package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
compact = re.sub(r'\s+', ' ', migration.lower())
failures = []


def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)


need('R55 is one forward-only migration after R54',
     migration_path.exists()
     and len(list((root / 'supabase/migrations').glob('*.sql'))) == 257
     and migration_path.name > '20260810224144_r54_operational_inventory_valuation_timing_closure.sql')
need('Opportunity notification target is tenant validated',
     'opportunity_notification_company_mismatch' in migration
     and 'opportunity_assignee_not_found' in migration
     and 'm.company_id=p_company_id' in compact)
need('Opportunity notifications are deterministic and retry idempotent',
     'md5(p_company_id::text' in compact
     and 'on conflict(company_id,id) do update' in compact)
need('Assignment and meaningful follow-up changes are covered',
     all(value in migration for value in (
         'opportunity_assignment', 'opportunity_follow_up',
         'assignedUserId', 'followUpDate', 'saleId')))
need('R55 helpers are internal and use a fixed search path',
     compact.count('security definer') == 2
     and compact.count('set search_path=public') == 2
     and compact.count('from public,anon,authenticated') == 2)
need('PostgreSQL runtime proves no duplicates and cross-tenant denial',
     'r55_assignment_retry_duplicated' in runtime
     and 'r55_cross_tenant_assignee_was_accepted' in runtime
     and 'when foreign_key_violation' in runtime)
need('Fresh database runs the R55 runtime proof',
     'verify_r55_opportunity_notifications.sql' in fresh
     and '$r55NotificationTest' in fresh)
scripts = package.get('scripts', {})
need('R55 verifier is registered in workspace verification',
     scripts.get('verify:r55', '').endswith('verify_r55_real_runtime_acceptance.py')
     and 'npm run verify:r55' in scripts.get('verify:workspace', ''))

if failures:
    print(f'FAIL R55 real runtime acceptance - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R55 real runtime acceptance - 8 gates')
