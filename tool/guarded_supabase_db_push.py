#!/usr/bin/env python3
"""Run Supabase db push with a bounded R57 out-of-order migration guard."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


COMPAT_VERSION = "20260809124735"
# The exceptional compatibility file is safe only for an existing database
# that has already crossed its immediate chronological successor. Requiring a
# later R57 migration here incorrectly rejects restored databases whose valid
# history ends before the newer R57 work (for example 20260811191823).
EXISTING_DATABASE_FLOOR = "20260809124736"
EXPECTED_LINKED_PROJECT_REF = "havlqebmnjdcwmpaaqew"
MIGRATION_PATTERN = re.compile(r"(20\d{12}_[A-Za-z0-9_]+\.sql)")


class GuardError(RuntimeError):
    """A migration state or CLI result failed the bounded safety policy."""


@dataclass(frozen=True)
class MigrationState:
    local_versions: frozenset[str]
    remote_versions: frozenset[str]
    latest_remote: str | None
    missing_local_versions: tuple[str, ...]
    historical_gaps: tuple[str, ...]
    remote_only_versions: tuple[str, ...]
    use_include_all: bool


def classify_history(rows: Iterable[dict[str, object]]) -> MigrationState:
    local = {
        str(row.get("local", "")).strip()
        for row in rows
        if str(row.get("local", "")).strip()
    }
    remote = {
        str(row.get("remote", "")).strip()
        for row in rows
        if str(row.get("remote", "")).strip()
    }
    latest = max(remote) if remote else None
    missing = tuple(sorted(local - remote))
    historical = tuple(
        version for version in missing if latest is not None and version < latest
    )
    remote_only = tuple(sorted(remote - local))

    if remote_only:
        raise GuardError(
            "Database migration history contains versions absent from the repository: "
            + ", ".join(remote_only)
        )
    if historical:
        if (
            historical != (COMPAT_VERSION,)
            or latest is None
            or latest < EXISTING_DATABASE_FLOOR
        ):
            raise GuardError(
                "Unexpected out-of-order migration gap; refusing database push: "
                + ", ".join(historical)
            )
        use_include_all = True
    else:
        use_include_all = False

    return MigrationState(
        local_versions=frozenset(local),
        remote_versions=frozenset(remote),
        latest_remote=latest,
        missing_local_versions=missing,
        historical_gaps=historical,
        remote_only_versions=remote_only,
        use_include_all=use_include_all,
    )


def migration_files_by_version(migrations_dir: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted(migrations_dir.glob("*.sql")):
        version = path.name.split("_", 1)[0]
        if not re.fullmatch(r"20\d{12}", version):
            continue
        if version in result:
            raise GuardError(f"Duplicate migration version in repository: {version}")
        result[version] = path.name
    return result


def validate_exceptional_dry_run(
    state: MigrationState,
    dry_run_output: str,
    files_by_version: dict[str, str],
) -> tuple[str, ...]:
    if not state.use_include_all:
        raise GuardError("Exceptional dry-run validation requested for normal history")

    unknown_versions = [
        version
        for version in state.missing_local_versions
        if version not in files_by_version
    ]
    if unknown_versions:
        raise GuardError(
            "Missing repository filename for migration version(s): "
            + ", ".join(unknown_versions)
        )

    expected = {
        files_by_version[version] for version in state.missing_local_versions
    }
    actual = set(MIGRATION_PATTERN.findall(dry_run_output))
    if actual != expected:
        unexpected = sorted(actual - expected)
        omitted = sorted(expected - actual)
        details: list[str] = []
        if unexpected:
            details.append("unexpected=" + ", ".join(unexpected))
        if omitted:
            details.append("omitted=" + ", ".join(omitted))
        raise GuardError(
            "Bounded --include-all dry-run did not match migration history ("
            + "; ".join(details)
            + ")"
        )

    unexpected_historical = sorted(
        version
        for version in state.missing_local_versions
        if state.latest_remote is not None
        and version < state.latest_remote
        and version != COMPAT_VERSION
    )
    if unexpected_historical:
        raise GuardError(
            "Dry-run includes unexpected historical migration(s): "
            + ", ".join(unexpected_historical)
        )
    if files_by_version[COMPAT_VERSION] not in actual:
        raise GuardError("R57 compatibility migration is absent from exceptional dry-run")
    return tuple(sorted(actual))


class SupabaseRunner:
    def __init__(self, executable: str, target_args: Sequence[str], workdir: Path):
        self.executable = executable
        self.target_args = list(target_args)
        self.workdir = workdir

    def run(
        self,
        args: Sequence[str],
        *,
        allow_failure: bool = False,
        echo: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        completed = subprocess.run(
            [self.executable, *args],
            cwd=self.workdir,
            env={
                **os.environ,
                "SUPABASE_TELEMETRY_DISABLED": "1",
                "DO_NOT_TRACK": "1",
            },
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        combined = "\n".join(
            value.strip() for value in (completed.stdout, completed.stderr) if value.strip()
        )
        if combined and echo:
            print(combined)
        if completed.returncode != 0 and not allow_failure:
            raise GuardError(
                f"Supabase CLI failed with exit code {completed.returncode}"
            )
        return completed

    def migration_list(self) -> MigrationState:
        result = self.run(
            [
                "migration",
                "list",
                *self.target_args,
                "--output-format",
                "json",
                "--workdir",
                str(self.workdir),
            ],
            echo=False,
        )
        try:
            payload = json.loads(result.stdout)
            rows = payload["migrations"]
        except (json.JSONDecodeError, KeyError, TypeError) as error:
            raise GuardError("Could not parse Supabase migration history JSON") from error
        if not isinstance(rows, list):
            raise GuardError("Supabase migration history JSON has an invalid shape")
        return classify_history(rows)

    def db_push(
        self,
        *,
        dry_run: bool,
        include_all: bool,
        yes: bool,
    ) -> subprocess.CompletedProcess[str]:
        args = ["db", "push", *self.target_args]
        if dry_run:
            args.append("--dry-run")
        if include_all:
            args.append("--include-all")
        if yes:
            args.append("--yes")
        args.extend(["--workdir", str(self.workdir)])
        return self.run(args)


def find_supabase_executable(explicit: str | None, root: Path) -> str:
    if explicit:
        return explicit
    local = root / "node_modules" / ".bin" / (
        "supabase.cmd" if sys.platform == "win32" else "supabase"
    )
    if local.is_file():
        return str(local)
    discovered = shutil.which("supabase")
    if discovered:
        return discovered
    raise GuardError("Supabase CLI executable was not found")


def assert_expected_linked_project(root: Path) -> None:
    ref_file = root / "supabase" / ".temp" / "project-ref"
    if not ref_file.is_file():
        raise GuardError(
            "Linked Supabase project is not established. Run 'supabase link --project-ref "
            f"{EXPECTED_LINKED_PROJECT_REF}' first."
        )
    linked = ref_file.read_text(encoding="utf-8").strip()
    if linked != EXPECTED_LINKED_PROJECT_REF:
        raise GuardError(
            "Refusing linked database operation: repository is linked to "
            f"'{linked}', expected '{EXPECTED_LINKED_PROJECT_REF}'."
        )


def execute_guarded_push(
    runner: SupabaseRunner,
    migrations_dir: Path,
    *,
    dry_run_only: bool,
    yes: bool,
) -> str:
    state = runner.migration_list()
    files = migration_files_by_version(migrations_dir)

    if state.use_include_all:
        print(
            "GUARDED_R57_MODE: exact historical gap "
            f"{COMPAT_VERSION}; bounded --include-all preflight required"
        )
        preview = runner.db_push(dry_run=True, include_all=True, yes=yes)
        combined = preview.stdout + "\n" + preview.stderr
        pending = validate_exceptional_dry_run(state, combined, files)
        print("GUARDED_R57_PREFLIGHT: " + ", ".join(pending))
        if dry_run_only:
            return "exceptional-dry-run"
        rechecked = runner.migration_list()
        if rechecked != state:
            raise GuardError("Migration history changed after bounded preflight")
        runner.db_push(dry_run=False, include_all=True, yes=yes)
        mode = "exceptional-push"
    else:
        print("GUARDED_R57_MODE: normal chronological db push")
        runner.db_push(dry_run=True, include_all=False, yes=yes)
        if dry_run_only:
            return "normal-dry-run"
        runner.db_push(dry_run=False, include_all=False, yes=yes)
        mode = "normal-push"

    post_state = runner.migration_list()
    if post_state.historical_gaps:
        raise GuardError(
            "Historical migration gap remains after push: "
            + ", ".join(post_state.historical_gaps)
        )
    runner.db_push(dry_run=True, include_all=False, yes=True)
    print("GUARDED_R57_POSTCHECK: normal chronological history is consistent")
    return mode


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply Supabase migrations with the bounded R57 history guard."
    )
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--linked", action="store_true")
    target.add_argument("--db-url")
    parser.add_argument("--dry-run-only", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--workdir", type=Path, default=Path.cwd())
    parser.add_argument("--supabase-bin")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.workdir.resolve()
    migrations_dir = root / "supabase" / "migrations"
    if not migrations_dir.is_dir():
        raise GuardError(f"Migration directory not found: {migrations_dir}")
    if args.linked:
        assert_expected_linked_project(root)
    target_args = ["--linked"] if args.linked else ["--db-url", args.db_url]
    executable = find_supabase_executable(args.supabase_bin, root)
    runner = SupabaseRunner(executable, target_args, root)
    mode = execute_guarded_push(
        runner,
        migrations_dir,
        dry_run_only=args.dry_run_only,
        yes=args.yes,
    )
    print(f"GUARDED_R57_RESULT: {mode}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GuardError as error:
        print(f"GUARDED_R57_ABORT: {error}", file=sys.stderr)
        raise SystemExit(1)
