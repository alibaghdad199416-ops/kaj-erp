#!/usr/bin/env python3
from hashlib import sha256
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration = (root / 'supabase/migrations/20260810153311_r52_fresh_database_lint_runtime_closure.sql').read_text(encoding='utf-8')
bootstrap = (root / 'supabase/fresh_install/r35_cloud_command_compatibility.sql').read_text(encoding='utf-8')
orchestrator = (root / 'tool/verify_fresh_database.ps1').read_text(encoding='utf-8')
final_state = (root / 'supabase/tests/verify_fresh_install_final_state.sql').read_text(encoding='utf-8')
runtime = (root / 'supabase/tests/verify_r50_r52_runtime.sql').read_text(encoding='utf-8')
package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
failures = []


def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)


def digest(relative):
    return sha256((root / relative).read_bytes()).hexdigest().upper()


compact_migration = re.sub(r'\s+', ' ', migration.lower())
compact_bootstrap = re.sub(r'\s+', ' ', bootstrap.lower())

need(
    'historical R37 and canonical R35 migrations remain byte-identical',
    digest('supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql')
    == 'B492C1960BC4B4AF574E5BBB1F963D1F4184250E54E84F1400CF7E65D9430632'
    and digest('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql')
    == 'BF11954F37BBC2091A5ECC7921D11E102C25054E97EB5BD41A3CB63F19B19538',
)
need(
    'fresh-install prerequisite has exact fail-closed invoker signature',
    'create or replace function public.erp_r35_cloud_command( p_area text, p_action text, p_payload jsonb ) returns jsonb'
    in compact_bootstrap
    and 'security invoker' in compact_bootstrap
    and 'fresh_install_r35_compatibility_must_not_execute' in compact_bootstrap
    and 'from public,anon,authenticated,service_role' in compact_bootstrap,
)
need(
    'orchestrator permits only isolated local CLI operations',
    "'migration', 'up', '--local', '--include-all'" in orchestrator
    and "'db', 'lint', '--local'" in orchestrator
    and "'db', 'advisors', '--local'" in orchestrator
    and "'migration', 'up', '--linked'" not in orchestrator
    and "'db', 'lint', '--linked'" not in orchestrator
    and "'migration', 'up', '--db-url'" not in orchestrator
    and 'havlqebmnjdcwmpaaqew' in orchestrator
    and 'com.supabase.cli.project' in orchestrator,
)
need(
    'orchestrator destroys only its validated disposable stack',
    "'quality-line-erp-fresh-'" in orchestrator
    and '--project-id $localProjectId --no-backup' in orchestrator
    and "Remove-Item -LiteralPath $resolved -Recurse -Force" in orchestrator,
)
need(
    'final-state test rejects placeholders and proves canonical R35 body and ACL',
    'fresh_install_placeholder_survived' in final_state
    and 'canonical_r35_body_mismatch' in final_state
    and 'canonical_r35_privileges_mismatch' in final_state
    and "v_language<>'sql' or not v_security_definer" in final_state,
)
need(
    'retired document-processing table is absent from active monitor implementation',
    'create or replace function public.erp_r9_system_monitor_command' in compact_migration
    and 'erp_document_processing_jobs' not in compact_migration
    and "'pending_sync_operations',0" in compact_migration
    and "'retried_jobs',0" in compact_migration,
)
need(
    'R9 master reads use typed JSON no-row handling',
    compact_migration.count('v_row jsonb;') == 2
    and 'if v_row is null then return null; end if;' in compact_migration
    and 'v_row record' not in compact_migration,
)
need(
    'R15 and R16 canonical table work is statically explicit',
    'foreach v_table' not in compact_migration
    and sum(
        compact_migration.count(
            f"public.erp_r15_pending_delete_exists(p_company_id,'{table}',r.id)"
        )
        for table in (
            'erp_cars', 'erp_car_images', 'erp_customers', 'erp_suppliers',
            'erp_warehouses', 'erp_inventory', 'erp_inventory_groups',
            'erp_product_images',
        )
    ) == 8
    and compact_migration.count("t.source_table='erp_") == 8,
)
need(
    'global search uses authoritative erp_records updated_at fallback',
    "r.updated_at::text)" in compact_migration
    and 'r.created_at' not in compact_migration,
)
need(
    'runtime SQL covers affected modules, currencies, tenants and R50-R51 denial paths',
    all(marker in runtime for marker in (
        'R52 Opportunity', 'R52-SALE', 'R52-PURCHASE', 'R52-MAINTENANCE',
        'R52 Car', 'R52 Product', 'R52-JOURNAL', 'R52-DOC',
        'cross_tenant_a_to_b_unexpected_success',
        'cross_tenant_b_to_a_unexpected_success',
        'anonymous_unexpected_success', 'r51_bridge_marker_leaked',
    )),
)
scripts = package.get('scripts', {})
need(
    'R52 and fresh database commands are registered',
    scripts.get('verify:fresh-db', '').endswith('tool/verify_fresh_database.ps1')
    and scripts.get('verify:r52', '').endswith('verify_r52_fresh_database_lint_runtime_closure.py')
    and 'npm run verify:r52' in scripts.get('verify:workspace', ''),
)

if failures:
    print(f'FAIL R52 fresh database closure - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R52 fresh database lint/runtime closure - 11 gates')
