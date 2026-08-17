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
  throw 'dart_defines.json local development baseline is missing.'
}

$production = Get-Content $ProductionDefines -Raw | ConvertFrom-Json
$local = Get-Content $LocalBaseline -Raw | ConvertFrom-Json

if ($production.KAJ_BACKEND_TARGET -ne 'production') {
  throw 'Production runtime must declare KAJ_BACKEND_TARGET=production.'
}
if ($production.SUPABASE_URL -ne 'https://havlqebmnjdcwmpaaqew.supabase.co') {
  throw 'Production Supabase URL does not match havlqebmnjdcwmpaaqew.'
}
if ($production.SUPABASE_ALLOW_LOCAL_DEV -ne $false) {
  throw 'Production runtime must explicitly disable Local Supabase.'
}
if ([string]::IsNullOrWhiteSpace([string]$production.SUPABASE_PUBLISHABLE_KEY) -or
    -not ([string]$production.SUPABASE_PUBLISHABLE_KEY).StartsWith('sb_publishable_')) {
  throw 'Production Supabase publishable key is missing or invalid.'
}
if ([string]$production.SUPABASE_PUBLISHABLE_KEY -match 'sb_secret_|service_role') {
  throw 'A secret/service-role key must never be used by the Flutter web client.'
}

if ($local.SUPABASE_URL -ne 'http://127.0.0.1:54321') {
  throw 'Local runtime baseline is not isolated to Local Supabase loopback.'
}
$localKey = [string]($local.SUPABASE_PUBLISHABLE_KEY ?? $local.SUPABASE_ANON_KEY)
if ([string]::IsNullOrWhiteSpace($localKey) -or $localKey -match 'sb_secret_|service_role') {
  throw 'Local runtime must contain a public Supabase key only.'
}
$localNames = @($local.PSObject.Properties.Name)
$unexpectedLocal = @($localNames | Where-Object { $_ -notin @('SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_PUBLISHABLE_KEY') })
if ($unexpectedLocal.Count -gt 0) {
  throw "Unexpected local browser runtime keys: $($unexpectedLocal -join ', ')"
}

Write-Host 'Production runtime configuration is ready.' -ForegroundColor Green
Write-Host 'The Local Supabase dart_defines.json baseline was not modified.' -ForegroundColor Green
Write-Host 'Supabase project: havlqebmnjdcwmpaaqew' -ForegroundColor Cyan
Write-Host 'Firebase project: kaj-erp (Hosting only)' -ForegroundColor Cyan
Write-Host 'Runtime file: dart_defines.production.json' -ForegroundColor Cyan
