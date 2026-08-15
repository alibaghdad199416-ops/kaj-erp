#!/usr/bin/env python3
"""Run the current project verification gates without historical release noise."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATES = (
    "verify_supabase_only.py",
    "verify_postgres_contracts.py",
    "verify_postgres_type_boundaries.py",
    "verify_modular_runtime_architecture.py",
    "verify_static_dart_sanity.py",
    "verify_localization.py",
    "verify_v72_complete_linked_operations.py",
    "verify_v721_recycle_purge_lint_fix.py",
    "verify_v73_reversible_workflows.py",
    "verify_v731_preserved_payment_reallocation.py",
    "verify_v732_operational_state_report_links.py",
    "verify_v733_premium_exports_nomenclature.py",
    "verify_v734_complete_export_audit.py",
    "verify_v734_analyzer_repairs.py",
    "verify_v735_workflow_performance_ui.py",
    "verify_v736_invoice_owned_accounting_ui.py",
    "verify_v737_complete_repairs.py",
    "verify_v738_full_requirements.py",
    "verify_v741_complete_requirements.py",
    "verify_v742_final_audit.py",
    "verify_r78_complete_requirements.py",
    "verify_r79_media_export_stabilization.py",
    "verify_r84_user_media_scope_ui_exports.py",
)


def main() -> int:
    for script_name in GATES:
        script = ROOT / "tool" / script_name
        print(f"\n==> {script_name}", flush=True)
        completed = subprocess.run(
            [sys.executable, "-B", str(script)],
            cwd=ROOT,
            check=False,
        )
        if completed.returncode != 0:
            print(f"FAILED: {script_name}", file=sys.stderr)
            return completed.returncode
    print("\nPASS current Quality Line ERP verification")
    print("NOTE delivery-package cleanliness is checked separately with: npm run verify:package")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
