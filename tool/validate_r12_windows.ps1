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

# Delivery/package cleanliness must be checked before npm/flutter generate caches.
Invoke-Step 'verify:delivery (clean source package)' { npm run verify:delivery }
Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'dart format' { npm run format }
Invoke-Step 'verify:all (post-format semantic gates)' { npm run verify:all }
Invoke-Step 'format:check' { npm run format:check }
Invoke-Step 'flutter analyze' { npm run analyze }
Invoke-Step 'flutter test' { npm run test }
Invoke-Step 'build:web' { npm run build:web }

Write-Host "`nPASS R12 Windows release validation" -ForegroundColor Green
