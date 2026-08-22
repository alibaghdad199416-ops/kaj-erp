$ErrorActionPreference = "Stop"

Set-Location C:\Projects\kaj-erp

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " R95.2 LOCAL DATABASE DIAGNOSTIC" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Find the LOCAL Supabase PostgreSQL container.
$dbContainer = docker ps --format "{{.Names}}" |
    Where-Object { $_ -eq "supabase_db_quality_line_erp_local_dev" } |
    Select-Object -First 1

if (-not $dbContainer) {
    $dbContainer = docker ps --format "{{.Names}}" |
        Where-Object { $_ -like "supabase_db_*" } |
        Select-Object -First 1
}

if (-not $dbContainer) {
    throw "Local Supabase PostgreSQL container was not found."
}

Write-Host "Database container: $dbContainer" -ForegroundColor Green

$backupDir = Join-Path (Get-Location) ".local_backups"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

$definitionFile = Join-Path `
    $backupDir `
    "r95_2_invoice_function_definition_$stamp.sql"

Write-Host "`n=== READ CURRENT FUNCTION DEFINITION ===" -ForegroundColor Cyan

$sql = @"
select pg_get_functiondef(
  'public.erp_approve_cloud_workflow_invoice(uuid,uuid,text)'::regprocedure
);
"@

$raw = & docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -A `
    -t `
    -c $sql 2>&1

$psqlExit = $LASTEXITCODE

if ($psqlExit -ne 0) {
    $raw | ForEach-Object { Write-Host $_ }
    throw "Could not read local PostgreSQL function definition."
}

$definition = ($raw -join "`n").Trim()

if ([string]::IsNullOrWhiteSpace($definition)) {
    throw "Function definition is empty."
}

$utf8 = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
    $definitionFile,
    $definition,
    $utf8
)

Write-Host "Saved: $definitionFile" -ForegroundColor Green

$oldGuard = @'
perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.approve','sales.update'] else array['purchases.approve','purchases.update'] end);
'@

$exactIndex = $definition.IndexOf(
    $oldGuard,
    [System.StringComparison]::Ordinal
)

$broadIndex = $definition.IndexOf(
    "erp_require_any_cloud_permission",
    [System.StringComparison]::Ordinal
)

$granularIndex = $definition.IndexOf(
    "erp_r95_user_can_perform_action",
    [System.StringComparison]::Ordinal
)

Write-Host "`n=== GUARD ANALYSIS ===" -ForegroundColor Cyan

Write-Host "Exact historical guard index : $exactIndex"
Write-Host "Broad permission call index   : $broadIndex"
Write-Host "R95 granular guard index      : $granularIndex"

Write-Host "`n=== FUNCTION METADATA ===" -ForegroundColor Cyan

$metaSql = @"
select
  p.oid::text as oid,
  p.proname,
  pg_get_userbyid(p.proowner) as owner,
  p.prosecdef as security_definer,
  md5(p.prosrc) as body_md5
from pg_proc p
where p.oid =
  'public.erp_approve_cloud_workflow_invoice(uuid,uuid,text)'::regprocedure;
"@

& docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -P pager=off `
    -c $metaSql

if ($LASTEXITCODE -ne 0) {
    throw "Function metadata query failed."
}

Write-Host "`n=== GUARD CONTEXT ===" -ForegroundColor Cyan

$lines = $definition -split "`r?`n"

$matchLine = -1

for ($i = 0; $i -lt $lines.Count; $i++) {
    if (
        $lines[$i] -match "erp_require_any_cloud_permission" -or
        $lines[$i] -match "erp_r95_user_can_perform_action"
    ) {
        $matchLine = $i
        break
    }
}

if ($matchLine -ge 0) {
    $start = [Math]::Max(0, $matchLine - 4)
    $end   = [Math]::Min($lines.Count - 1, $matchLine + 12)

    for ($i = $start; $i -le $end; $i++) {
        "{0,4}: {1}" -f ($i + 1), $lines[$i]
    }
}
else {
    Write-Host "No broad/granular authorization marker found." -ForegroundColor Red
}

Write-Host "`n=== LOCAL MIGRATION HISTORY ===" -ForegroundColor Cyan

$historySql = @"
select version, name
from supabase_migrations.schema_migrations
where version >= '20260821044500'
order by version;
"@

& docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -P pager=off `
    -c $historySql

if ($LASTEXITCODE -ne 0) {
    throw "Migration-history query failed."
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " R95.2 DIAGNOSTIC COMPLETED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nIMPORTANT:"
Write-Host "No database data or migration history was modified."
Write-Host "Do NOT run db reset, db push, migration repair, or link."