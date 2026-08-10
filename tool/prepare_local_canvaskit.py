#!/usr/bin/env python3
"""Ensure CanvasKit is available locally under build/web/canvaskit.

The preferred path is to build with Flutter's --no-web-resources-cdn flag,
which bundles the web engine resources. This helper validates that output and
only falls back to copying from the installed Flutter SDK cache when needed.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "build" / "web" / "canvaskit"
REQUIRED = ("canvaskit.js", "canvaskit.wasm")


def valid_canvaskit(directory: Path) -> bool:
    js = directory / "canvaskit.js"
    wasm = directory / "canvaskit.wasm"
    return (
        js.is_file()
        and wasm.is_file()
        and js.stat().st_size > 10_000
        and wasm.stat().st_size > 100_000
    )


def flutter_executable() -> Path | None:
    explicit_root = os.environ.get("FLUTTER_ROOT")
    if explicit_root:
        root = Path(explicit_root)
        for name in ("flutter.bat", "flutter.cmd", "flutter"):
            candidate = root / "bin" / name
            if candidate.is_file():
                return candidate

    for name in ("flutter", "flutter.bat", "flutter.cmd"):
        value = shutil.which(name)
        if value:
            return Path(value)

    if os.name == "nt":
        try:
            result = subprocess.run(
                ["where.exe", "flutter"],
                check=True,
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            for line in result.stdout.splitlines():
                candidate = Path(line.strip())
                if candidate.is_file():
                    return candidate
        except (OSError, subprocess.CalledProcessError):
            pass
    return None


def flutter_root() -> Path:
    executable = flutter_executable()
    if executable is None:
        raise FileNotFoundError(
            "Flutter executable was not found. Build with `flutter build web "
            "--release --no-web-resources-cdn` first.",
        )

    command: list[str]
    if os.name == "nt" and executable.suffix.lower() in {".bat", ".cmd"}:
        command = ["cmd.exe", "/d", "/s", "/c", str(executable), "--version", "--machine"]
    else:
        command = [str(executable), "--version", "--machine"]

    process = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    data = json.loads(process.stdout)
    value = data.get("flutterRoot")
    if value:
        return Path(value)

    # flutter[.bat] is normally <root>/bin/flutter[.bat].
    return executable.resolve().parent.parent


def locate_source(root: Path) -> Path:
    cache = root / "bin" / "cache"
    candidates = [
        cache / "flutter_web_sdk" / "canvaskit",
        cache / "artifacts" / "engine" / "common" / "flutter_web_sdk" / "canvaskit",
    ]
    for candidate in candidates:
        if valid_canvaskit(candidate):
            return candidate

    if cache.is_dir():
        for js in cache.rglob("canvaskit.js"):
            candidate = js.parent
            if valid_canvaskit(candidate):
                return candidate

    raise FileNotFoundError(
        "CanvasKit was not found in the Flutter SDK cache. Run "
        "`flutter precache --web`, then rebuild with --no-web-resources-cdn.",
    )



def copy_host_metadata(build: Path) -> None:
    # Copy cache-control metadata that Flutter may omit from web output.
    for name in ("_headers", ".htaccess"):
        source = ROOT / "web" / name
        if source.is_file():
            shutil.copy2(source, build / name)

def main() -> int:
    build = ROOT / "build" / "web"
    if not (build / "flutter_bootstrap.js").is_file():
        print("FAIL local CanvasKit preparation")
        print(" - build/web/flutter_bootstrap.js is missing; run flutter build web first")
        return 1

    copy_host_metadata(build)

    # Preferred path: Flutter already bundled the resources via
    # --no-web-resources-cdn. Do not invoke Flutter or copy anything.
    if valid_canvaskit(DESTINATION):
        print("PASS local CanvasKit preparation")
        print(" - Flutter build already bundled CanvasKit under build/web/canvaskit")
        return 0

    try:
        source = locate_source(flutter_root())
        if DESTINATION.exists():
            shutil.rmtree(DESTINATION)
        shutil.copytree(source, DESTINATION)
    except (OSError, RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print("FAIL local CanvasKit preparation")
        print(f" - {exc}")
        print(" - preferred command: flutter build web --release --no-web-resources-cdn")
        return 1

    if not valid_canvaskit(DESTINATION):
        print("FAIL local CanvasKit preparation")
        print(" - copied CanvasKit files are missing, empty, or unexpectedly small")
        return 1

    print("PASS local CanvasKit preparation")
    print(f" - copied self-hosted CanvasKit from {source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
