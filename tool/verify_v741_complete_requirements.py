from pathlib import Path
import re

from verification_text import contains_code

root = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8", errors="strict")


def _windows(text: str, anchor: str, before: int = 600, after: int = 1800):
    start = 0
    while True:
        index = text.find(anchor, start)
        if index < 0:
            return
        yield text[max(0, index - before): min(len(text), index + after)]
        start = index + len(anchor)


def _has_statuses(text: str) -> bool:
    return all(f"'{status}'" in text for status in ("approved", "posted", "completed", "confirmed"))


def has_sales_invoice_fallback(text: str) -> bool:
    """Validate eligibility behavior without depending on physical Dart layout."""
    for region in _windows(text, "'canCreateInvoice'", before=300, after=2600):
        if (
            _has_statuses(region)
            and "deliveryStatus" in region
            and "invoiceId" in region
            and "canCreateInvoice" in region
            and contains_code(region, ".trim().toLowerCase()")
            and ("_invoice(" in region or "Create Invoice" in region or "إنشاء فاتورة" in region)
        ):
            return True
    return False


def has_details_invoice_fallback(text: str) -> bool:
    """Validate details-dialog invoice fallback after logistics completion."""
    # Anchor on the actual logistics status variable, then locate a region that
    # also owns the invoice action. This survives formatter wrapping and commas.
    for match in re.finditer(r"\blogisticsStatus\b", text):
        start = max(0, match.start() - 900)
        end = min(len(text), match.start() + 2600)
        region = text[start:end]
        if not _has_statuses(region):
            continue
        if not contains_code(region, "invoice == null"):
            continue
        if "_createInvoiceDraft" not in region and "Create purchase invoice draft" not in region and "Create sales invoice draft" not in region:
            continue
        return True
    return False


checks = {
    "version": contains_code(read("pubspec.yaml"), "version: 22.9.8+229008"),
    "migration": (root / "supabase/migrations/20260806053000_v741_final_workflow_accounting_fx_ui.sql").exists(),
    "responsive reflow without canvas scaling": (
        "FittedBox(" not in read("lib/core/widgets/app_full_page_route.dart")
        and "preferred.width.clamp(minimum.width, available.width)" in read("lib/core/widgets/app_full_page_route.dart")
        and "preferred.height" in read("lib/core/widgets/app_full_page_route.dart")
    ),
    "integrated close": "AppWindowCloseButton" in read("lib/core/widgets/app_entity_page.dart"),
    "sales invoice fallback": has_sales_invoice_fallback(read("lib/features/sales/workflow/pages/sales_workflow_page.dart")),
    "details invoice fallback": has_details_invoice_fallback(read("lib/features/sales/workflow/pages/order_details_dialog.dart")),
    "definition accounting": "erp_v736_item_accounting" in read("supabase/migrations/20260806040000_v740_definition_accounting_fx_payments_compact_numbers.sql"),
    "compact references": "compactReference" in read("supabase/migrations/20260806053000_v741_final_workflow_accounting_fx_ui.sql"),
}
missing = [key for key, value in checks.items() if not value]
if missing:
    print("FAIL V7.4.1:", ", ".join(missing))
    raise SystemExit(1)
print("PASS V7.4.1 complete requirements verification")
for key in checks:
    print("  -", key)
