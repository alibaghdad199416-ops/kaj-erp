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
  Write-Host '`nStarting the existing local Supabase stack...' -ForegroundColor Cyan
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
  $backupPath = Join-Path $BackupDirectory "pre_local_migration_$timestamp.sql"
  Write-Host "`nCreating a non-blocking local business-data backup..." -ForegroundColor Cyan
  Invoke-Supabase -Arguments @('db', 'dump', '--local', '--data-only', '--file', $backupPath) | Out-Null
  if (-not (Test-Path $backupPath) -or (Get-Item $backupPath).Length -le 0) {
    throw 'Local business-data backup was not created; migrations were not applied.'
  }
  Write-Host "PASS: local backup created: $backupPath" -ForegroundColor Green
}

Write-Host "`nLocal migration state before update:" -ForegroundColor Cyan
Invoke-Supabase -Arguments @('migration', 'list', '--local') | Out-Null

Write-Host "`nApplying all pending migrations to the EXISTING LOCAL database..." -ForegroundColor Cyan
Write-Host 'This is forward-only: no db reset, no DROP database, no linked/remote push.' -ForegroundColor Yellow
Invoke-Supabase -Arguments @('migration', 'up', '--local', '--include-all') | Out-Null

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
$localRuntime | ConvertTo-Json | Set-Content -Path $LocalDefines -Encoding utf8

Write-Host '`nPASS: current local Supabase runtime is ready.' -ForegroundColor Green
Write-Host "  API: $apiUrl" -ForegroundColor Green
Write-Host "  Studio: $studioUrl" -ForegroundColor Green
if (-not [string]::IsNullOrWhiteSpace($dbUrl)) {
  Write-Host "  DB: $dbUrl"
}
Write-Host "  Runtime file: $LocalDefines"
Write-Host '  Production dart_defines.json: unchanged.' -ForegroundColor Green
Write-Host '  Remote Supabase: not contacted by this repair path.' -ForegroundColor Green
