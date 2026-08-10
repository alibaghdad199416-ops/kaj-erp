from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    "phase4 components": ROOT / "lib/design_system/kaj_phase4_components.dart",
    "maintenance command center": ROOT / "lib/features/maintenance/pages/maintenance_page.dart",
    "maintenance intake": ROOT / "lib/features/maintenance/pages/add_maintenance_order_page.dart",
    "maintenance details": ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart",
    "partner center": ROOT / "lib/features/business_partners/pages/business_partners_page.dart",
    "customer service": ROOT / "lib/features/customer_service/pages/customer_service_page.dart",
    "opportunity form": ROOT / "lib/features/customer_service/pages/add_opportunity_page.dart",
    "opportunity card": ROOT / "lib/features/customer_service/widgets/opportunity_card.dart",
}
for name, path in checks.items():
    if not path.exists():
        raise SystemExit(f"FAIL missing {name}: {path}")

assert "21.3.0+213000" in (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
assert "KajPhaseHero" in checks["maintenance command center"].read_text(encoding="utf-8")
assert "KajWorkflowStepper" in checks["maintenance intake"].read_text(encoding="utf-8")
assert "KajPartnerHero" in checks["partner center"].read_text(encoding="utf-8")
assert "Business partner center" in checks["partner center"].read_text(encoding="utf-8")
assert "Commercial opportunity center" in checks["customer service"].read_text(encoding="utf-8")
assert "KajPartnerCardShell" in checks["opportunity card"].read_text(encoding="utf-8")
assert "appBar: AppBar" not in checks["opportunity form"].read_text(encoding="utf-8")
print("PASS V21.3 Phase 4 maintenance, partners, customer service and CRM verification")
