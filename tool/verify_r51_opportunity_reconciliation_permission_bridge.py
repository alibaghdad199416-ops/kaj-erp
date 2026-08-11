#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration_path = (
    root
    / 'supabase/migrations/20260810144714_r51_opportunity_reconciliation_permission_bridge.sql'
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
    'R51 is a new forward-only migration',
    migration_path.exists()
    and migration_path.name.startswith('20260810144714_r51_'),
)
need(
    'bridge requires the exact transaction-local reconciliation marker',
    "current_setting('qualityline.r51_reconciliation_permission',true)="
    "'customer_service.update'" in compact,
)
need(
    'bridge revalidates the real CRM update permission',
    "erp_cloud_user_has_permission(v_company_id,'customer_service.update')"
    in compact,
)
need(
    'bridge is limited to sales updates and opportunity_id',
    "tg_op='update'" in compact
    and "v_resource='sales'" in compact
    and "v_column<>'opportunity_id'" in compact,
)
need(
    'wrapper restores the prior marker on success and failure',
    compact.count("coalesce(v_previous_bridge,''), true") == 2
    and 'exception when others then' in compact,
)
need(
    'wrapper preserves tenant, permission, and fixed search-path guards',
    'perform public.erp_active_company_context(p_company_id);' in compact
    and 'not public.is_company_admin(p_company_id)' in compact
    and "permission_denied:customer_service.update" in compact
    and 'security definer set search_path=public' in compact,
)
need(
    'only the guarded wrapper is browser executable',
    'revoke all on function public.erp_r43_reconcile_opportunity_sales_links(uuid) '
    'from public, anon, authenticated;' in compact
    and 'grant execute on function '
    'public.erp_r43_reconcile_opportunity_sales_links(uuid) '
    'to authenticated, service_role;' in compact,
)
need(
    'R51 verifier is registered in the workspace chain',
    package.get('scripts', {}).get('verify:r51', '').endswith(
        'verify_r51_opportunity_reconciliation_permission_bridge.py'
    )
    and 'npm run verify:r51'
    in package.get('scripts', {}).get('verify:workspace', ''),
)

if failures:
    print(f'FAIL R51 permission bridge - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R51 opportunity reconciliation permission bridge - 8 gates')
