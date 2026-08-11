#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration_path = root / 'supabase/migrations/20260811084154_r55_opportunity_assignment_notifications.sql'
migration = migration_path.read_text(encoding='utf-8')
runtime = (root / 'supabase/tests/verify_r55_opportunity_notifications.sql').read_text(encoding='utf-8')
r551_path = root / 'supabase/migrations/20260811103921_r55_1_opportunity_terminal_state_guard.sql'
r551 = r551_path.read_text(encoding='utf-8')
r551_runtime = (root / 'supabase/tests/verify_r55_1_opportunity_terminal_semantics.sql').read_text(encoding='utf-8')
r551_sales_path = root / 'supabase/migrations/20260811113208_r55_1_sales_order_won_semantics_correction.sql'
r551_sales = r551_sales_path.read_text(encoding='utf-8')
r49_runtime = (root / 'supabase/tests/verify_r49_erp_transactions_runtime.sql').read_text(encoding='utf-8')
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
     and len(list((root / 'supabase/migrations').glob('*.sql'))) == 259
     and migration_path.name > '20260810224144_r54_operational_inventory_valuation_timing_closure.sql')
need('R55.1 is one forward-only migration after R55',
     r551_path.exists() and r551_path.name > migration_path.name)
need('R55.1 Sales Order correction is forward-only migration 259',
     r551_sales_path.exists() and r551_sales_path.name > r551_path.name)
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
need('R55.1 blocks forged Won and normalizes canonical Lost',
     'opportunity_won_requires_canonical_sales_workflow' in r551
     and 'opportunity_lost_requires_mark_lost' in r551
     and "'stage','lost','status','lost'" in re.sub(r'\s+', '', r551.lower()))
need('R55.1 runtime proves forged Won denial and canonical Lost',
     'r55_1_forged_won_was_accepted' in r551_runtime
     and 'r55_1_no_link_changed_user_controlled_stage' in r551_runtime
     and 'r55_1_canonical_lost_inconsistent' in r551_runtime
     and 'r55_1_lost_notification_not_exactly_once' in r551_runtime)
need('Approved or confirmed Sales Order is canonical Won evidence',
     "('approved','confirmed')" in re.sub(r'\s+', '', r551_sales.lower())
     and 'opportunity_won_requires_canonical_sales_workflow' in r551_sales)
need('Sales Order approval wins before delivery, invoice, and payment',
     "v_order_status in ('approved','confirmed') or d.id is not null or i.id is not null" in r551_sales
     and "v_status:='won'" in r551_sales and "v_stage:='won'" in r551_sales)
need('Runtime proves Sales Order Won lifecycle and commercial boundaries',
     all(marker in r49_runtime for marker in (
         'r55_1_sales_order_draft_must_remain_pending',
         'r55_1_sales_order_approval_must_immediately_win',
         'r55_1_sales_order_approval_crossed_commercial_boundary',
         'r55_1_delivery_reverted_won_opportunity',
         'r55_1_invoice_reverted_or_first_won_event',
         'r55_1_sales_order_cancellation_not_lost')))
need('Runtime proves Won and Lost notifications stay exactly once',
     'r55_1_won_notification_retry_duplicated' in r49_runtime
     and 'r55_1_lost_notification_retry_not_exactly_once' in r49_runtime)
need('Fresh database runs the R55.1 runtime proof',
     'verify_r55_1_opportunity_terminal_semantics.sql' in fresh
     and '$r551TerminalTest' in fresh)
scripts = package.get('scripts', {})
need('R55 verifier is registered in workspace verification',
     scripts.get('verify:r55', '').endswith('verify_r55_real_runtime_acceptance.py')
     and 'npm run verify:r55' in scripts.get('verify:workspace', ''))

if failures:
    print(f'FAIL R55/R55.1 real runtime acceptance - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R55/R55.1 real runtime acceptance - 17 gates')
