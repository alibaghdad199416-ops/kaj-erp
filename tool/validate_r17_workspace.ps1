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
Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'dart format' { npm run format }
Invoke-Step 'format:check' { npm run format:check }
Invoke-Step 'verify:workspace (generated dirs allowed)' { npm run verify:workspace }
Invoke-Step 'flutter analyze' { npm run analyze }
Invoke-Step 'flutter test' { npm run test }
Invoke-Step 'build:web' { npm run build:web }

Write-Host "`nPASS R17 installed-workspace release validation" -ForegroundColor Green
