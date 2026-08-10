#!/usr/bin/env python3
"""Verify the Phase 3 maintenance and opportunity luxury experience."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

checks = {
    "pubspec version": (ROOT / "pubspec.yaml", "version: 19.3.0+193000"),
    "phase 3 components": (
        ROOT / "lib/design_system/kaj_phase3_components.dart",
        "class KajPhaseHero",
    ),
    "maintenance hero": (
        ROOT / "lib/features/maintenance/pages/maintenance_page.dart",
        "AFTERSALES COMMAND CENTER",
    ),
    "maintenance stepper": (
        ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart",
        "KajWorkflowStepper",
    ),
    "maintenance intake": (
        ROOT / "lib/features/maintenance/pages/add_maintenance_order_page.dart",
        "PREMIUM SERVICE INTAKE",
    ),
    "opportunity center": (
        ROOT / "lib/features/customer_service/pages/customer_service_page.dart",
        "CUSTOMER EXPERIENCE & GROWTH",
    ),
    "opportunity form": (
        ROOT / "lib/features/customer_service/pages/add_opportunity_page.dart",
        "CUSTOMER JOURNEY DESIGN",
    ),
    "opportunity badge": (
        ROOT / "lib/features/customer_service/widgets/opportunity_card.dart",
        "KajStatusBadge",
    ),
    "release notes": (ROOT / "RELEASE_19.3.0_AR.md", "المرحلة الثالثة"),
}

errors: list[str] = []
for label, (path, marker) in checks.items():
    if not path.exists():
        errors.append(f"missing {label}: {path.relative_to(ROOT)}")
        continue
    text = path.read_text(encoding="utf-8", errors="ignore")
    if marker not in text:
        errors.append(f"missing marker for {label}: {marker!r}")

if errors:
    print("FAIL Phase 3 luxury verification")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("PASS Phase 3 maintenance and opportunity luxury verification")
