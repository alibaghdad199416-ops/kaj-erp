[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$ProductionDefines = Join-Path $ProjectRoot 'dart_defines.production.json'
$LocalBaseline = Join-Path $ProjectRoot 'dart_defines.json'

if (-not (Test-Path $ProductionDefines)) {
  throw 'dart_defines.production.json is missing.'
}
if (-not (Test-Path $LocalBaseline)) {
  throw 'dart_defines.json local test baseline is missing.'
}

$production = Get-Content $ProductionDefines -Raw | ConvertFrom-Json
if ($production.SUPABASE_URL -ne 'https://havlqebmnjdcwmpaaqew.supabase.co') {
  throw 'Production Supabase URL does not match havlqebmnjdcwmpaaqew.'
}
if ([string]::IsNullOrWhiteSpace([string]$production.SUPABASE_PUBLISHABLE_KEY) -or
    -not ([string]$production.SUPABASE_PUBLISHABLE_KEY).StartsWith('sb_publishable_')) {
  throw 'Production Supabase publishable key is missing or invalid.'
}
if ([string]$production.SUPABASE_PUBLISHABLE_KEY -match 'sb_secret_|service_role') {
  throw 'A secret/service-role key must never be used by the Flutter web client.'
}

Write-Host 'Production runtime configuration is ready.' -ForegroundColor Green
Write-Host 'The Local Supabase dart_defines.json baseline was not modified.' -ForegroundColor Green
Write-Host 'Supabase project: havlqebmnjdcwmpaaqew' -ForegroundColor Cyan
Write-Host 'Firebase project: kaj-erp' -ForegroundColor Cyan
Write-Host 'Runtime file: dart_defines.production.json' -ForegroundColor Cyan
