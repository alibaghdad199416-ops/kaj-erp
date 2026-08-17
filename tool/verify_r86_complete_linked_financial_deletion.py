from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "supabase" / "config.toml"
SQL_TEST = ROOT / "supabase" / "tests" / "verify_r86_complete_linked_financial_deletion.sql"
EXPECTED_PROJECT_ID = "quality_line_erp_local_dev"
PASS_MARKER = "R86 complete linked financial deletion PASS"


def fail(message: str, output: str | None = None) -> "NoReturn":
    if output:
        print(output.rstrip(), file=sys.stderr)
    raise SystemExit(f"FAIL: {message}")


def local_host(url: str, label: str) -> None:
    parsed = urlparse(url.strip().strip('"').strip("'"))
    if parsed.hostname not in {"127.0.0.1", "localhost"}:
        fail(f"{label} is not local: {url}")


def parse_status_env(output: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in output.splitlines():
        match = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*[\"']?(.*?)[\"']?\s*$", raw)
        if match:
            values[match.group(1)] = match.group(2)
    return values


def main() -> int:
    if not CONFIG.is_file():
        fail("supabase/config.toml is missing")
    if not SQL_TEST.is_file():
        fail(f"SQL regression file is missing: {SQL_TEST.relative_to(ROOT)}")

    config = CONFIG.read_text(encoding="utf-8")
    project_match = re.search(r'^\s*project_id\s*=\s*"([^"]+)"', config, re.MULTILINE)
    project_id = project_match.group(1) if project_match else ""
    if project_id != EXPECTED_PROJECT_ID:
        fail(
            "refusing to run against an unexpected Supabase project_id: "
            f"{project_id or '<missing>'}"
        )

    npx = shutil.which("npx.cmd") or shutil.which("npx")
    docker = shutil.which("docker.exe") or shutil.which("docker")
    if not npx:
        fail("npx is required to verify the local Supabase stack")
    if not docker:
        fail("Docker CLI is required to execute the SQL inside Local Supabase Postgres")

    status = subprocess.run(
        [npx, "--no-install", "supabase", "status", "-o", "env"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if status.returncode != 0:
        fail("Local Supabase is not running", status.stdout)

    status_env = parse_status_env(status.stdout)
    api_url = status_env.get("API_URL", "")
    db_url = status_env.get("DB_URL", "")
    if not api_url:
        fail("supabase status did not expose API_URL", status.stdout)
    local_host(api_url, "API_URL")
    if db_url:
        local_host(db_url, "DB_URL")

    containers = subprocess.run(
        [docker, "ps", "--format", "{{.Names}}"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if containers.returncode != 0:
        fail("could not inspect Docker containers", containers.stdout)

    names = [line.strip() for line in containers.stdout.splitlines() if line.strip()]
    expected_name = f"supabase_db_{project_id}"
    if expected_name in names:
        db_container = expected_name
    else:
        candidates = [
            name
            for name in names
            if name.startswith("supabase_db_") and project_id in name
        ]
        if len(candidates) != 1:
            fail(
                "could not uniquely resolve the Local Supabase Postgres container; "
                f"expected {expected_name}, candidates={candidates}"
            )
        db_container = candidates[0]

    sql = SQL_TEST.read_bytes()
    result = subprocess.run(
        [
            docker,
            "exec",
            "-i",
            db_container,
            "psql",
            "-X",
            "-v",
            "ON_ERROR_STOP=1",
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-f",
            "-",
        ],
        cwd=ROOT,
        input=sql,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = result.stdout.decode("utf-8", errors="replace")
    print(output.rstrip())
    if result.returncode != 0:
        fail("R86 linked financial deletion SQL regression failed")
    if PASS_MARKER not in output:
        fail("SQL regression completed without the expected PASS marker")

    print("PASS: R86 linked financial deletion verified on Local Supabase only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
