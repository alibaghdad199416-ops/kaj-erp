from pathlib import Path
from verification_text import contains_code
root=Path(__file__).resolve().parents[1]
checks={
 "migration": root/"supabase/migrations/20260806160000_v751_invoice_stage_premium_ui.sql",
 "sales": root/"lib/features/sales/workflow/pages/sales_workflow_page.dart",
 "purchases": root/"lib/features/purchases/pages/purchase_workflow_page.dart",
 "dialog": root/"lib/features/sales/workflow/pages/order_details_dialog.dart",
 "window": root/"lib/core/widgets/app_full_page_route.dart",
}
for name,path in checks.items():
    if not path.exists(): raise SystemExit(f"FAIL missing {name}: {path}")
text=checks["migration"].read_text(encoding="utf-8")
required=["partially_executed", "erp_v750_approve_workflow_invoice_resilient", "notify pgrst,'reload schema'"]
for token in required:
    if token not in text: raise SystemExit(f"FAIL migration missing {token}")
for key in ("sales","purchases"):
    t=checks[key].read_text(encoding="utf-8")
    if not contains_code(t, "const <String>{'approved','partially_executed',}.contains(status)"):
        raise SystemExit(f"FAIL {key} invoice fallback")
d=checks["dialog"].read_text(encoding="utf-8")
if "_premiumField" not in d or "KajDesignTokens.surfaceGradient" not in d: raise SystemExit("FAIL premium dialog layout")
w=checks["window"].read_text(encoding="utf-8")
if not (("appBar?.title case final title?" in w or "appBar!.title!" in w) and "closeDock" in w and "if (actions.isNotEmpty) const SizedBox(width: 8)," in w): raise SystemExit("FAIL unified window command row")
print("PASS V7.5.1 invoice-stage eligibility, unified close row, localized premium responsive model layout")
