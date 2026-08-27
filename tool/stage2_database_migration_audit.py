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


def strip_sql_non_code(text: str) -> str:
    """Remove SQL comments and string literals while preserving SQL code."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"(?m)--[^\n]*", " ", text)
    # Remove ordinary PostgreSQL string literals, including escaped quotes.
    text = re.sub(r"'(?:''|[^'])*'", "''", text)
    return text


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
        errors.append(
            f"migration ordering is not strictly increasing: {previous_name} -> {migration.name}"
        )
    previous_name = migration.name

    text = migration.read_text(encoding="utf-8", errors="replace")
    executable = strip_sql_non_code(text)
    lower = executable.lower()

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

    # Only treat explicit unfinished-code markers as errors. The generic word
    # `placeholder` is intentionally excluded: it is commonly used in valid
    # application text, generated labels, or documentation embedded in SQL.
    unfinished = (
        r"(?i)\b(?:todo|fixme|not\s+implemented)\b"
        r"|\bplaceholder\s*(?::=|:=|=)"
    )
    if re.search(unfinished, executable):
        errors.append(f"placeholder marker in executable migration SQL: {migration.name}")

if errors:
    print("FAILED Stage 2 migration static safety audit")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(f"PASS Stage 2 migration static safety audit — {len(files)} migrations checked")
