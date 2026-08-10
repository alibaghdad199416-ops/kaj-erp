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

# IMPORTANT: delivery cleanliness is checked BEFORE commands that legitimately
# create node_modules/.dart_tool/build metadata in the working tree.
Invoke-Step 'verify:delivery (pristine package, before dependency generation)' { npm run verify:delivery }

Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'dart format' { npm run format }
Invoke-Step 'format:check' { npm run format:check }

# Workspace gates must NEVER reject generated dependency/cache directories.
Invoke-Step 'verify:workspace (generated dirs allowed)' { npm run verify:workspace }
Invoke-Step 'flutter analyze' { npm run analyze }
Invoke-Step 'flutter test' { npm run test }
Invoke-Step 'build:web' { npm run build:web }

Write-Host "`nPASS R13 Windows release validation" -ForegroundColor Green
