$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "KAJ ERP source root: $ProjectRoot"
try {
  $commit = (git rev-parse HEAD).Trim()
  Write-Host "Git commit: $commit"
} catch {
  throw "The current folder is not a valid KAJ ERP Git workspace."
}

python -B tool/verify_r76_local_current_database.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r78_complete_requirements.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nPreparing the CURRENT LOCAL Supabase database..." -ForegroundColor Cyan
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\prepare_local_current_database.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path 'dart_defines.local.generated.json')) {
  throw 'Local Supabase runtime file was not generated.'
}

Write-Host "`nLaunching KAJ ERP against LOCAL Supabase only..." -ForegroundColor Green
Write-Host 'Backend source: Supabase CLI local stack (127.0.0.1)' -ForegroundColor Green
Write-Host 'All pending migrations, including R78, are applied forward-only to the existing local database.' -ForegroundColor Green
Write-Host 'Production configuration remains separate and unchanged.' -ForegroundColor Green
flutter run -d edge --dart-define-from-file=dart_defines.local.generated.json
exit $LASTEXITCODE
