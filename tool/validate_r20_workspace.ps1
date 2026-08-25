$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

# This validator is intentionally safe for an already-installed/built workspace.
# Generated paths such as .dart_tool, node_modules, build and
# .flutter-plugins-dependencies are expected here and are NOT delivery errors.
Invoke-Step 'native CLI stderr/exit-code self-test' { powershell -NoProfile -ExecutionPolicy Bypass -File tool/test_r20_native_cli_runner.ps1 }
Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'dart format' { npm run format }
Invoke-Step 'format:check' { npm run format:check }
Invoke-Step 'verify:workspace (generated dirs allowed)' { npm run verify:workspace }
Invoke-Step 'flutter analyze' { npm run analyze }
Invoke-Step 'flutter test' { npm run test }
Invoke-Step 'build:web' { npm run build:web }

Write-Host "`nPASS R20 installed-workspace release validation" -ForegroundColor Green
