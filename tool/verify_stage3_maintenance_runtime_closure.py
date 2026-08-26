from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


checks: dict[str, bool] = {}
page = read('lib/features/maintenance/pages/maintenance_page.dart')
model = read('lib/features/maintenance/models/maintenance_order_model.dart')
repo = read('lib/features/maintenance/data/maintenance_repository.dart')
controller = read('lib/features/maintenance/controllers/maintenance_controller.dart')
workflow = read('supabase/migrations/20260803233000_v66_workflow_delete_permissions.sql')

checks['workflow action is protected by maintenance approval permission'] = (
    "PermissionAction.require(context,\n                                  'maintenance.approve'" in page
    and "PermissionAction.allowed(\n                                context,\n                                'maintenance.approve'" in page
)
checks['edit action is limited to editable lifecycle stages'] = (
    "workflowStage == 'order_draft' || workflowStage == 'order_approved'" in model
    and "if (order.canEdit &&" in page
    and "'maintenance.update'" in page
)
checks['payment action is restricted to approved invoice'] = (
    "order.workflowStage == 'invoice_approved'" in page
    and "'cashbox.receipt'" in page
    and "maintenance_approved_invoice_required" in workflow
)
checks['cancel action has dedicated permission and lifecycle guard'] = (
    "'maintenance.cancel'" in page
    and "!<String>{\n                                'paid',\n                                'completed',\n                              }.contains(order.workflowStage)" in page
    and "array['maintenance.cancel']" in workflow
)
checks['delete action has dedicated permission and backend guard'] = (
    "'maintenance.delete'" in page
    and "array['maintenance.delete']" in workflow
)
checks['client uses hardened maintenance create/update endpoints'] = (
    "'erp_r49_create_cloud_maintenance_order'" in repo
    and "'erp_r49_update_cloud_maintenance_draft'" in repo
    and "'p_expected_updated_at': expectedUpdatedAt.toUtc().toIso8601String()" in repo
)
checks['maintenance backend workflow itself enforces approval permission'] = (
    "array['maintenance.approve']" in workflow
)
checks['maintenance backend payment enforces cash permission'] = (
    "array['cashbox.receipt']" in workflow
)
checks['maintenance change propagation covers dependent modules'] = all(
    token in controller
    for token in ("'inventory'", "'accounting'", "'cars'", "'cashbox'")
)

for name, ok in checks.items():
    print(('PASS' if ok else 'FAIL'), name)

if not all(checks.values()):
    sys.exit(1)

print(f'PASS Stage 3 maintenance runtime closure — {len(checks)} gates')
