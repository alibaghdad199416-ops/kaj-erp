from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def text(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        errors.append(f"missing file: {rel}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def need(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


migration_rel = "supabase/migrations/20260820124500_r91_phase11_material_issue_acceptance_closure.sql"
migration = text(migration_rel)
need("R91 migration missing", bool(migration))
need("R91 must be forward-only", "begin;" in migration.lower() and "commit;" in migration.lower())
need("R91 must not be destructive", not re.search(r"\b(drop\s+schema|drop\s+table|truncate\s+table)\b", migration, re.I))

# Description must come from persisted product data through the secure R9 reader.
for token in [
    "erp_r9_get_cloud_maintenance_order_lines",
    "public.erp_inventory",
    "data->>'description'",
    "data->>'descriptionAr'",
    "data->>'descriptionEn'",
    "'maintenance','items'",
    "erp_r84_record_visible",
]:
    need(f"R91 maintenance description boundary missing {token}", token in migration)

model = text("lib/features/maintenance/models/maintenance_order_model.dart")
need("Maintenance line model missing description", "final String description;" in model)
need("Maintenance line model does not deserialize description", "description: map['description']?.toString() ?? ''" in model)

page = text("lib/features/maintenance/pages/maintenance_order_details_dialog.dart")
need("Maintenance details table still uses generic Stock item description", "Separate labor/service') : _bi('مادة مخزنية', 'Stock item')" not in page)
need("Maintenance details table does not use line.description", "line.description.trim().isNotEmpty" in page)
# The source is formatted by `dart format` before this verifier runs.  Verify
# the semantic guards instead of relying on one exact line-wrapping shape.
need(
    "Maintenance draft helper does not subtract already drafted quantity",
    re.search(
        r"final\s+remaining\s*=\s*\(line\['remainingQuantity'\]\s+as\s+num\?\)\?\.toDouble\(\)\s*\?\?\s*0\s*;[\s\S]*?"
        r"final\s+drafted\s*=\s*\(line\['draftedQuantity'\]\s+as\s+num\?\)\?\.toDouble\(\)\s*\?\?\s*0\s*;[\s\S]*?"
        r"availableToDraft\s*=\s*\(remaining\s*-\s*drafted\)\.clamp\(0,\s*remaining\)\s*;[\s\S]*?"
        r"availableToDraft\s*<=\s*0",
        page,
    ) is not None,
)
need(
    "Fully drafted maintenance line still exposes Add to draft",
    re.search(
        r"trailing\s*:[\s\S]*?remainingQuantity[\s\S]*?-\s*"
        r"[\s\S]*?draftedQuantity[\s\S]*?>\s*0\s*\?\s*FilledButton\.tonalIcon",
        page,
    ) is not None,
)

# Tax/discount columns remain explicit but no fabricated values are introduced.
need("Maintenance invoice Tax column missing", "_bi('الضريبة', 'Tax')" in page)
need("Maintenance invoice Discount column missing", "_bi('الخصم', 'Discount')" in page)
need("Maintenance invoice must not fabricate tax/discount", "const DataCell(AppText('—'))" in page)

# Inventory change must remain approval-owned through R90 draft approval.
r90 = text("supabase/migrations/20260820113000_r90_phase11_final_acceptance_closure.sql")
for token in [
    "erp_r90_save_maintenance_issue_draft_line",
    "'inventoryChanged',false",
    "erp_r90_approve_maintenance_issue_draft",
    "erp_r57_execute_maintenance_material_issue",
    "from authenticated;",
]:
    need(f"R90 approval-owned issue contract missing {token}", token in r90)
need(
    "Direct R57 material issue execution still browser-exposed",
    re.search(
        r"revoke\s+execute\s+on\s+function\s+public\.erp_r57_execute_maintenance_material_issue\([\s\S]*?\)\s+from\s+authenticated",
        r90,
        re.I,
    ) is not None,
)

# R90 must own one event per approved issue draft; R88 must no longer add a
# second event when the final draft advances the order to stock_issue_approved.
need("R90 draft approval notification missing", "'r90:maintenance_material_issue:'||v_draft.id::text" in r90)
need("R91 does not suppress legacy final material-issue notification", "when 'stock_issue_approved' then 'maintenance_material_issue'" not in migration)
need("R91 accidentally removed maintenance invoice notifications", "when 'invoice_approved' then 'maintenance_invoice'" in migration)
need("R91 accidentally removed maintenance payment notifications", "new.paid_amount>old.paid_amount" in migration)

if errors:
    print("R91 Phase 11 material-issue acceptance FAILED")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print("R91 Phase 11 material-issue acceptance PASS")
