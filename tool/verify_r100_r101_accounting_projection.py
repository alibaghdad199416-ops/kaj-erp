#!/usr/bin/env python3
"""R100/R101 accounting report projection and GL presentation contract."""
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        raise AssertionError(f"missing required file: {rel}")
    return path.read_text(encoding="utf-8", errors="strict")


def require(source: str, needle: str, context: str) -> None:
    if needle not in source:
        raise AssertionError(f"{context}: missing {needle!r}")


def main() -> int:
    page = read("lib/features/accounting/pages/accounting_center_page.dart")
    repository = read(
        "lib/features/accounting/repositories/professional_accounting_repository.dart"
    )
    r100 = read(
        "supabase/migrations/20260821193000_r100_accounting_report_projection_closure.sql"
    )
    r101 = read(
        "supabase/migrations/20260821200000_r101_gl_running_balance_deterministic_closure.sql"
    )
    runner = read("tool/run_r89_r92_local_runtime_tests.py")

    for key in (
        "openingDebit",
        "openingCredit",
        "periodDebit",
        "periodCredit",
        "closingDebit",
        "closingCredit",
    ):
        require(
            page,
            f"DataCell(amountCell(row, '{key}'))",
            "Trial Balance six-column presentation",
        )

    require(page, "'runningBalance'", "GL running-balance column")
    require(page, "'Running balance'", "GL English label")
    require(page, "'الرصيد التراكمي'", "GL Arabic label")
    require(
        page,
        "final accountRows = List<Map<String, Object?>>.of(",
        "GL must preserve server row order",
    )
    require(
        page,
        "if (widget.type != _AccountingReportType.generalLedger) {",
        "GL must not be re-sorted after server running-balance calculation",
    )

    require(
        repository,
        "'erp_r22_cloud_detailed_accounting_report'",
        "guarded report RPC",
    )
    for param in ("p_from_date", "p_to_date", "p_branch_id", "p_cost_center_id"):
        require(repository, f"'{param}'", "report filter contract")

    mappings = {
        "openingDebit": "debit",
        "openingCredit": "credit",
        "periodDebit": "debit",
        "periodCredit": "credit",
        "closingDebit": "debit",
        "closingCredit": "credit",
        "runningBalance": "balances",
    }
    for key, field in mappings.items():
        require(
            r100,
            f"when '{key}' then '{field}'",
            "R100 guarded accounting projection",
        )

    require(
        r101,
        "line.entry_id,",
        "R101 deterministic running-balance tie-breaker",
    )
    require(
        r101,
        "line.line_id",
        "R101 deterministic running-balance tie-breaker",
    )
    require(
        r101,
        "lower(coalesce(p_report_type,''))='generalledger'",
        "R22 stable GL routing",
    )
    require(
        r101,
        "from public.erp_r101_cloud_general_ledger(",
        "R22 routes GL through R101",
    )

    for runtime_test in (
        "supabase/tests/verify_r100_accounting_report_projection_runtime.sql",
        "supabase/tests/verify_r101_gl_running_balance_runtime.sql",
    ):
        require(runner, f'"{runtime_test}"', "canonical Local Supabase runner")

    print("PASS R100/R101 accounting projection and deterministic GL presentation contract")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAILED R100/R101 accounting projection contract: {exc}", file=sys.stderr)
        raise SystemExit(1)
