#!/usr/bin/env python3
"""Apply the narrow analyzer fixes required to reach the R99-R101 runtime gates."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAINTENANCE = ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart"
SALES = ROOT / "lib/features/sales/workflow/pages/order_details_dialog.dart"

MAINTENANCE_SPREAD_OLD = "            if (reconciliation != null) ...reconciliation,\n"
MAINTENANCE_SPREAD_NEW = "            ...?reconciliation,\n"
SALES_SPREAD_OLD = "            if (reconciliation != null) ...reconciliation,\n"
SALES_SPREAD_NEW = "            ...?reconciliation,\n"

INVOICE_MARKER = "  Widget _maintenanceInvoiceTable(MaintenanceOrderModel order) {\n"
RECONCILIATION_HELPER = """  Map<String, Object?>? _reconciliationLine(String lineId) {
    final normalizedId = lineId.trim();
    if (normalizedId.isEmpty) return null;
    for (final row in _costs?.lines ?? const <Map<String, Object?>>[]) {
      if ((row['lineId']?.toString().trim() ?? '') == normalizedId) {
        return row;
      }
    }
    return null;
  }

"""


def replace_once_or_verify(path: Path, old: str, new: str, context: str) -> None:
    source = path.read_text(encoding="utf-8", errors="strict")
    old_count = source.count(old)
    new_count = source.count(new)
    if old_count == 0 and new_count >= 1:
        return
    if old_count != 1:
        raise SystemExit(f"{context}: expected one legacy block, found {old_count}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    replace_once_or_verify(
        MAINTENANCE,
        MAINTENANCE_SPREAD_OLD,
        MAINTENANCE_SPREAD_NEW,
        "maintenance null-aware lifecycle spread",
    )
    replace_once_or_verify(
        SALES,
        SALES_SPREAD_OLD,
        SALES_SPREAD_NEW,
        "sales null-aware lifecycle spread",
    )

    source = MAINTENANCE.read_text(encoding="utf-8", errors="strict")
    if RECONCILIATION_HELPER not in source:
        if source.count(INVOICE_MARKER) != 1:
            raise SystemExit("maintenance reconciliation helper insertion marker not unique")
        source = source.replace(
            INVOICE_MARKER,
            RECONCILIATION_HELPER + INVOICE_MARKER,
            1,
        )
        MAINTENANCE.write_text(source, encoding="utf-8")

    print("Applied focused analyzer blockers for R99-R101 closure")


if __name__ == "__main__":
    main()
