from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


checks: dict[str, bool] = {}
model = read('lib/features/maintenance/models/maintenance_order_model.dart')
repo = read('lib/features/maintenance/data/maintenance_repository.dart')
controller = read('lib/features/maintenance/controllers/maintenance_controller.dart')
page = read('lib/features/maintenance/pages/maintenance_page.dart')
r39 = read('supabase/migrations/20260809161514_r39_canonical_maintenance_compile_closure.sql')
latest = read('supabase/migrations/20260826180100_stage3_maintenance_integrity_closure.sql')
r49_permissions = read('supabase/migrations/20260810090000_r49_focused_final_permission_runtime_closure.sql')
r49_identity = read('supabase/migrations/20260810060000_r49_product_identity_accounting_integrity.sql')

checks['editability matches backend lifecycle'] = (
    "workflowStage == 'order_draft' || workflowStage == 'order_approved'" in model
    and "v_target_stage:=coalesce(v_snapshot->>'workflowStage','order_draft')" in r39
)
checks['maintenance create uses permission wrapper'] = (
    'erp_r49_create_cloud_maintenance_order' in repo
    and "'maintenance.create'" in r49_permissions
)
checks['maintenance update uses stale-version guard'] = (
    'erp_r49_update_cloud_maintenance_draft' in repo
    and "'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String()" in repo
    and 'stale_record_conflict' in r49_permissions
)
checks['labor-only maintenance remains supported'] = (
    'jsonb_array_length(v_parts)>0' in r39
    and "else\n    update public.erp_maintenance_parts" in r39
)
checks['maintenance workflow is forward-only'] = all(
    token in latest
    for token in (
        "workflow_stage='order_approved'",
        "workflow_stage='stock_issue_draft'",
        "workflow_stage='stock_issue_approved'",
        "workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end",
        "workflow_stage='invoice_approved'",
    )
)
checks['maintenance material issue is the inventory movement owner'] = (
    'erp_inventory_insert_movement' in latest
    and "'maintenance_out'" in latest
    and 'erp_phase3_post_maintenance_issue' in latest
    and "line_type<>'service'" in latest
)
checks['paid maintenance invoice requires real customer ledger'] = (
    'paid_maintenance_customer_required' in r49_identity
    and 'erp_v764_assert_partner_dual_ledgers' in r49_identity
    and 'erp_workflow_partner_account' in r49_identity
)
checks['maintenance summaries remain currency-separated'] = (
    all(token in controller for token in ('paidRevenueByCurrency', 'totalCostByCurrency', '_sumByCurrency'))
    and 'CurrencyTotalsFormatter.format' in page
)
checks['maintenance page uses granular permissions'] = all(
    token in page
    for token in (
        "'maintenance.create'",
        "'maintenance.update'",
        "'maintenance.delete'",
        "'maintenance.cancel'",
    )
)
checks['maintenance read model preserves authoritative update token'] = (
    "updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '')" in model
    and "jsonb_build_object('updatedAt',o.updated_at)" in r49_permissions
)
checks['no generic maintenance write endpoint is used by the client'] = (
    "'erp_create_cloud_maintenance_order'" not in repo
    and "'erp_update_cloud_maintenance_draft'" not in repo
)

for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL'), name)

if not all(checks.values()):
    sys.exit(1)

print(f'PASS Stage 3 maintenance closure — {len(checks)} gates')
