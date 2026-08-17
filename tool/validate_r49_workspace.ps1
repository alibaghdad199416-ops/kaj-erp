$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-Step { param([string]$Label,[scriptblock]$Action); Write-Host "`n==> $Label" -ForegroundColor Cyan; & $Action; if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" } }
Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'dart format' { npm run format }
Invoke-Step 'R49 complete workspace gates' { npm run verify:all }
Invoke-Step 'format check' { npm run format:check }
Invoke-Step 'flutter analyze' { npm run analyze }
# Tests intentionally exercise the LOCAL DEVELOPMENT runtime contract.
Invoke-Step 'flutter test (local runtime)' { npm run test }
# The artifact that can reach Firebase Hosting must always use production defines.
Invoke-Step 'fresh production web release build' {
    powershell -NoProfile -ExecutionPolicy Bypass -File tool/build_production_web.ps1
}
Write-Host "`nPASS R49 installed-workspace validation" -ForegroundColor Green
