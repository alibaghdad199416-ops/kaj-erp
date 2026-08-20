from __future__ import annotations

from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE_COMMIT = "967845801cb6d63881f95b38744fdd6e4c27ff6c"
errors: list[str] = []


def need(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def text(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        errors.append(f"missing file: {rel}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        errors.append(
            f"git {' '.join(args)} failed: {result.stderr.strip() or result.stdout.strip()}"
        )
        return ""
    return result.stdout


# 1. Historical migrations are immutable relative to the accepted R92 baseline.
# New forward-only migrations are allowed; any migration that already existed in
# the accepted baseline must remain byte-identical.
need(
    "accepted R92 baseline commit is not available in git history",
    subprocess.run(
        ["git", "cat-file", "-e", f"{BASELINE_COMMIT}^{{commit}}"],
        cwd=ROOT,
        check=False,
        capture_output=True,
    ).returncode
    == 0,
)
baseline_migrations = {
    line.strip()
    for line in git(
        "ls-tree", "-r", "--name-only", BASELINE_COMMIT, "--", "supabase/migrations"
    ).splitlines()
    if line.strip()
}
changed_migrations = {
    line.strip()
    for line in git(
        "diff", "--name-only", f"{BASELINE_COMMIT}..HEAD", "--", "supabase/migrations"
    ).splitlines()
    if line.strip()
}
for rel in sorted(baseline_migrations & changed_migrations):
    errors.append(f"historical migration changed after accepted R92 baseline: {rel}")

# 2. The latest Phase 11 static and PostgreSQL runtime gates must exist.
for rel in [
    "tool/verify_r88_phase11.py",
    "tool/verify_r89_phase11_completion.py",
    "tool/verify_r90_phase11_final_acceptance.py",
    "tool/verify_r91_phase11_material_issue_acceptance.py",
    "tool/verify_r92_comprehensive_module_audit.py",
    "supabase/tests/verify_r89_phase11_runtime.sql",
    "supabase/tests/verify_r90_phase11_runtime.sql",
    "supabase/tests/verify_r91_phase11_runtime.sql",
    "supabase/tests/verify_r92_comprehensive_module_audit_runtime.sql",
    "supabase/tests/verify_r93_restricted_user_runtime.sql",
    "tool/run_r89_r92_local_runtime_tests.py",
]:
    need(f"required final gate missing: {rel}", (ROOT / rel).exists())

# 3. R92 ACL tightening must not revoke an RPC still called anywhere in Flutter,
# including shared core/widgets code outside the seven audited feature trees.
r92 = text("supabase/migrations/20260820133000_r92_comprehensive_module_audit.sql")
rpc_pattern = re.compile(r"\.rpc\(\s*['\"]([^'\"]+)['\"]")
used_rpcs: dict[str, list[str]] = {}
for dart in (ROOT / "lib").rglob("*.dart"):
    src = dart.read_text(encoding="utf-8", errors="replace")
    for rpc in rpc_pattern.findall(src):
        used_rpcs.setdefault(rpc, []).append(str(dart.relative_to(ROOT)))

revoked_rpcs: set[str] = set()
for statement in r92.split(";"):
    if re.search(r"\brevoke\b", statement, re.I) and re.search(
        r"\bauthenticated\b", statement, re.I
    ):
        match = re.search(r"function\s+public\.([A-Za-z0-9_]+)\s*\(", statement, re.I)
        if match:
            revoked_rpcs.add(match.group(1))
for array_match in re.finditer(
    r"foreach\s+v_name\s+in\s+array\s+array\[(.*?)\]\s+loop", r92, re.S | re.I
):
    revoked_rpcs.update(re.findall(r"'([^']+)'", array_match.group(1)))

for conflict in sorted(set(used_rpcs) & revoked_rpcs):
    errors.append(
        "R92 revokes RPC still used by Flutter: "
        + conflict
        + " in "
        + ", ".join(sorted(set(used_rpcs[conflict])))
    )

# 4. The official GitHub gate must validate the committed tree before any
# formatter mutation, run current Phase 11 gates, and exercise local PostgreSQL.
workflow = text(".github/workflows/quality-gates.yml")
for marker in [
    "fetch-depth: 0",
    "npm run format:check",
    "python -B tool/verify_r88_phase11.py",
    "python -B tool/verify_r89_phase11_completion.py",
    "python -B tool/verify_r90_phase11_final_acceptance.py",
    "python -B tool/verify_r91_phase11_material_issue_acceptance.py",
    "python -B tool/verify_r92_comprehensive_module_audit.py",
    "python -B tool/verify_r93_final_closure.py",
    "npx supabase start",
    "python -B tool/run_r89_r92_local_runtime_tests.py",
    "npm run analyze",
    "npm run test",
    "npm run build:web",
]:
    need(f"quality-gates workflow missing final closure marker: {marker}", marker in workflow)
need(
    "quality-gates workflow still mutates Dart formatting before validation",
    "npm run format\n" not in workflow and "npm run format\r\n" not in workflow,
)
for forbidden in [
    "supabase db reset",
    "supabase db push",
    "supabase link",
    "dart_defines.production.json",
]:
    need(f"quality-gates workflow contains forbidden operation: {forbidden}", forbidden not in workflow)

# 5. The local runtime runner must be explicitly local-only and cover every
# available R89-R93 PostgreSQL acceptance script without reset/push/link.
runner = text("tool/run_r89_r92_local_runtime_tests.py")
for marker in [
    "supabase_db_quality_line_erp_local_dev",
    "verify_r89_phase11_runtime.sql",
    "verify_r90_phase11_runtime.sql",
    "verify_r91_phase11_runtime.sql",
    "verify_r92_comprehensive_module_audit_runtime.sql",
    "verify_r93_restricted_user_runtime.sql",
    "ON_ERROR_STOP=1",
]:
    need(f"local runtime runner missing marker: {marker}", marker in runner)
for forbidden in ["db reset", "db push", "supabase link"]:
    need(f"local runtime runner contains forbidden operation: {forbidden}", forbidden not in runner)

if errors:
    print("R93 final closure verification FAILED")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print("R93 final closure verification PASS")
print("  - accepted R92 historical migrations remain immutable")
print("  - R92 revoked RPCs are unused across the complete Flutter lib tree")
print("  - committed formatting is checked before any formatter mutation")
print("  - R88-R92 static gates are wired into official CI")
print("  - R89-R93 PostgreSQL runtime tests are wired to local Supabase only")
print("  - restricted-user runtime proves field masking and delete denial")
print("  - analyze, Flutter tests and web build remain mandatory")
