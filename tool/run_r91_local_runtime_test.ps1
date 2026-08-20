$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$container = docker ps --format '{{.Names}}' | Where-Object { $_ -eq 'supabase_db_quality_line_erp_local_dev' } | Select-Object -First 1
if (-not $container) {
  throw 'LOCAL Supabase PostgreSQL container supabase_db_quality_line_erp_local_dev is not running.'
}

$testFile = Join-Path $ProjectRoot 'supabase\tests\verify_r91_phase11_runtime.sql'
if (-not (Test-Path -LiteralPath $testFile -PathType Leaf)) {
  throw "R91 runtime SQL test not found: $testFile"
}

Get-Content -LiteralPath $testFile -Raw -Encoding UTF8 |
  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
  throw 'R91 LOCAL PostgreSQL runtime verification failed.'
}
