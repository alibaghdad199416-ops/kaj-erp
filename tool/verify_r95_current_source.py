#!/usr/bin/env python3
"""Run the canonical R95 source and regression verification gates."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON_GATES = (
    "verify_r95_granular_action_backend_guard.py",
    "verify_r95_1_granular_commercial_stage_backend_guard.py",
    "verify_r95_2_granular_invoice_approval_backend_guard.py",
    "verify_r95_3_granular_payment_backend_guard.py",
    "verify_r95_maintenance_draft_reopen_guard.py",
)
FLUTTER_TESTS = (
    "test/r95_enterprise_permission_contract_test.dart",
    "test/r95_unified_query_contract_test.dart",
)


def _run_python_gate(script_name: str) -> int:
    script = ROOT / "tool" / script_name
    print(f"\n==> {script_name}", flush=True)
    completed = subprocess.run(
        [sys.executable, "-B", str(script)],
        cwd=ROOT,
        check=False,
    )
    return completed.returncode


def _run_flutter_tests() -> int:
    flutter = shutil.which("flutter")
    if flutter is None:
        print("FAILED: Flutter executable is not available on PATH.", file=sys.stderr)
        return 127
    print("\n==> R95 Flutter regression tests", flush=True)
    completed = subprocess.run(
        [flutter, "test", *FLUTTER_TESTS],
        cwd=ROOT,
        check=False,
    )
    return completed.returncode


def main() -> int:
    for script_name in PYTHON_GATES:
        returncode = _run_python_gate(script_name)
        if returncode != 0:
            print(f"FAILED: {script_name}", file=sys.stderr)
            return returncode

    returncode = _run_flutter_tests()
    if returncode != 0:
        print("FAILED: R95 Flutter regression tests", file=sys.stderr)
        return returncode

    print("\nPASS R95 current source verification")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
