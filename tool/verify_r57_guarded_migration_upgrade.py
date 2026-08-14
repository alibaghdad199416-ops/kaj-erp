#!/usr/bin/env python3
"""Focused regression tests for the bounded R57 migration-history guard."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

from guarded_supabase_db_push import (
    COMPAT_VERSION,
    GuardError,
    classify_history,
    execute_guarded_push,
    validate_exceptional_dry_run,
)


ROOT = Path(__file__).resolve().parents[1]
COMPAT_FILE = "20260809124735_r57_pre_r37_cloud_command_dependency.sql"
LATEST = "20260811191823"
FUTURE = "20260813100000"


def rows(local: list[str], remote: list[str]) -> list[dict[str, str]]:
    versions = sorted(set(local) | set(remote))
    return [
        {
            "local": version if version in local else "",
            "remote": version if version in remote else "",
        }
        for version in versions
    ]


class FakeRunner:
    def __init__(self, states, previews):
        self.states = list(states)
        self.previews = list(previews)
        self.calls: list[tuple[bool, bool, bool]] = []

    def migration_list(self):
        if not self.states:
            raise AssertionError("unexpected migration_list call")
        return self.states.pop(0)

    def db_push(self, *, dry_run: bool, include_all: bool, yes: bool):
        self.calls.append((dry_run, include_all, yes))
        output = self.previews.pop(0) if self.previews else "Local database is up to date."
        return subprocess.CompletedProcess([], 0, output, "")


class GuardDecisionTests(unittest.TestCase):
    def test_fresh_or_no_history_uses_normal_push(self):
        state = classify_history(rows([COMPAT_VERSION, LATEST], []))
        self.assertFalse(state.use_include_all)

    def test_exact_r57_historical_gap_is_permitted(self):
        state = classify_history(
            rows([COMPAT_VERSION, LATEST], [LATEST])
        )
        self.assertTrue(state.use_include_all)
        self.assertEqual(state.historical_gaps, (COMPAT_VERSION,))

    def test_r57_plus_unexpected_historical_gap_aborts(self):
        with self.assertRaisesRegex(GuardError, "Unexpected out-of-order"):
            classify_history(
                rows(
                    ["20260809120000", COMPAT_VERSION, LATEST],
                    [LATEST],
                )
            )

    def test_different_single_historical_gap_aborts(self):
        with self.assertRaisesRegex(GuardError, "Unexpected out-of-order"):
            classify_history(
                rows(["20260809120000", LATEST], [LATEST])
            )

    def test_already_reconciled_history_uses_normal_push(self):
        state = classify_history(
            rows([COMPAT_VERSION, LATEST], [COMPAT_VERSION, LATEST])
        )
        self.assertFalse(state.use_include_all)

    def test_later_migration_after_reconciliation_remains_normal(self):
        state = classify_history(
            rows(
                [COMPAT_VERSION, LATEST, FUTURE],
                [COMPAT_VERSION, LATEST],
            )
        )
        self.assertFalse(state.use_include_all)
        self.assertEqual(state.missing_local_versions, (FUTURE,))

    def test_exceptional_dry_run_rejects_unexpected_historical_file(self):
        state = classify_history(
            rows([COMPAT_VERSION, LATEST], [LATEST])
        )
        with self.assertRaisesRegex(GuardError, "unexpected="):
            validate_exceptional_dry_run(
                state,
                "Would push:\n"
                f" • {COMPAT_FILE}\n"
                " • 20260809120000_unexpected.sql",
                {COMPAT_VERSION: COMPAT_FILE, LATEST: f"{LATEST}_latest.sql"},
            )

    def test_exceptional_execution_returns_to_normal_postcheck(self):
        before = classify_history(
            rows([COMPAT_VERSION, LATEST], [LATEST])
        )
        after = classify_history(
            rows([COMPAT_VERSION, LATEST], [COMPAT_VERSION, LATEST])
        )
        runner = FakeRunner(
            [before, before, after],
            [f"Would push:\n • {COMPAT_FILE}", "Applying migration", "up to date"],
        )
        mode = execute_guarded_push(
            runner,
            ROOT / "supabase" / "migrations",
            dry_run_only=False,
            yes=True,
        )
        self.assertEqual(mode, "exceptional-push")
        self.assertEqual(
            runner.calls,
            [(True, True, True), (False, True, True), (True, False, True)],
        )

    def test_compatibility_migration_is_conditional_and_fail_closed(self):
        sql = (ROOT / "supabase" / "migrations" / COMPAT_FILE).read_text(
            encoding="utf-8"
        ).lower()
        self.assertIn(
            "to_regprocedure('public.erp_r35_cloud_command(text,text,jsonb)') is null",
            sql,
        )
        self.assertIn("security invoker", sql)
        self.assertIn("fresh_install_r35_compatibility_must_not_execute", sql)
        self.assertIn("revoke all on function", sql)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(GuardDecisionTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("R57 guarded migration upgrade verification PASS")
