$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-Step { param([string]$Label,[scriptblock]$Action); Write-Host "`n==> $Label" -ForegroundColor Cyan; & $Action; if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" } }
Invoke-Step 'npm ci' { npm ci }
Invoke-Step 'flutter pub get' { flutter pub get }
Invoke-Step 'dart format' { npm run format }
Invoke-Step 'R49 complete workspace gates' { npm run verify:all }
Invoke-Step 'format check' { npm run format:check }
Invoke-Step 'flutter analyze' { npm run analyze }
Invoke-Step 'flutter test' { npm run test }
Invoke-Step 'fresh web release build' { npm run build:web }
Write-Host "`nPASS R49 installed-workspace validation" -ForegroundColor Green
