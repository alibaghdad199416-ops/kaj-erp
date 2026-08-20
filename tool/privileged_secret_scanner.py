#!/usr/bin/env python3
"""Semantic privileged-secret detection for source/package verification.

The scanner deliberately distinguishes PostgreSQL/Supabase role *names* and
assertion identifiers from actual credential values. A token such as
`service_role_execute_missing` is not a secret; a service-role JWT, modern
`sb_secret_...` key, password-bearing PostgreSQL DSN, or long literal assigned
as a service-role key is.
"""
from __future__ import annotations

import base64
import json
import re
from dataclasses import dataclass
from pathlib import Path


_MODERN_SUPABASE_SECRET_RE = re.compile(
    r"(?<![A-Za-z0-9_])sb_secret_[A-Za-z0-9._-]{12,}(?![A-Za-z0-9_])",
    re.IGNORECASE,
)
_PASSWORD_DSN_RE = re.compile(
    "postgres" + r"(?:ql)?://[^\s:@/]+:[^\s@/]+@",
    re.IGNORECASE,
)
_SERVICE_ROLE_QUOTED_ASSIGNMENT_RE = re.compile(
    r"""
    (?<![A-Za-z0-9_])
    (?P<name_quote>[\"']?)
    \$?
    \b(?:SUPABASE[_-]?)?SERVICE[_-]?ROLE(?:[_-]?KEY)?\b
    (?P=name_quote)
    \s*(?:=|:)\s*
    (?P<quote>[\"'])
    (?P<value>[A-Za-z0-9._~+/=-]{20,})
    (?P=quote)
    """,
    re.IGNORECASE | re.VERBOSE,
)
_SERVICE_ROLE_BARE_CONFIG_RE = re.compile(
    r"""
    ^\s*(?:export\s+)?
    (?P<name_quote>[\"']?)
    (?:SUPABASE_SERVICE_ROLE_KEY|SERVICE_ROLE_KEY|supabase-service-role-key|service-role-key)
    (?P=name_quote)
    \s*(?:=|:)\s*
    (?P<value>[A-Za-z0-9._~+/=-]{20,})
    \s*(?:[#;].*)?$
    """,
    re.MULTILINE | re.VERBOSE,
)
_JWT_RE = re.compile(
    r"(?<![A-Za-z0-9_-])"
    r"(?P<jwt>eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,})"
    r"(?![A-Za-z0-9_-])"
)


@dataclass(frozen=True)
class PrivilegedSecretMatch:
    kind: str
    preview: str


def _decode_base64url_json(segment: str) -> dict[str, object] | None:
    padding = "=" * (-len(segment) % 4)
    try:
        raw = base64.urlsafe_b64decode((segment + padding).encode("ascii"))
        payload = json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def _jwt_is_service_role(token: str) -> bool:
    parts = token.split(".")
    if len(parts) != 3:
        return False
    payload = _decode_base64url_json(parts[1])
    if payload is None:
        return False
    return str(payload.get("role", "")).strip().lower() == "service_role"


def find_privileged_secret(text: str) -> PrivilegedSecretMatch | None:
    """Return the first real privileged credential literal, if any."""
    match = _MODERN_SUPABASE_SECRET_RE.search(text)
    if match:
        return PrivilegedSecretMatch("supabase_secret", "sb_secret_…")

    match = _PASSWORD_DSN_RE.search(text)
    if match:
        return PrivilegedSecretMatch(
            "postgres_password_dsn",
            "password-bearing PostgreSQL DSN",
        )

    for pattern in (
        _SERVICE_ROLE_QUOTED_ASSIGNMENT_RE,
        _SERVICE_ROLE_BARE_CONFIG_RE,
    ):
        match = pattern.search(text)
        if match:
            value = match.group("value")
            # Environment/template expressions and function calls are not literal
            # values. Quoted source values and bare config/env values are.
            return PrivilegedSecretMatch(
                "service_role_key_literal",
                value[:6] + "…",
            )

    for match in _JWT_RE.finditer(text):
        token = match.group("jwt")
        if _jwt_is_service_role(token):
            return PrivilegedSecretMatch("service_role_jwt", "eyJ…")

    return None


def contains_privileged_secret(text: str) -> bool:
    return find_privileged_secret(text) is not None


def _fake_service_role_jwt() -> str:
    def encode(value: dict[str, object]) -> str:
        raw = json.dumps(value, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")

    return ".".join(
        (
            encode({"alg": "HS256", "typ": "JWT"}),
            encode({"role": "service_role", "iss": "supabase"}),
            "signature_for_contract_test_only",
        )
    )


def assert_detection_contract() -> None:
    """Fail closed if future edits reintroduce broad false positives or gaps."""
    safe_samples = (
        "has_function_privilege('service_role', v_sig, 'execute')",
        "r94_internal_service_role_execute_missing",
        "service_role is a PostgreSQL role name",
        "$serviceRoleKey = Get-LocalServiceRoleKey",
        "serviceRoleKey = loadServiceRoleKeyFromEnvironment()",
        "SERVICE_ROLE_KEY = os.environ['SUPABASE_SERVICE_ROLE_KEY']",
        "SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}",
    )
    for sample in safe_samples:
        if contains_privileged_secret(sample):
            raise AssertionError(f"safe service-role reference misclassified: {sample}")

    dangerous_samples = (
        "".join(("prefix ", "sb_", "secret_", "abcdefghijkl", "mnopqrstuvwx")),
        "".join(
            (
                "DATABASE_URL=",
                "postgres",
                "ql://",
                "contract-user",
                ":",
                "embedded-",
                "password",
                "@",
                "db.invalid/postgres",
            )
        ),
        "".join(
            (
                "SUPABASE_",
                "SERVICE_",
                "ROLE_KEY=",
                "'",
                "literal_",
                "privileged_",
                "key_material_",
                "123456789",
                "'",
            )
        ),
        "".join(
            (
                "SERVICE_",
                "ROLE_KEY=",
                "bare_",
                "privileged_",
                "key_material_",
                "123456789",
            )
        ),
        _fake_service_role_jwt(),
    )
    for sample in dangerous_samples:
        if not contains_privileged_secret(sample):
            raise AssertionError("privileged credential contract was weakened")

    source_match = find_privileged_secret(Path(__file__).read_text(encoding="utf-8"))
    if source_match:
        raise AssertionError(
            f"scanner source contains a matchable {source_match.kind} sample"
        )


if __name__ == "__main__":
    assert_detection_contract()
    print("Privileged secret scanner contract PASS")
