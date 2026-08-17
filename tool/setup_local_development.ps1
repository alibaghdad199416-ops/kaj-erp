[CmdletBinding()]
param(
  [string]$Email = 'dev@kaj.local',
  [string]$Password = 'KajLocalDev!2026-LocalOnly'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Require-Command([string]$Name, [string]$InstallHint) {
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw "$Name is required. $InstallHint"
  }
  return $command.Source
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host 'KAJ ERP - LOCAL DEVELOPMENT FIRST-RUN SETUP' -ForegroundColor Cyan
Write-Host 'Target: Local Supabase only (127.0.0.1)' -ForegroundColor Green
Write-Host 'Hosted Supabase is not used by this setup path.' -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Cyan

Require-Command 'git.exe' 'Install Git for Windows and reopen VS Code.' | Out-Null
Require-Command 'node.exe' 'Install Node.js 20 or later and reopen VS Code.' | Out-Null
Require-Command 'npm.cmd' 'Install Node.js 20 or later and reopen VS Code.' | Out-Null
Require-Command 'npx.cmd' 'Install Node.js 20 or later and reopen VS Code.' | Out-Null
Require-Command 'python.exe' 'Install Python and reopen VS Code.' | Out-Null
Require-Command 'flutter.bat' 'Install Flutter and add it to PATH.' | Out-Null
Require-Command 'docker.exe' 'Install Docker Desktop with the WSL 2 backend, start it, then retry.' | Out-Null

$nodeVersion = (& node --version).Trim().TrimStart('v')
$nodeMajor = [int]($nodeVersion.Split('.')[0])
if ($nodeMajor -lt 20) {
  throw "Node.js 20 or later is required by the Supabase CLI. Current version: $nodeVersion"
}

Write-Host "`nChecking Docker Desktop engine..." -ForegroundColor Cyan
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker info *> $null
$dockerExit = [int]$LASTEXITCODE
$ErrorActionPreference = $previousPreference
if ($dockerExit -ne 0) {
  throw 'Docker is installed but its engine is not running. Start Docker Desktop and wait until it reports Running, then retry.'
}
Write-Host 'PASS: Docker engine is running.' -ForegroundColor Green

if (-not (Test-Path 'node_modules\.bin\supabase.cmd')) {
  Write-Host "`nInstalling pinned project tooling with npm ci..." -ForegroundColor Cyan
  & npm.cmd ci
  if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
} else {
  Write-Host 'PASS: project Supabase CLI dependency is already installed.' -ForegroundColor Green
}

Write-Host "`nPreparing the forward-only LOCAL database..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tool\prepare_local_current_database.ps1'
if ($LASTEXITCODE -ne 0) { throw 'Local database preparation failed.' }

Write-Host "`nCreating/updating the LOCAL development login..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'tool\bootstrap_local_supabase.ps1' -Email $Email -Password $Password
if ($LASTEXITCODE -ne 0) { throw 'Local Auth bootstrap failed.' }

Write-Host "`nRunning deployment-target safety verification..." -ForegroundColor Cyan
& python.exe -B 'tool\verify_deployment_target.py'
if ($LASTEXITCODE -ne 0) { throw 'Deployment-target verification failed.' }

Write-Host "`nLOCAL DEVELOPMENT IS READY" -ForegroundColor Green
Write-Host 'Supabase API:    http://127.0.0.1:54321' -ForegroundColor Green
Write-Host 'Supabase Studio: http://127.0.0.1:54323' -ForegroundColor Green
Write-Host "Login email:     $Email" -ForegroundColor Green
Write-Host "Login password:  $Password" -ForegroundColor Green
Write-Host ''
Write-Host 'Start the ERP with:' -ForegroundColor Cyan
Write-Host '  npm run run:web:local'
Write-Host ''
Write-Host 'Stop Local Supabase without deleting its database with:' -ForegroundColor Cyan
Write-Host '  npx supabase stop'
Write-Host ''
Write-Host 'No Hosted Supabase project was contacted by this first-run setup.' -ForegroundColor Green
