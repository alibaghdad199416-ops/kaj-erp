[CmdletBinding()]
param(
  [switch]$SkipBusinessDataBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$ExpectedLocalProjectId = 'quality_line_erp_local_dev'
$LocalDefines = Join-Path $ProjectRoot 'dart_defines.local.generated.json'
$ConfigPath = Join-Path $ProjectRoot 'supabase\config.toml'
$BackupDirectory = Join-Path $ProjectRoot '.local_backups'
$Npx = (Get-Command npx.cmd -ErrorAction Stop).Source

# These versions were written to the local migration history by an intermediate
# source state and no longer exist in the authoritative migration directory.
# Supabase CLI itself recommends marking these history rows reverted before
# continuing. This changes only supabase_migrations.schema_migrations; it does
# not execute rollback SQL and does not remove business data.
$KnownOrphanedLocalMigrationVersions = @(
  '20260815044500',
  '20260815055000',
  '20260815060000',
  '20260815080000',
  '20260815083000',
  '20260815083800',
  '20260815120500'
)

function Invoke-Supabase {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$AllowFailure,
    [switch]$Capture
  )

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    if ($Capture) {
      $output = & $Npx --no-install supabase @Arguments 2>&1
      $code = [int]$LASTEXITCODE
      if (-not $AllowFailure -and $code -ne 0) {
        foreach ($line in @($output)) { Write-Host $line }
        throw "Supabase command failed: supabase $($Arguments -join ' ') (exit $code)"
      }
      return [pscustomobject]@{ Code = $code; Output = @($output) }
    }

    & $Npx --no-install supabase @Arguments
    $code = [int]$LASTEXITCODE
    if (-not $AllowFailure -and $code -ne 0) {
      throw "Supabase command failed: supabase $($Arguments -join ' ') (exit $code)"
    }
    return $code
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Get-LocalStatusVariables {
  $status = Invoke-Supabase -Arguments @('status', '-o', 'env') -AllowFailure -Capture
  if ($status.Code -ne 0) {
    return $null
  }

  $values = @{}
  foreach ($rawLine in $status.Output) {
    $line = [string]$rawLine
    if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*["'']?(.*?)["'']?\s*$') {
      $values[$matches[1]] = $matches[2]
    }
  }
  if (-not $values.ContainsKey('API_URL') -or -not $values.ContainsKey('ANON_KEY')) {
    throw 'Supabase local status did not expose API_URL and ANON_KEY.'
  }
  return $values
}

function Invoke-LocalMigrationUpWithSafeHistoryRepair {
  Write-Host "`nApplying all pending migrations to the EXISTING LOCAL database..." -ForegroundColor Cyan
  Write-Host 'This is forward-only: no db reset, no DROP database, no linked/remote push.' -ForegroundColor Yellow

  $up = Invoke-Supabase -Arguments @('migration', 'up', '--local', '--include-all') -AllowFailure -Capture
  if ($up.Code -eq 0) {
    foreach ($line in $up.Output) { Write-Host $line }
    return
  }

  $allOutput = ($up.Output | ForEach-Object { [string]$_ }) -join "`n"
  if ($allOutput -notmatch 'Remote migration versions not found in local migrations directory') {
    foreach ($line in $up.Output) { Write-Host $line }
    throw 'Local migration update failed for a reason unrelated to migration-history drift.'
  }

  $repairLine = $up.Output |
    ForEach-Object { [string]$_ } |
    Where-Object { $_ -match 'migration repair\s+--status\s+reverted' } |
    Select-Object -First 1

  if ([string]::IsNullOrWhiteSpace([string]$repairLine)) {
    foreach ($line in $up.Output) { Write-Host $line }
    throw 'Supabase reported migration-history drift but did not provide repair versions.'
  }

  $versions = @(
    [regex]::Matches([string]$repairLine, '\b\d{14}\b') |
      ForEach-Object { $_.Value } |
      Select-Object -Unique
  )
  if ($versions.Count -eq 0) {
    foreach ($line in $up.Output) { Write-Host $line }
    throw 'No migration versions could be parsed from the Supabase repair recommendation.'
  }

  $unexpected = @($versions | Where-Object { $_ -notin $KnownOrphanedLocalMigrationVersions })
  if ($unexpected.Count -gt 0) {
    foreach ($line in $up.Output) { Write-Host $line }
    throw "Refusing automatic migration-history repair because unexpected local-only versions were found: $($unexpected -join ', ')"
  }

  Write-Host "`nDetected known orphaned LOCAL migration-history rows:" -ForegroundColor Yellow
  foreach ($version in $versions) {
    Write-Host "  - $version" -ForegroundColor Yellow
  }
  Write-Host 'Repairing tracking history only; no SQL rollback and no business-row deletion.' -ForegroundColor Yellow

  $repairArgs = @('migration', 'repair') + $versions + @('--status', 'reverted', '--local')
  Invoke-Supabase -Arguments $repairArgs | Out-Null

  Write-Host "`nRetrying forward-only local migration update after history reconciliation..." -ForegroundColor Cyan
  $retry = Invoke-Supabase -Arguments @('migration', 'up', '--local', '--include-all') -AllowFailure -Capture
  foreach ($line in $retry.Output) { Write-Host $line }
  if ($retry.Code -ne 0) {
    throw 'Local migration update still failed after safe migration-history reconciliation.'
  }
}

if (-not (Test-Path $ConfigPath)) {
  throw 'supabase\config.toml is missing. The local database cannot be started safely.'
}
$config = Get-Content $ConfigPath -Raw
if ($config -notmatch 'project_id\s*=\s*"quality_line_erp_local_dev"') {
  throw "Local Supabase project_id must remain '$ExpectedLocalProjectId'."
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host 'KAJ ERP - CURRENT LOCAL DATABASE' -ForegroundColor Cyan
Write-Host "Local project id: $ExpectedLocalProjectId" -ForegroundColor Green
Write-Host 'Hosted production configuration will not be modified.' -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Cyan

$statusValues = Get-LocalStatusVariables
if ($null -eq $statusValues) {
  Write-Host "`nStarting the existing local Supabase stack..." -ForegroundColor Cyan
  Write-Host 'No db reset and no remote project operation will be used.' -ForegroundColor Yellow
  Invoke-Supabase -Arguments @('start') | Out-Null
  $statusValues = Get-LocalStatusVariables
  if ($null -eq $statusValues) {
    throw 'Supabase local stack did not become available after supabase start.'
  }
} else {
  Write-Host 'PASS: existing local Supabase stack is already running.' -ForegroundColor Green
}

$apiUrl = [string]$statusValues['API_URL']
$anonKey = [string]$statusValues['ANON_KEY']
$dbUrl = if ($statusValues.ContainsKey('DB_URL')) { [string]$statusValues['DB_URL'] } else { '' }
$studioUrl = if ($statusValues.ContainsKey('STUDIO_URL')) { [string]$statusValues['STUDIO_URL'] } else { 'http://127.0.0.1:54323' }

try {
  $apiUri = [Uri]$apiUrl
} catch {
  throw "Invalid local API URL returned by Supabase: $apiUrl"
}
if ($apiUri.Scheme -ne 'http' -or $apiUri.Host -notin @('127.0.0.1', 'localhost')) {
  throw "Refusing non-local Supabase API URL: $apiUrl"
}
if ([string]::IsNullOrWhiteSpace($anonKey)) {
  throw 'Local Supabase anon key is empty.'
}

if (-not $SkipBusinessDataBackup) {
  New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $dataBackupPath = Join-Path $BackupDirectory "pre_local_migration_data_$timestamp.sql"
  $schemaBackupPath = Join-Path $BackupDirectory "pre_local_migration_schema_$timestamp.sql"

  Write-Host "`nCreating local backups before migration/history reconciliation..." -ForegroundColor Cyan
  Invoke-Supabase -Arguments @('db', 'dump', '--local', '--data-only', '--file', $dataBackupPath) | Out-Null
  Invoke-Supabase -Arguments @('db', 'dump', '--local', '--file', $schemaBackupPath) | Out-Null

  foreach ($backupPath in @($dataBackupPath, $schemaBackupPath)) {
    if (-not (Test-Path $backupPath) -or (Get-Item $backupPath).Length -le 0) {
      throw "Local backup was not created correctly: $backupPath"
    }
  }
  Write-Host "PASS: local data backup created: $dataBackupPath" -ForegroundColor Green
  Write-Host "PASS: local schema backup created: $schemaBackupPath" -ForegroundColor Green
}

Write-Host "`nLocal migration state before update:" -ForegroundColor Cyan
Invoke-Supabase -Arguments @('migration', 'list', '--local') | Out-Null

Invoke-LocalMigrationUpWithSafeHistoryRepair

Write-Host "`nLocal migration state after update:" -ForegroundColor Cyan
Invoke-Supabase -Arguments @('migration', 'list', '--local') | Out-Null

$statusValues = Get-LocalStatusVariables
$apiUrl = [string]$statusValues['API_URL']
$anonKey = [string]$statusValues['ANON_KEY']

$localRuntime = [ordered]@{
  SUPABASE_URL = $apiUrl
  SUPABASE_PUBLISHABLE_KEY = $anonKey
  SUPABASE_LOCAL_PROJECT_ID = $ExpectedLocalProjectId
  SUPABASE_ALLOW_LOCAL_DEV = $true
}
$runtimeJson = $localRuntime | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($LocalDefines, $runtimeJson + [Environment]::NewLine, $utf8NoBom)

Write-Host "`nPASS: current local Supabase runtime is ready." -ForegroundColor Green
Write-Host "  API: $apiUrl" -ForegroundColor Green
Write-Host "  Studio: $studioUrl" -ForegroundColor Green
if (-not [string]::IsNullOrWhiteSpace($dbUrl)) {
  Write-Host "  DB: $dbUrl"
}
Write-Host "  Runtime file: $LocalDefines"
Write-Host '  Production dart_defines.json: unchanged.' -ForegroundColor Green
Write-Host '  Remote Supabase: not contacted by this repair path.' -ForegroundColor Green
