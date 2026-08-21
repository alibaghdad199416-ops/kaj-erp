from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DETAILS = ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


def block(text: str, start_marker: str, end_marker: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start + len(start_marker))
    return text[start:end]


text = DETAILS.read_text(encoding="utf-8")
init_state = block(text, "  void initState() {", "  bool get _isOrderDraft")
draft_loader = block(
    text,
    "  Future<void> _loadDraftCoreLines() async {",
    "  Future<void> _loadDetails() async {",
)
reload_details = block(
    text,
    "  Future<void> _reloadDetails() =>",
    "  Future<void> _loadDraftCoreLines() async {",
)

require(
    "const <String>{'draft', 'order_draft'}.contains(_order.workflowStage)" in text,
    "both persisted draft stage spellings are recognized",
)
require(
    "if (_isOrderDraft)" in init_state
    and "_loading = false;" in init_state
    and "unawaited(_loadDraftCoreLines());" in init_state,
    "draft renders immediately and loads only core lines",
)
require(
    init_state.index("if (_isOrderDraft)") < init_state.index("unawaited(_loadDetails());"),
    "draft branch runs before downstream snapshot loading",
)
require(
    "_isOrderDraft ? _loadDraftCoreLines() : _loadDetails()" in reload_details,
    "refresh preserves the draft-safe loading path",
)
require(
    "_repository.getOrderLines(_order.id)" in draft_loader,
    "draft loader reads authoritative order lines",
)
for forbidden in (
    "getOrderSnapshot",
    "getCostReconciliation",
    "getMaintenancePayments",
):
    require(
        forbidden not in draft_loader,
        f"draft loader does not depend on optional downstream data: {forbidden}",
    )
require(
    "_error = null;" in draft_loader
    and "_loadWarning = userFacingError(" in draft_loader,
    "draft line failure stays visible as warning instead of blank/error workspace",
)
require(
    "The maintenance draft was opened, but some lines could not be loaded." in draft_loader,
    "draft reopen failure exposes a retryable user-facing message",
)
require(
    "A persisted order draft has no downstream stock/invoice state yet." in init_state,
    "draft isolation intent remains documented next to the branch",
)

print("R95 maintenance draft reopen guard PASS")
