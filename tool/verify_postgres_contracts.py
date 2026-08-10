#!/usr/bin/env python3
"""Offline CREATE OR REPLACE compatibility check for ordered SQL migrations."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"


def split_top(value: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    quote: str | None = None
    i = 0
    while i < len(value):
        char = value[i]
        if quote:
            if char == quote:
                if i + 1 < len(value) and value[i + 1] == quote:
                    i += 2
                    continue
                quote = None
        else:
            if char in "'\"":
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth = max(0, depth - 1)
            elif char == "," and depth == 0:
                parts.append(value[start:i].strip())
                start = i + 1
        i += 1
    if value[start:].strip():
        parts.append(value[start:].strip())
    return parts


def canonical(value: str) -> str:
    value = re.sub(r"\s+", " ", value.strip().lower())
    return re.sub(r"\s*([(),])\s*", r"\1", value)


def normalize_argument(value: str) -> tuple[str, str, str]:
    value = re.sub(r"\s+", " ", value.strip())
    value = re.split(r"\s+default\s+|\s*=\s*", value, flags=re.I)[0].strip()
    tokens = value.split()
    mode = "in"
    if tokens and tokens[0].lower() in {"in", "out", "inout", "variadic"}:
        mode = tokens.pop(0).lower()
    name = ""
    if len(tokens) >= 2 and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", tokens[0]):
        name = tokens.pop(0).lower()
    return mode, name, canonical(" ".join(tokens))


create_re = re.compile(
    r"create\s+(?:or\s+replace\s+)?function\s+"
    r"((?:\"?[A-Za-z_][A-Za-z0-9_]*\"?\.)?\"?[A-Za-z_][A-Za-z0-9_]*\"?)\s*\(",
    re.I,
)
drop_re = re.compile(
    r"drop\s+function\s+(?:if\s+exists\s+)?"
    r"((?:\"?[A-Za-z_][A-Za-z0-9_]*\"?\.)?\"?[A-Za-z_][A-Za-z0-9_]*\"?)\s*\((.*?)\)",
    re.I | re.S,
)

state: dict[tuple[str, tuple[tuple[str, str], ...]], tuple[str, tuple[str, ...], str]] = {}
errors: list[str] = []
definition_count = 0

for migration in sorted(MIGRATIONS.glob("*.sql")):
    text = migration.read_text(encoding="utf-8", errors="replace")
    events = [(match.start(), "create", match) for match in create_re.finditer(text)]
    events += [(match.start(), "drop", match) for match in drop_re.finditer(text)]

    for _, event_type, match in sorted(events, key=lambda item: item[0]):
        function_name = match.group(1).replace('"', "").lower()
        if "." not in function_name:
            function_name = "public." + function_name

        if event_type == "drop":
            signature = tuple(
                (mode, arg_type)
                for mode, _, arg_type in map(normalize_argument, split_top(match.group(2)))
                if mode != "out"
            )
            state.pop((function_name, signature), None)
            continue

        position = match.end()
        depth = 1
        quote: str | None = None
        dollar_tag: str | None = None
        index = position
        while index < len(text) and depth:
            if dollar_tag:
                if text.startswith(dollar_tag, index):
                    index += len(dollar_tag)
                    dollar_tag = None
                else:
                    index += 1
                continue
            char = text[index]
            if quote:
                if char == quote:
                    if index + 1 < len(text) and text[index + 1] == quote:
                        index += 2
                        continue
                    quote = None
                index += 1
                continue
            if char in "'\"":
                quote = char
                index += 1
                continue
            dollar_match = re.match(r"\$[A-Za-z0-9_]*\$", text[index:])
            if dollar_match:
                dollar_tag = dollar_match.group(0)
                index += len(dollar_tag)
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            index += 1

        arguments = [normalize_argument(item) for item in split_top(text[position : index - 1])]
        signature = tuple(
            (mode, arg_type) for mode, _, arg_type in arguments if mode != "out"
        )
        argument_names = tuple(
            name for mode, name, _ in arguments if mode in {"in", "inout", "variadic"}
        )
        tail = text[index : index + 1000]
        returns_match = re.search(
            r"\breturns\s+(.+?)(?=\s+language\b|\s+immutable\b|\s+stable\b|"
            r"\s+volatile\b|\s+security\b|\s+set\b|\s+as\s+\$)",
            tail,
            re.I | re.S,
        )
        return_type = canonical(returns_match.group(1)) if returns_match else "<unknown>"
        key = (function_name, signature)
        definition_count += 1

        previous = state.get(key)
        if previous:
            previous_return, previous_names, previous_file = previous
            if previous_return != return_type:
                errors.append(
                    f"return type changed for {function_name}{signature}: "
                    f"{previous_return} -> {return_type} ({previous_file} -> {migration.name})"
                )
            if previous_names and argument_names and previous_names != argument_names:
                errors.append(
                    f"input argument names changed for {function_name}{signature}: "
                    f"{previous_names} -> {argument_names} ({previous_file} -> {migration.name})"
                )
        state[key] = (return_type, argument_names, migration.name)

if errors:
    print("FAILED PostgreSQL CREATE OR REPLACE compatibility")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print(
    "PASS PostgreSQL CREATE OR REPLACE compatibility — "
    f"{definition_count} definitions checked, {len(state)} active signatures"
)
