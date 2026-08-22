#!/usr/bin/env python3
"""Authoritative non-production quality-gate contract for Quality Line ERP.

Historical release verifiers remain useful evidence, but they must not each invent
what `verify:all`, `check`, or GitHub Actions mean. This module owns the current
installed-workspace superset and CI ordering so R10/R13/R93/package checks cannot
drift into mutually contradictory requirements again.

R94 is intentionally wired through `verify_project.py`, the current-project gate
already executed by `verify:workspace`. The explicit npm phase aliases remain the
accepted R88-R93 historical chain instead of adding another competing topology.
"""
from __future__ import annotations

from collections.abc import Mapping

CURRENT_PHASE_VERIFY_SCRIPTS: tuple[str, ...] = (
    "verify:r88",
    "verify:r89",
    "verify:r90",
    "verify:r91",
    "verify:r92",
    "verify:r93",
)

CANONICAL_CHECK_COMMAND = (
    "npm run verify:all && npm run format:check && npm run analyze && npm run test"
)

CANONICAL_DELIVERY_COMMAND = (
    "npm run verify:package && npm run verify:deployment-target"
)

CI_ORDERED_STEPS: tuple[str, ...] = (
    "run: npm run verify:delivery",
    "run: npm ci",
    "run: flutter pub get",
    "run: npm run format:check",
    "run: npm run verify:all",
    "run: npm run analyze",
    "run: npm run test",
    "run: npm run build:web",
)


def verify_all_errors(scripts: Mapping[str, object]) -> list[str]:
    """Return structural errors in the authoritative installed-workspace chain."""
    errors: list[str] = []
    command = str(scripts.get("verify:all", ""))
    if "npm run verify:workspace" not in command:
        errors.append("verify:all must include verify:workspace")
    for script_name in CURRENT_PHASE_VERIFY_SCRIPTS:
        if f"npm run {script_name}" not in command:
            errors.append(f"verify:all must include {script_name}")
    return errors


def check_errors(scripts: Mapping[str, object]) -> list[str]:
    """Return errors in commands that represent the current developer check."""
    errors = verify_all_errors(scripts)
    if str(scripts.get("check", "")) != CANONICAL_CHECK_COMMAND:
        errors.append(
            "check must run verify:all, committed formatting, analyzer, and tests"
        )
    return errors


def workflow_errors(workflow: str) -> list[str]:
    """Validate delivery-first, non-mutating CI stage ordering."""
    errors: list[str] = []
    positions = [workflow.find(marker) for marker in CI_ORDERED_STEPS]
    if any(position < 0 for position in positions):
        missing = [
            marker
            for marker, position in zip(CI_ORDERED_STEPS, positions)
            if position < 0
        ]
        errors.append("CI is missing canonical stages: " + ", ".join(missing))
    elif positions != sorted(positions):
        errors.append(
            "CI must run delivery -> install -> format check -> verify:all -> "
            "analyze -> test -> build"
        )

    workflow_lines = {line.strip() for line in workflow.splitlines()}
    if "run: npm run format" in workflow_lines:
        errors.append("CI must not auto-format committed source")
    return errors
