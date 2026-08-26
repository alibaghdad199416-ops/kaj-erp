#!/usr/bin/env python3
"""Stage 2 static safety audit for ordered Supabase migrations."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
errors: list[str] = []
files = sorted(MIGRATIONS.glob("*.sql"))

if not files:
    errors.append("no SQL migrations found")

seen_stamps: set[str] = set()
previous_name = ""
filename_re = re.compile(r"^(\d{14})_[A-Za-z0-9][A-Za-z0-9_-]*\.sql$")

for migration in files:
    match = filename_re.fullmatch(migration.name)
    if not match:
        errors.append(f"invalid migration filename: {migration.name}")
        continue
    stamp = match.group(1)
    if stamp in seen_stamps:
        errors.append(f"duplicate migration timestamp: {stamp}")
    seen_stamps.add(stamp)
    if previous_name and migration.name <= previous_name:
        errors.append(f"migration ordering is not strictly increasing: {previous_name} -> {migration.name}")
    previous_name = migration.name

    text = migration.read_text(encoding="utf-8", errors="replace")
    lower = text.lower()

    forbidden = {
        "supabase db reset": r"\bsupabase\s+db\s+reset\b",
        "supabase db push": r"\bsupabase\s+db\s+push\b",
        "git reset --hard": r"\bgit\s+reset\s+--hard\b",
        "drop database": r"\bdrop\s+database\b",
    }
    for label, pattern in forbidden.items():
        if re.search(pattern, lower):
            errors.append(f"forbidden migration command/text '{label}' in {migration.name}")

    if re.search(r"(?m)^\s*after_rollback_marker\s*:=", lower):
        errors.append(f"stray procedural assignment outside a function/block: {migration.name}")

if errors:
    print("FAILED Stage 2 migration static safety audit")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(f"PASS Stage 2 migration static safety audit — {len(files)} migrations checked")
