#!/usr/bin/env python3
"""Formatter-invariant helpers for source verification.

The Dart formatter is allowed to reflow whitespace and comments without changing
program semantics. Historical release gates must therefore never depend on a
physical line layout. These helpers strip whitespace/comments only while in
normal code, preserving quoted string contents exactly.
"""
from __future__ import annotations

import hashlib
from pathlib import Path


def normalized_text_sha256(path: Path) -> str:
    """Hash text bytes while treating Git CRLF and LF worktrees identically."""
    payload = path.read_bytes().replace(b"\r\n", b"\n")
    return hashlib.sha256(payload).hexdigest()


def compact_code(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    state = "code"
    quote = ""
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if state == "code":
            if ch.isspace():
                i += 1
                continue
            if ch == "/" and nxt == "/":
                state = "line_comment"
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if ch in ("'", '"'):
                quote = ch
                state = "string"
                out.append(ch)
                i += 1
                continue
            out.append(ch)
            i += 1
            continue

        if state == "line_comment":
            if ch in "\r\n":
                state = "code"
            i += 1
            continue

        if state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
            else:
                i += 1
            continue

        # Quoted string. Preserve contents, including whitespace and escapes.
        out.append(ch)
        if ch == "\\" and i + 1 < n:
            out.append(text[i + 1])
            i += 2
            continue
        if ch == quote:
            state = "code"
            quote = ""
        i += 1

    return "".join(out)


def contains_code(text: str, snippet: str) -> bool:
    """Return True when snippet occurs modulo formatter whitespace/comments."""
    return compact_code(snippet) in compact_code(text)


def contains_all_code(text: str, snippets: tuple[str, ...] | list[str]) -> bool:
    compact = compact_code(text)
    return all(compact_code(snippet) in compact for snippet in snippets)
