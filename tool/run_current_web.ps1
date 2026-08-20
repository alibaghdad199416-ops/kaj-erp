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

python -B tool/verify_r79_media_export_stabilization.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r84_user_media_scope_ui_exports.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r85_secondary_record_scope.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r88_phase11.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r89_phase11_completion.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r90_phase11_final_acceptance.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r91_phase11_material_issue_acceptance.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_r92_comprehensive_module_audit.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nPreparing the CURRENT LOCAL Supabase database..." -ForegroundColor Cyan
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\prepare_local_current_database.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\run_r89_local_runtime_test.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\run_r90_local_runtime_test.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\run_r91_local_runtime_test.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tool\run_r92_local_runtime_test.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path 'dart_defines.local.generated.json')) {
  throw 'Local Supabase runtime file was not generated.'
}

Write-Host "`nLaunching KAJ ERP against LOCAL Supabase only..." -ForegroundColor Green
Write-Host 'Backend source: Supabase CLI local stack (127.0.0.1)' -ForegroundColor Green
Write-Host 'All pending migrations, including R88/R89/R90/R91/R92 Phase 11 + comprehensive module audit, are applied forward-only to the existing local database.' -ForegroundColor Green
Write-Host 'Production configuration remains separate and unchanged.' -ForegroundColor Green
flutter run -d edge --dart-define-from-file=dart_defines.local.generated.json
exit $LASTEXITCODE
