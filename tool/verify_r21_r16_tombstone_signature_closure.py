#!/usr/bin/env python3
"""R21: close the R16 tombstone function-call signature mismatch.

Production proved that erp_universal_recycle_bin.deleted_by/restored_by are UUID
columns while erp_r16_sync_tombstone intentionally accepts actor identities as
text (to also support audit/external actor IDs). PostgreSQL function resolution
does not implicitly choose the text signature from UUID arguments in a SELECT
call. R21 requires explicit casts in the still-pending R16 seed migration.
"""
from __future__ import annotations

from verification_text import normalized_text_sha256
import json
import re
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")

for relative, digest in {
    "dart_defines.json": "4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need(normalized_text_sha256(ROOT / relative) == digest,
         f"local runtime/hosting baseline changed: {relative}")

r16 = read("supabase/migrations/20260808024500_r16_persistent_canonical_state.sql")
recycle = read("supabase/migrations/20260801070000_universal_recycle_bin_and_document_polish.sql")

# Source schema really is UUID for recycle-bin actor columns.
need(re.search(r"\bdeleted_by\s+uuid\b", recycle, re.I) is not None,
     "recycle-bin deleted_by is no longer verified as UUID")
need(re.search(r"\brestored_by\s+uuid\b", recycle, re.I) is not None,
     "recycle-bin restored_by is no longer verified as UUID")

# Canonical tombstones deliberately store actor identity as text so audit/external
# identities and Supabase UUIDs share one durable representation.
need("p_deleted_at timestamptz,p_deleted_by text,p_deletion_mode text" in r16,
     "R16 tombstone deleted_by contract is not text")
need("p_restored_at timestamptz,p_restored_by text,p_metadata jsonb" in r16,
     "R16 tombstone restored_by contract is not text")

seed_match = re.search(
    r"-- Seed all currently visible recycle-bin deletions\.(.*?)from public\.erp_universal_recycle_bin u",
    r16,
    re.S | re.I,
)
need(seed_match is not None, "R16 recycle-bin seed block missing")
seed = seed_match.group(1) if seed_match else ""
need("u.deleted_by::text" in seed, "R16 seed must cast recycle deleted_by UUID to text")
need("u.restored_by::text" in seed, "R16 seed must cast recycle restored_by UUID to text")
need("u.deleted_at,u.deleted_by,u.deletion_mode" not in seed,
     "buggy uncast deleted_by function call returned")
need("u.restored_at,u.restored_by," not in seed,
     "buggy uncast restored_by function call returned")

# Keep grants/revokes aligned to the actual text signature.
sig = "erp_r16_sync_tombstone(uuid,text,text,timestamptz,text,text,uuid,timestamptz,timestamptz,text,jsonb)"
need(r16.count(sig) >= 2, "R16 privileges are not aligned to the text tombstone signature")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r21") == "python -B tool/verify_r21_r16_tombstone_signature_closure.py",
     "verify:r21 command missing")
need("npm run verify:r21" in scripts.get("verify:workspace", ""),
     "workspace verification missing R21")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 21 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production must point at R21 or an existing verified later orchestrator")

production = read("tool/deploy_r21_production.ps1")
need("20260808024500_r16_persistent_canonical_state.sql" in production,
     "R21 deploy no longer permits the corrected pending R16 migration")
need("Unexpected pending migrations. Refusing production push" in production,
     "R21 lost unexpected migration refusal")
need("Invoke-NativeCaptured" in production,
     "R21 lost R20 native CLI exit-code handling")
need("npm run validate:r21:workspace" in production,
     "R21 deploy does not validate/build R21 workspace first")

# R16 is still the same migration version because production never completed it.
# Adding a compensating R21 DB migration would be wrong: R16 is pending and must
# first become internally valid.
migrations = {p.name for p in (ROOT / "supabase/migrations").glob("*.sql")}
need(not any(name.startswith("20260808") and "r21" in name.lower() for name in migrations),
     "R21 must fix the still-pending R16 migration instead of adding a later DB patch")

if errors:
    print("FAILED R21 R16 tombstone-signature closure")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R21 R16 tombstone-signature closure")
print("  - recycle-bin UUID actor columns are explicitly cast to the canonical text actor contract")
print("  - every R16 seed call resolves to the existing erp_r16_sync_tombstone text signature")
print("  - the corrected R16 migration remains the only pending canonical-state database step after R15")
print("  - R20 native CLI exit-code handling and unexpected-migration refusal remain mandatory")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
