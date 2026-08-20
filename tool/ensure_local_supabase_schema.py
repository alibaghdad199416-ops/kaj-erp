from __future__ import annotations

from pathlib import Path
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCAL_PROJECT_ID = "quality_line_erp_local_dev"
CONTAINER = os.environ.get(
    "KAJ_LOCAL_SUPABASE_DB_CONTAINER",
    "supabase_db_quality_line_erp_local_dev",
)
SUPABASE_CLI = os.environ.get(
    "KAJ_SUPABASE_CLI",
    "npx.cmd" if os.name == "nt" else "npx",
)

# These versions are the minimum schema level required by the Phase 11 runtime
# suite. `supabase migration up --local` still applies every pending migration
# in timestamp order; this list is only the postcondition we enforce.
REQUIRED_MIGRATION_VERSIONS = (
    "20260819210000",  # R88
    "20260820090000",  # R89
    "20260820113000",  # R90
    "20260820124500",  # R91
    "20260820133000",  # R92
    "20260820184500",  # R93 purchase receipt single-action closure
)


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def _local_project_guard() -> None:
    config_path = ROOT / "supabase" / "config.toml"
    if not config_path.is_file():
        fail("Missing supabase/config.toml; refusing to migrate an unknown database.")
    config = config_path.read_text(encoding="utf-8", errors="strict")
    project_match = re.search(
        r'^project_id\s*=\s*"([^"]+)"\s*$',
        config,
        re.MULTILINE,
    )
    project_id = project_match.group(1) if project_match else ""
    if project_id != LOCAL_PROJECT_ID:
        fail(
            "Refusing schema migration because Supabase project_id is not the "
            f"approved LOCAL project ({LOCAL_PROJECT_ID}): {project_id or '<missing>'}"
        )
    if "port = 54322" not in config:
        fail("Refusing schema migration because the approved LOCAL DB port 54322 is missing.")


def _running_containers() -> set[str]:
    result = subprocess.run(
        ["docker", "ps", "--format", "{{.Names}}"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        fail(f"Unable to inspect LOCAL Docker containers: {result.stderr.strip()}")
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def _psql_scalar(sql: str) -> str:
    result = subprocess.run(
        [
            "docker",
            "exec",
            CONTAINER,
            "psql",
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-At",
            "-v",
            "ON_ERROR_STOP=1",
            "-c",
            sql,
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        fail(
            "Unable to inspect LOCAL PostgreSQL migration state: "
            f"{result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout.strip()


def _applied_required_versions() -> set[str]:
    quoted = ",".join(f"'{version}'" for version in REQUIRED_MIGRATION_VERSIONS)
    output = _psql_scalar(
        "select version from supabase_migrations.schema_migrations "
        f"where version in ({quoted}) order by version;"
    )
    return {line.strip() for line in output.splitlines() if line.strip()}


def _discover_local_migration_command() -> None:
    try:
        result = subprocess.run(
            [SUPABASE_CLI, "supabase", "migration", "up", "--help"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError as exc:
        fail(f"Supabase CLI launcher is unavailable ({SUPABASE_CLI}): {exc}")
    help_text = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0 or "--local" not in help_text:
        fail(
            "Installed Supabase CLI does not expose `migration up --local`; "
            "update/repair the local CLI before changing schema state."
        )


def _apply_pending_local_migrations() -> None:
    print("\n=== LOCAL Supabase schema sync: pending forward migrations ===")
    result = subprocess.run(
        [SUPABASE_CLI, "supabase", "migration", "up", "--local"],
        cwd=ROOT,
        check=False,
    )
    if result.returncode != 0:
        fail(
            "LOCAL Supabase pending migration application failed. "
            "No runtime test was executed against the stale schema."
        )


def ensure_local_supabase_schema() -> str:
    """Bring the approved LOCAL database to the committed migration level.

    This is intentionally forward-only. It never targets a linked/hosted project
    and never recreates the database. Existing local data is preserved while the
    CLI applies only migrations missing from the local migration history.
    """

    _local_project_guard()
    running = _running_containers()
    if CONTAINER not in running:
        fail(f"Approved LOCAL Supabase PostgreSQL container is not running: {CONTAINER}")

    _discover_local_migration_command()

    before = _applied_required_versions()
    missing_before = [
        version for version in REQUIRED_MIGRATION_VERSIONS if version not in before
    ]
    if missing_before:
        print(
            "LOCAL schema is behind the Phase 11 runtime baseline; pending required "
            "versions: " + ", ".join(missing_before)
        )
    else:
        print("LOCAL schema already contains the required R88-R93 migration versions.")

    # Always invoke the idempotent pending-migration command. On an up-to-date
    # database the CLI reports no pending migrations; on a stale database it
    # advances history in the repository's timestamp order.
    _apply_pending_local_migrations()

    after = _applied_required_versions()
    missing_after = [
        version for version in REQUIRED_MIGRATION_VERSIONS if version not in after
    ]
    if missing_after:
        fail(
            "LOCAL schema is still missing required Phase 11 migrations after "
            "migration up: " + ", ".join(missing_after)
        )

    trial_balance_filter = _psql_scalar(
        "select coalesce(to_regprocedure(" 
        "'public.erp_r88_filter_trial_balance_row(uuid,jsonb)')::text,'');"
    )
    if not trial_balance_filter:
        fail(
            "LOCAL migration history claims R88 is applied but the trial-balance "
            "filter function is absent; database drift must be repaired before runtime tests."
        )

    print("LOCAL Supabase schema sync PASS — required R88-R93 migrations are applied.")
    return CONTAINER


def main() -> None:
    ensure_local_supabase_schema()


if __name__ == "__main__":
    main()
