[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$Source = Join-Path $ProjectRoot 'dart_defines.production.json'
$Target = Join-Path $ProjectRoot 'dart_defines.json'

if (Test-Path $Source) {
  Copy-Item $Source $Target -Force
  Write-Host 'Production runtime configuration created from dart_defines.production.json.' -ForegroundColor Green
} elseif (Test-Path $Target) {
  Write-Host 'dart_defines.production.json is not present; keeping the existing dart_defines.json unchanged.' -ForegroundColor Green
} else {
  throw 'Neither dart_defines.production.json nor dart_defines.json exists.'
}
Write-Host 'Supabase project: havlqebmnjdcwmpaaqew' -ForegroundColor Cyan
Write-Host 'Firebase project: kaj-erp' -ForegroundColor Cyan
