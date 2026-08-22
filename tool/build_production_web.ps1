$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
$ProductionDefines = 'dart_defines.production.json'

if (-not (Test-Path $ProductionDefines)) {
  throw 'Production runtime file dart_defines.production.json is missing.'
}

Write-Host 'Verifying production Supabase/Firebase target...' -ForegroundColor Cyan
python -B tool/verify_deployment_target.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Preparing production web release...' -ForegroundColor Cyan
python -B tool/prepare_web_release.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Building Flutter Web with hosted Supabase production defines...' -ForegroundColor Cyan
flutter build web --release --no-wasm-dry-run --no-web-resources-cdn --dart-define-from-file=$ProductionDefines
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/prepare_local_canvaskit.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

python -B tool/verify_web_release.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'PASS production web build' -ForegroundColor Green
Write-Host 'Supabase: https://havlqebmnjdcwmpaaqew.supabase.co' -ForegroundColor Green
Write-Host 'Firebase Hosting target: kaj-erp' -ForegroundColor Green
