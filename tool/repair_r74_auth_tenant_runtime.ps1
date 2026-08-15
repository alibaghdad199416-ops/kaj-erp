Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$ExpectedProjectRef = 'havlqebmnjdcwmpaaqew'
$RefFile = Join-Path $ProjectRoot 'supabase\.temp\project-ref'

Write-Host "KAJ ERP R74 auth/tenant repair root: $ProjectRoot" -ForegroundColor Cyan

if (-not (Test-Path $RefFile)) {
  throw "Supabase project is not linked. Run: npx supabase link --project-ref $ExpectedProjectRef"
}
$LinkedProjectRef = (Get-Content $RefFile -Raw).Trim()
if ($LinkedProjectRef -ne $ExpectedProjectRef) {
  throw "Refusing R74 repair: linked project '$LinkedProjectRef' is not '$ExpectedProjectRef'."
}
Write-Host "PASS: linked Supabase project = $LinkedProjectRef" -ForegroundColor Green

python -B tool/verify_r71_supabase_runtime_isolation.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python -B tool/verify_r71_current_runtime_source.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python -B tool/verify_r72_dashboard_database_contract.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
python -B tool/verify_r74_authenticated_tenant_runtime.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nPreviewing pending R74 database migration..." -ForegroundColor Cyan
python -B tool/guarded_supabase_db_push.py --linked --dry-run-only --yes
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nApplying pending migrations to $ExpectedProjectRef..." -ForegroundColor Cyan
python -B tool/guarded_supabase_db_push.py --linked --yes
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nPASS R74 auth/tenant database synchronization" -ForegroundColor Green
Write-Host "  - project: $ExpectedProjectRef"
Write-Host "  - persisted sessions are verified before tenant restore"
Write-Host "  - tenant cache is scoped by project + Auth user"
Write-Host "  - database runtime identity attestation is installed"
Write-Host "  - browser runtime token: r74-authenticated-tenant-runtime-20260815"
Write-Host "  - no db reset/drop/truncate was used"
