#!/usr/bin/env python3
"""Check that visible Flutter strings follow the current localization path."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "lib"
errors: list[str] = []

raw_text = re.compile(r'''(?<![\w.])Text\s*\(\s*['"]''')
raw_property = re.compile(
    r'''(labelText|hintText|helperText|errorText|tooltip|semanticLabel|barrierLabel)\s*:\s*['"]'''
)
raw_validator = re.compile(r'''validator\s*:.*\?\s*['"][^'"]+['"]\s*:\s*null''')

for path in sorted(LIB.rglob("*.dart")):
    relative = path.relative_to(ROOT).as_posix()
    source = path.read_text(encoding="utf-8")
    if relative != "lib/core/localization/app_localizations.dart" and raw_text.search(source):
        errors.append(f"raw Text literal: {relative}")
    if raw_property.search(source):
        errors.append(f"raw visible form property: {relative}")
    if raw_validator.search(source):
        errors.append(f"raw validator message: {relative}")

localization = (LIB / "core/localization/app_localizations.dart").read_text(
    encoding="utf-8"
)
localization_catalog_source = "\n".join(
    path.read_text(encoding="utf-8")
    for path in sorted((LIB / "core/localization").rglob("*.dart"))
)

# AppText/AppTranslation can translate legacy literals at runtime, but a fixed
# Arabic phrase still needs an exact English catalog entry. Otherwise English
# mode can leak Arabic or depend on fragile partial-word substitutions.
arabic_literal_patterns = (
    re.compile(r"AppText\(\s*'([^']*[\u0600-\u06ff][^']*)'"),
    re.compile(r'AppText\(\s*"([^"]*[\u0600-\u06ff][^"]*)"'),
    re.compile(r"AppTranslation\.translate\(\s*'([^']*[\u0600-\u06ff][^']*)'"),
    re.compile(r'AppTranslation\.translate\(\s*"([^"]*[\u0600-\u06ff][^"]*)"'),
)
fixed_arabic_literals: set[str] = set()
for path in sorted(LIB.rglob("*.dart")):
    source = path.read_text(encoding="utf-8")
    for pattern in arabic_literal_patterns:
        for value in pattern.findall(source):
            if value.find("$") >= 0 or value.find("\n") >= 0 or value.find("\\") >= 0:
                continue
            fixed_arabic_literals.add(value)
for value in sorted(fixed_arabic_literals):
    single = "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"
    double = '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if single not in localization_catalog_source and double not in localization_catalog_source:
        errors.append(f"missing exact English catalog entry for Arabic UI phrase: {value}")
for token in (
    "static String translateForLocale(",
    "Localizations.maybeLocaleOf(context)?.languageCode",
    "AppTranslation.translateForLocale(data, activeLocale)",
    "static String localeCode = 'en';",
    "<Locale>[Locale('en'), Locale('ar')]",
):
    if token not in localization:
        errors.append(f"localization runtime is missing {token!r}")

if errors:
    print("FAILED localization verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS localization verification")
print("  - English remains the primary locale and Arabic remains supported")
print("  - AppText follows the active widget-tree locale")
print("  - visible form properties and validators use localization")
print("  - fixed Arabic AppText/AppTranslation phrases have exact English catalog entries")
