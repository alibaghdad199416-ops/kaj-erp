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

python -B tool/verify_r71_supabase_runtime_isolation.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r71_current_runtime_source.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r72_dashboard_database_contract.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r73_current_runtime_identity.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Launching Edge against havlqebmnjdcwmpaaqew from the verified current source..."
Write-Host "Browser runtime token: r73-current-schema-runtime-20260815" -ForegroundColor Green
flutter run -d edge --dart-define-from-file=dart_defines.json
exit $LASTEXITCODE
