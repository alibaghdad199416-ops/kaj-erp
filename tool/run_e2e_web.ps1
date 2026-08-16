$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "KAJ ERP E2E source root: $ProjectRoot"
try {
  $commit = (git rev-parse HEAD).Trim()
  Write-Host "Git commit: $commit"
} catch {
  throw "The current folder is not a valid KAJ ERP Git workspace."
}

python -B tool/verify_r76_local_current_database.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path 'dart_defines.local.generated.json')) {
  Write-Host "Local runtime file is missing; preparing the existing LOCAL Supabase database..." -ForegroundColor Cyan
  powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File tool\prepare_local_current_database.ps1
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "`nLaunching KAJ ERP E2E web server on http://127.0.0.1:8080" -ForegroundColor Green
Write-Host 'Backend source: Supabase CLI local stack only (127.0.0.1).' -ForegroundColor Green
Write-Host 'This fixed port matches playwright.config.ts and Phase 2A/2B browser tests.' -ForegroundColor Green

flutter run -d web-server `
  --web-hostname 127.0.0.1 `
  --web-port 8080 `
  --dart-define-from-file=dart_defines.local.generated.json
exit $LASTEXITCODE
