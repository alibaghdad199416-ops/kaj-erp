#!/usr/bin/env python3
"""Apply the R101 Flutter General Ledger server-order preservation fix."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "lib/features/accounting/pages/accounting_center_page.dart"

OLD = """                      final accountRows = account.value
                        ..sort((left, right) {
                          final leftDate = '${left['entryDate'] ?? ''}';
                          final rightDate = '${right['entryDate'] ?? ''}';
                          final dateResult = leftDate.compareTo(rightDate);
                          if (dateResult != 0) return dateResult;
                          return '${left['entryNumber'] ?? ''}'.compareTo(
                            '${right['entryNumber'] ?? ''}',
                          );
                        });
"""

NEW = """                      final accountRows = List<Map<String, Object?>>.of(
                        account.value,
                      );
                      // R101 makes General Ledger running balances deterministic
                      // at the database boundary. Preserve that exact server row
                      // order so tied lines from the same journal entry cannot be
                      // reordered after their running balances are calculated.
                      if (widget.type != _AccountingReportType.generalLedger) {
                        accountRows.sort((left, right) {
                          final leftDate = '${left['entryDate'] ?? ''}';
                          final rightDate = '${right['entryDate'] ?? ''}';
                          final dateResult = leftDate.compareTo(rightDate);
                          if (dateResult != 0) return dateResult;
                          return '${left['entryNumber'] ?? ''}'.compareTo(
                            '${right['entryNumber'] ?? ''}',
                          );
                        });
                      }
"""


def main() -> None:
    source = PAGE.read_text(encoding="utf-8", errors="strict")
    old_count = source.count(OLD)
    new_count = source.count(NEW)

    if old_count == 0 and new_count == 1:
        print("R101 GL server-order fix already applied")
        return
    if old_count != 1 or new_count != 0:
        raise SystemExit(
            "Unexpected accounting_center_page.dart state: "
            f"legacy_block={old_count}, fixed_block={new_count}"
        )

    PAGE.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")
    print("Applied R101 GL server-order preservation fix")


if __name__ == "__main__":
    main()
