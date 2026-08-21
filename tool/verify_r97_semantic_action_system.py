#!/usr/bin/env python3
"""Verify the R97 semantic action/design-system contract."""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEST = "test/r97_semantic_action_system_test.dart"


def main() -> int:
    universal = (ROOT / "lib/design_system/kaj_universal_components.dart").read_text(
        encoding="utf-8-sig"
    )
    permission_actions = (
        ROOT / "lib/features/settings/access/widgets/permission_action.dart"
    ).read_text(encoding="utf-8-sig")

    required_universal = (
        "enum KajActionTone",
        "class KajActionButton",
        "KajActionTone.primary",
        "KajActionTone.secondary",
        "KajActionTone.approve",
        "KajActionTone.danger",
        "KajActionTone.neutral",
        "KajComponentTokens.controlHeight",
        "KajComponentTokens.compactControlHeight",
    )
    missing = [needle for needle in required_universal if needle not in universal]
    if missing:
        print(f"FAILED: semantic action contract missing {', '.join(missing)}", file=sys.stderr)
        return 1

    if "class PermissionActionButton" not in permission_actions:
        print("FAILED: Settings actions are not bridged to semantic action system", file=sys.stderr)
        return 1
    if "KajActionButton(" not in permission_actions:
        print("FAILED: PermissionActionButton does not consume KajActionButton", file=sys.stderr)
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

    print("PASS R97 semantic action system")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
