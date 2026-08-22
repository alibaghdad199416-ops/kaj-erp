from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260821051500_r95_2_granular_invoice_approval_backend_guard.sql"
V742 = ROOT / "supabase/migrations/20260806064500_v742_conflict_free_workflow_and_accounting.sql"
V750 = ROOT / "supabase/migrations/20260806143000_v750_rpc_runtime_recovery.sql"
V760 = ROOT / "supabase/migrations/20260807013000_v760_no_capitalization_accounting_integrity.sql"
R22 = ROOT / "supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


def function_block(text: str, name: str) -> str:
    marker = f"create or replace function public.{name}("
    start = text.index(marker)
    next_create = text.find("create or replace function public.", start + len(marker))
    if next_create == -1:
        next_create = text.find("commit;", start)
    return text[start:next_create if next_create != -1 else len(text)]


text = MIGRATION.read_text(encoding="utf-8")
v742 = V742.read_text(encoding="utf-8")
v750 = V750.read_text(encoding="utf-8")
v760 = V760.read_text(encoding="utf-8")
r22 = R22.read_text(encoding="utf-8")

require(text.lstrip().lower().startswith("begin;"), "R95.2 migration is forward-only")
require(text.rstrip().endswith("commit;"), "R95.2 commits atomically")

require(
    "pg_get_functiondef(" in text
    and "'public.erp_approve_cloud_workflow_invoice(uuid,uuid,text)'::regprocedure" in text,
    "active V742 posting engine is patched in place instead of reimplemented",
)
require(
    "r95_2_invoice_posting_guard_signature_changed" in text
    and "r95_2_invoice_posting_guard_ambiguous" in text,
    "posting-engine authorization patch fails closed on source drift",
)

core_old_guard = """perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.approve','sales.update'] else array['purchases.approve','purchases.update'] end);"""
require(core_old_guard in v742, "historical V742 broad invoice guard is still present")
require(core_old_guard in text, "R95.2 targets the exact historical V742 guard")

for token in (
    "sales.actions.restrict",
    "sales.invoice.approve",
    "purchases.actions.restrict",
    "purchases.invoice.approve",
):
    require(token in text, f"R95.2 contains {token}")

r22_new = function_block(text, "erp_r22_approve_workflow_invoice")
require(
    "erp_r95_user_can_perform_action" in r22_new,
    "R22 browser approval surface uses canonical granular action guard",
)
require(
    "erp_cloud_user_has_permission(p_company_id,v_required_permission)" not in r22_new,
    "R22 no longer hard-requires only the broad approve permission",
)
for token in (
    "erp_r22_invoice_preflight",
    "erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales')",
    "erp_r22_post_purchase_invoice_direct(p_company_id,p_invoice_id)",
    "erp_v762_assert_posted_journal_balanced",
    "erp_v73_recompute_commercial_order_status",
):
    require(token in r22_new, f"R22 preserves posting/integrity contract: {token}")

v760_new = function_block(text, "erp_v760_approve_workflow_invoice")
helper_index = v760_new.index("erp_r95_user_can_perform_action")
fallback_index = v760_new.index("erp_v750_approve_workflow_invoice_resilient")
require(
    helper_index < fallback_index,
    "V760 authorizes before entering resilient V750 fallback",
)
require(
    "erp_v760_normalize_purchase_invoice_posting" in v760_new,
    "V760 purchase no-capitalization normalization remains intact",
)

require(
    "exception when others" in function_block(v750, "erp_v750_approve_workflow_invoice_resilient"),
    "historical V750 fallback catches posting errors and therefore needs an external guard",
)
require(
    "grant execute on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text) to authenticated,service_role;"
    in v750,
    "historical V750 was browser-callable before R95.2",
)
require(
    "revoke all on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text)"
    in text
    and "from public,anon,authenticated;" in text,
    "R95.2 removes direct authenticated access to V750 fallback engine",
)
require(
    "grant execute on function public.erp_v750_approve_workflow_invoice_resilient(uuid,uuid,text)"
    in text
    and "to service_role;" in text,
    "V750 remains available to trusted internal/service execution",
)

require(
    "return public.erp_v760_approve_workflow_invoice(p_company_id,p_component_id,p_module);"
    in v760,
    "legacy commercial component endpoint still converges through guarded V760",
)
require(
    "select public.erp_r22_approve_workflow_invoice($1,$2,$3)"
    in r22,
    "R22 compatibility V762 endpoint converges to current R22 approval",
)
require(
    "grant execute on function public.erp_r22_post_purchase_invoice_direct(uuid,uuid) to service_role;"
    in r22,
    "direct R22 purchase posting engine remains service-role only",
)

require(
    "notify pgrst,'reload schema';" in text,
    "PostgREST schema cache reload is requested",
)

print("R95.2 granular invoice approval backend guard PASS")
