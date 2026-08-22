[CmdletBinding()]
param(
  [switch]$SupabaseOnly,
  [switch]$HostingOnly,
  [switch]$SkipBuild,
  [switch]$SkipDatabaseDryRun,
  [switch]$SkipAuthConfig,
  [switch]$ReconfigureRuntime,
  [switch]$RequireConfirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($SupabaseOnly -and $HostingOnly) {
  throw 'SupabaseOnly and HostingOnly cannot be used together.'
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$SupabaseProjectRef = 'havlqebmnjdcwmpaaqew'
$ProductionSupabaseWorkdir = 'deployment\production'
$ProductionSupabaseConfig = Join-Path $ProductionSupabaseWorkdir 'supabase\config.toml'
$ProductionDefines = 'dart_defines.production.json'
$FirebaseProjectId = 'kaj-erp'
$RunSupabase = -not $HostingOnly
$RunHosting = -not $SupabaseOnly
$Npx = (Get-Command npx.cmd -ErrorAction Stop).Source
$Npm = (Get-Command npm.cmd -ErrorAction Stop).Source

function Resolve-FlutterTools {
  $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
  if ($null -eq $flutterCommand) {
    $commonFlutter = 'C:\src\flutter\bin\flutter.bat'
    if (Test-Path $commonFlutter) { $flutterCommand = Get-Item $commonFlutter }
  }
  if ($null -eq $flutterCommand) {
    throw 'Flutter was not found. Add Flutter\bin to PATH or install it in C:\src\flutter.'
  }
  $flutterPath = if ($flutterCommand -is [System.IO.FileInfo]) {
    $flutterCommand.FullName
  } else {
    $flutterCommand.Source
  }
  $flutterBin = Split-Path $flutterPath -Parent
  $dartBin = Join-Path $flutterBin 'cache\dart-sdk\bin'
  if (-not (Test-Path (Join-Path $dartBin 'dart.exe'))) {
    throw "Dart SDK was not found under $dartBin."
  }
  $env:Path = "$flutterBin;$dartBin;$env:Path"
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Command
  )
  Write-Host "`n==> $Name" -ForegroundColor Cyan
  & $Command
  if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE." }
}

function Invoke-WithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Command,
    [int]$Attempts = 3
  )
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    Write-Host "`n==> $Name - attempt $attempt of $Attempts" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -eq 0) { return }
    if ($attempt -eq $Attempts) { throw "$Name failed after $Attempts attempts." }
    Start-Sleep -Seconds (5 * $attempt)
  }
}

function Assert-ProductionRuntime {
  if (-not (Test-Path $ProductionDefines)) {
    throw "$ProductionDefines is missing."
  }
  $runtime = Get-Content $ProductionDefines -Raw | ConvertFrom-Json
  if ($runtime.KAJ_BACKEND_TARGET -ne 'production') {
    throw 'Production runtime must declare KAJ_BACKEND_TARGET=production.'
  }
  if ($runtime.SUPABASE_URL -ne "https://$SupabaseProjectRef.supabase.co") {
    throw 'Production runtime points to an unexpected Supabase URL.'
  }
  if ([string]::IsNullOrWhiteSpace([string]$runtime.SUPABASE_PUBLISHABLE_KEY) -or
      -not ([string]$runtime.SUPABASE_PUBLISHABLE_KEY).StartsWith('sb_publishable_')) {
    throw 'Production publishable key is missing or invalid.'
  }
  if ($runtime.SUPABASE_ALLOW_LOCAL_DEV -ne $false) {
    throw 'Production runtime must disable Local Supabase.'
  }
}

function Ensure-SupabaseLink {
  Invoke-WithRetry 'Link exact final Supabase production project' {
    & $Npx --no-install supabase link --project-ref $SupabaseProjectRef --yes
  }
  $refFile = 'supabase\.temp\project-ref'
  if (-not (Test-Path $refFile)) { throw "Supabase link did not create $refFile." }
  $linked = (Get-Content $refFile -Raw).Trim()
  if ($linked -ne $SupabaseProjectRef) {
    throw "Refusing deployment: linked project '$linked' is not '$SupabaseProjectRef'."
  }
}

Resolve-FlutterTools
Assert-ProductionRuntime

if ($ReconfigureRuntime) {
  Invoke-Checked 'Re-validate production runtime values' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\configure_production.ps1
  }
}

if (-not (Test-Path $ProductionSupabaseConfig)) {
  throw "Separated production Supabase config is missing: $ProductionSupabaseConfig"
}
$productionConfigText = Get-Content $ProductionSupabaseConfig -Raw
if ($productionConfigText -notmatch [regex]::Escape($SupabaseProjectRef)) {
  throw 'Production Supabase config does not identify the final project.'
}
if ($productionConfigText -match 'localhost|127\.0\.0\.1') {
  throw 'Production Supabase config must not contain Local Supabase redirects.'
}

if (-not (Test-Path 'node_modules')) {
  Invoke-Checked 'Install Node deployment tools' { & $Npm ci }
}
Invoke-Checked 'Resolve Flutter packages' { flutter.bat pub get }
Invoke-Checked 'Verify strict deployment target separation' { python -B tool\verify_deployment_target.py }
Invoke-Checked 'Verify final acceptance gates' { & $Npm run verify:final }

if (-not $SkipBuild) {
  Invoke-Checked 'Format source' { & $Npm run format }
  Invoke-Checked 'Run analyzer and local-runtime tests' { & $Npm run check }
  Invoke-Checked 'Build production web artifact with production defines only' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\build_production_web.ps1
  }
} elseif (-not (Test-Path 'build\web\index.html')) {
  throw 'SkipBuild was requested but build\web\index.html does not exist.'
}

if ($RunSupabase) {
  Ensure-SupabaseLink

  if (-not $SkipDatabaseDryRun) {
    Invoke-WithRetry 'Preview pending database migrations on final production only' {
      python -B tool\guarded_supabase_db_push.py --linked --dry-run-only --yes
    }
  }

  if ($RequireConfirmation) {
    $confirmation = Read-Host "Type DEPLOY to apply migrations to $SupabaseProjectRef"
    if ($confirmation.Trim().ToUpperInvariant() -ne 'DEPLOY') {
      throw 'Deployment cancelled.'
    }
  }

  Invoke-WithRetry 'Apply migrations to final production only' {
    python -B tool\guarded_supabase_db_push.py --linked --yes
  }

  if (-not $SkipAuthConfig) {
    Invoke-WithRetry 'Push isolated production Auth configuration' {
      & $Npx --no-install supabase --workdir $ProductionSupabaseWorkdir config push `
        --project-ref $SupabaseProjectRef --yes
    }
  }

  foreach ($functionName in @('admin-create-user', 'admin-manage-user', 'admin-update-user-media')) {
    Invoke-WithRetry "Deploy Edge Function $functionName" {
      & $Npx --no-install supabase functions deploy $functionName `
        --project-ref $SupabaseProjectRef --yes
    }
  }

  Invoke-WithRetry 'Confirm no migrations remain' {
    python -B tool\guarded_supabase_db_push.py --linked --dry-run-only --yes
  }
}

if ($RunHosting) {
  Invoke-Checked 'Deploy production web artifact to Firebase Hosting only' {
    & $Npx --yes firebase-tools deploy --only hosting --project $FirebaseProjectId --non-interactive
  }
}

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host 'QUALITY LINE ERP PRODUCTION DEPLOYMENT COMPLETE' -ForegroundColor Green
Write-Host "Application: https://$FirebaseProjectId.web.app" -ForegroundColor Green
Write-Host "Supabase: https://$SupabaseProjectRef.supabase.co" -ForegroundColor Green
Write-Host 'Local Supabase configuration was not pushed to production.' -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Green
