from __future__ import annotations

from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CONTAINER = os.environ.get(
    "KAJ_LOCAL_SUPABASE_DB_CONTAINER",
    "supabase_db_quality_line_erp_local_dev",
)
TESTS = [
    "supabase/tests/verify_r89_phase11_runtime.sql",
    "supabase/tests/verify_r90_phase11_runtime.sql",
    "supabase/tests/verify_r91_phase11_runtime.sql",
    "supabase/tests/verify_r92_comprehensive_module_audit_runtime.sql",
    "supabase/tests/verify_r93_purchase_receipt_single_action_runtime.sql",
    "supabase/tests/verify_r93_restricted_user_runtime.sql",
]


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    ps = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if ps.returncode != 0:
        fail(f"Unable to inspect local Docker containers: {ps.stderr.strip()}")
    running = {line.strip() for line in ps.stdout.splitlines() if line.strip()}
    if CONTAINER not in running:
        fail(
            "LOCAL Supabase PostgreSQL container is not running: "
            f"{CONTAINER}"
        )

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
                CONTAINER,
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

    print("\nR89-R93 LOCAL PostgreSQL runtime verification PASS")


if __name__ == "__main__":
    main()
