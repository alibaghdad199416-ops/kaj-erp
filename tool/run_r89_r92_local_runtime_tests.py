from __future__ import annotations

from pathlib import Path
import subprocess
import sys

from ensure_local_supabase_schema import ensure_local_supabase_schema

ROOT = Path(__file__).resolve().parents[1]
TESTS = [
    # Current maintenance accounting ownership: material issue owns FIFO/COGS,
    # invoice owns receivable/revenue without duplicate inventory-cost posting.
    "supabase/tests/verify_r58_maintenance_item_accounting_runtime.sql",
    "supabase/tests/verify_r89_phase11_runtime.sql",
    "supabase/tests/verify_r90_phase11_runtime.sql",
    "supabase/tests/verify_r91_phase11_runtime.sql",
    "supabase/tests/verify_r92_comprehensive_module_audit_runtime.sql",
    "supabase/tests/verify_r93_purchase_receipt_single_action_runtime.sql",
    "supabase/tests/verify_r93_restricted_user_runtime.sql",
    "supabase/tests/verify_r94_legacy_endpoint_acl_runtime.sql",
    # Focused R99 proof executes the real approval wrapper against an active
    # partially_executed Sales Order and verifies atomic temporary-stage rollback.
    "supabase/tests/verify_r99_sales_invoice_active_stage_runtime.sql",
    # Current wrapper-chain proof prevents regressions from R99/R90/R88/R37 into
    # the R87 maintenance invoice accounting + material-issue ownership contract.
    "supabase/tests/verify_r99_maintenance_invoice_current_workflow_runtime.sql",
]


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    # Runtime tests are only meaningful against the schema represented by the
    # committed migration history. A long-running local stack can otherwise be
    # several releases behind even though the source checkout is current.
    container = ensure_local_supabase_schema()

    for rel in TESTS:
        path = ROOT / rel
        if not path.is_file():
            fail(f"Missing LOCAL PostgreSQL runtime test: {rel}")
        print(f"\n=== LOCAL PostgreSQL runtime: {rel} ===")
        sql = path.read_text(encoding="utf-8", errors="strict")
        result = subprocess.run(
            [
                "docker",
                "exec",
                "-i",
                container,
                "psql",
                "-U",
                "postgres",
                "-d",
                "postgres",
                "-v",
                "ON_ERROR_STOP=1",
            ],
            cwd=ROOT,
            input=sql,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if result.returncode != 0:
            fail(f"LOCAL PostgreSQL runtime verification failed: {rel}")

    print("\nR58 + R89-R99 LOCAL PostgreSQL runtime verification PASS")


if __name__ == "__main__":
    main()
