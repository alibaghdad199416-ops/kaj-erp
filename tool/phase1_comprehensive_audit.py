from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"

# The audit targets page-local query state, not individual widgets. A ChoiceChip
# is a valid presentation primitive and must not be treated as legacy by itself.
PAGE_PATTERNS = {
    "legacy_search_state": re.compile(
        r"final\s+_search\s*=\s*TextEditingController|"
        r"TextEditingController\s+_search"
    ),
    "legacy_stage_state": re.compile(
        r"(?:String|final)\s+_stage\s*=|"
        r"(?:String|final)\s+selectedStage\s*="
    ),
}

MODULE_PAGES = (
    "features/business_partners",
    "features/inventory",
    "features/cars",
    "features/customer_service",
    "features/sales",
    "features/purchases",
    "features/maintenance",
    "features/accounting",
    "features/notifications",
    "features/settings",
)


def dart_files() -> list[Path]:
    return [p for p in LIB.rglob("*.dart") if p.is_file()]


def main() -> int:
    parser = argparse.ArgumentParser(description="KAJ ERP Phase 1 structural audit")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="return non-zero when a tracked legacy pattern is found",
    )
    args = parser.parse_args()

    findings: list[tuple[str, Path]] = []
    page_files = [
        p
        for p in dart_files()
        if any(f"/{module}/" in p.as_posix() for module in MODULE_PAGES)
        and "/pages/" in p.as_posix()
    ]

    for path in page_files:
        text = path.read_text(encoding="utf-8")
        for name, pattern in PAGE_PATTERNS.items():
            if pattern.search(text):
                findings.append((name, path))

    print(f"PHASE1 AUDIT: {'FAIL' if findings else 'PASS'}")
    print(f"checked_pages={len(page_files)}")
    print(f"findings={len(findings)}")
    for name, path in findings:
        print(f"{name}: {path.relative_to(ROOT)}")

    return 1 if args.strict and findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
