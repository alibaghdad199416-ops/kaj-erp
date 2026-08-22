param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $ProjectRoot

$ExpectedProjectId = 'quality_line_erp_local_dev'
$Container = "supabase_db_$ExpectedProjectId"
$TestFile = Join-Path $ProjectRoot 'supabase\tests\verify_r90_phase11_runtime.sql'

if (-not (Test-Path -LiteralPath $TestFile -PathType Leaf)) {
  throw "R90 runtime SQL is missing: $TestFile"
}
if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
  throw 'Docker Desktop/CLI is required for the LOCAL Supabase runtime test.'
}

$running = (& docker.exe inspect -f '{{.State.Running}}' $Container 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $running -ne 'true') {
  throw "LOCAL Supabase database container is not running: $Container. Run npm run db:local:update first."
}

$label = (& docker.exe inspect -f '{{index .Config.Labels "com.supabase.cli.project"}}' $Container).Trim()
if ($LASTEXITCODE -ne 0 -or $label -ne $ExpectedProjectId) {
  throw "Refusing unexpected Docker database container/project label: $Container / $label"
}

$remote = '/tmp/verify_r90_phase11_runtime.sql'
Write-Host 'Running R90 Phase 11 runtime test against LOCAL Supabase only...' -ForegroundColor Cyan
& docker.exe cp $TestFile "${Container}:$remote"
if ($LASTEXITCODE -ne 0) { throw 'Could not copy R90 runtime SQL into the LOCAL database container.' }

& docker.exe exec $Container psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -f $remote
if ($LASTEXITCODE -ne 0) { throw 'R90 LOCAL PostgreSQL runtime test failed.' }

Write-Host 'PASS: R90 Phase 11 LOCAL PostgreSQL runtime test.' -ForegroundColor Green
Write-Host 'No Production Supabase endpoint was contacted.' -ForegroundColor Green
