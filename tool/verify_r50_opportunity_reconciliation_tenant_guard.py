#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration_path = (
    root
    / 'supabase/migrations/20260810120139_r50_opportunity_reconciliation_tenant_guard.sql'
)
migration = migration_path.read_text(encoding='utf-8')
package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
failures = []


def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)


compact = re.sub(r'\s+', ' ', migration.lower())
need(
    'historical reconciliation implementation is internal',
    'revoke all on function public.erp_r37_reconcile_opportunity_sales_links(uuid) '
    'from public, anon, authenticated;' in compact
    and 'grant execute on function '
    'public.erp_r37_reconcile_opportunity_sales_links(uuid) to service_role;'
    in compact,
)
need(
    'browser reconciliation validates active tenant context',
    'perform public.erp_active_company_context(p_company_id);' in compact,
)
need(
    'browser reconciliation requires CRM update permission or admin',
    'not public.is_company_admin(p_company_id)' in compact
    and "erp_cloud_user_has_permission( p_company_id, 'customer_service.update' )"
    in compact
    and "permission_denied:customer_service.update" in compact,
)
need(
    'reconciliation wrapper retains a fixed search path',
    'security definer set search_path = public' in compact,
)
need(
    'only guarded wrapper remains available to authenticated users',
    'revoke all on function public.erp_r43_reconcile_opportunity_sales_links(uuid) '
    'from public, anon, authenticated;' in compact
    and 'grant execute on function '
    'public.erp_r43_reconcile_opportunity_sales_links(uuid) '
    'to authenticated, service_role;' in compact,
)
need(
    'trigger functions are not directly executable by browser roles',
    compact.count('revoke all on function public.erp_r37_') >= 3,
)
need(
    'R50 verifier is registered in the workspace chain',
    package.get('scripts', {}).get('verify:r50', '').endswith(
        'verify_r50_opportunity_reconciliation_tenant_guard.py'
    )
    and 'npm run verify:r50'
    in package.get('scripts', {}).get('verify:workspace', ''),
)

if failures:
    print(f'FAIL R50 tenant guard - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R50 opportunity reconciliation tenant guard - 7 gates')
