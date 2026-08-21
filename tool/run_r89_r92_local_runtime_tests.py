from __future__ import annotations

from pathlib import Path
import subprocess
import sys

from ensure_local_supabase_schema import ensure_local_supabase_schema

ROOT = Path(__file__).resolve().parents[1]
TESTS = [
    "supabase/tests/verify_r89_phase11_runtime.sql",
    "supabase/tests/verify_r90_phase11_runtime.sql",
    "supabase/tests/verify_r91_phase11_runtime.sql",
    "supabase/tests/verify_r92_comprehensive_module_audit_runtime.sql",
    "supabase/tests/verify_r93_purchase_receipt_single_action_runtime.sql",
    "supabase/tests/verify_r93_restricted_user_runtime.sql",
    "supabase/tests/verify_r94_legacy_endpoint_acl_runtime.sql",
    # R99 regression reuses the canonical R49 end-to-end transaction fixture.
    # That suite advances a sales order through approved deliveries to the
    # active partially_executed stage before approving its invoice, verifies
    # balanced AR/revenue + COGS/inventory journals, and proves invoice approval
    # does not mutate stock. It therefore fails on the pre-R99 literal
    # status='approved' posting guard and passes only with the active-stage fix.
    "supabase/tests/verify_r49_erp_transactions_runtime.sql",
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

    print("\nR49 + R89-R99 LOCAL PostgreSQL runtime verification PASS")


if __name__ == "__main__":
    main()
