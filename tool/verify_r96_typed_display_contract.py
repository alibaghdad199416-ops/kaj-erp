#!/usr/bin/env python3
"""Verify the R96 canonical typed display contract."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST = "test/r96_typed_display_formatter_test.dart"


def main() -> int:
    formatter = ROOT / "lib/core/utils/erp_display_formatter.dart"
    source = formatter.read_text(encoding="utf-8-sig")
    required = (
        "formatMoney(",
        "formatQuantity(",
        "formatRate(",
        "formatPercentage(",
        "formatInteger(",
        "formatReference(",
        "formatYear(",
        "formatDate(",
        "formatDateTime(",
    )
    missing = [needle for needle in required if needle not in source]
    if missing:
        print(f"FAILED: typed formatter missing {', '.join(missing)}", file=sys.stderr)
        return 1

    flutter = shutil.which("flutter")
    if flutter is None:
        print("FAILED: Flutter executable is not available on PATH.", file=sys.stderr)
        return 127

    print(f"==> {TEST}", flush=True)
    completed = subprocess.run(
        [flutter, "test", TEST],
        cwd=ROOT,
        check=False,
    )
    if completed.returncode != 0:
        return completed.returncode

    print("PASS R96 typed display contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
