from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"

# These patterns are intentionally conservative: form-local controllers are
# valid, while list-page search/filter state is a Phase 1 migration target.
PAGE_PATTERNS = {
    "legacy_search_state": re.compile(r"final\\s+_search\\s*=\\s*TextEditingController|TextEditingController\\s+_search"),
    "legacy_stage_state": re.compile(r"String\\s+_stage\\s*=|final\\s+_stage\\s*="),
    "legacy_choice_filter": re.compile(r"\\bChoiceChip\\s*\\("),
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
    failures: list[str] = []
    page_files = [
        p for p in dart_files()
        if any(f"/{module}/" in p.as_posix() for module in MODULE_PAGES)
        and "/pages/" in p.as_posix()
    ]

    for path in page_files:
        text = path.read_text(encoding="utf-8")
        for name, pattern in PAGE_PATTERNS.items():
            if pattern.search(text):
                failures.append(f"{name}: {path.relative_to(ROOT)}")

    if failures:
        print("PHASE1 AUDIT: FAIL")
        for item in failures:
            print(item)
        return 1

    print("PHASE1 AUDIT: PASS")
    print(f"checked_pages={len(page_files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
