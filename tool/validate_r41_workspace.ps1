$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-Step { param([string]$Label,[scriptblock]$Action); Write-Host "`n==> $Label" -ForegroundColor Cyan; & $Action; if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" } }
Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'R41 gates' { npm run verify:r41 }
Invoke-Step 'R40 compatibility' { npm run verify:r40 }
Invoke-Step 'static source verification' { npm run verify:source }
Invoke-Step 'database contracts' { npm run verify:database }
Invoke-Step 'localization verification' { npm run verify:localization }
Invoke-Step 'flutter analyze' { npm run analyze }
Invoke-Step 'flutter test' { npm run test }
Invoke-Step 'fresh web release build' { npm run build:web }
Write-Host "`nPASS R41 installed-workspace validation" -ForegroundColor Green
