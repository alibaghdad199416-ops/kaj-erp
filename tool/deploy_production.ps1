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

$SupabaseProjectRef = 'fjiaxdorunedmltgqtty'
$FirebaseProjectId = 'kaj-erp'
$RunSupabase = -not $HostingOnly
$RunHosting = -not $SupabaseOnly
$Npx = (Get-Command npx.cmd -ErrorAction Stop).Source
$Npm = (Get-Command npm.cmd -ErrorAction Stop).Source

function Resolve-FlutterTools {
  $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
  if ($null -eq $flutterCommand) {
    $commonFlutter = 'C:\src\flutter\bin\flutter.bat'
    if (Test-Path $commonFlutter) {
      $flutterCommand = Get-Item $commonFlutter
    }
  }
  if ($null -eq $flutterCommand) {
    throw 'Flutter was not found. Add Flutter\bin to PATH or install it in C:\src\flutter.'
  }

  $flutterPath = if ($flutterCommand -is [System.IO.FileInfo]) {
    $flutterCommand.FullName
  } else {
    $flutterCommand.Source
  }
  if ([string]::IsNullOrWhiteSpace([string]$flutterPath)) {
    throw 'Flutter command path could not be resolved.'
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
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Command
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($code -ne 0) {
    throw "$Name failed with exit code $code."
  }
}

function Invoke-WithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Command,
    [int]$Attempts = 6
  )

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    Write-Host "`n==> $Name - attempt $attempt of $Attempts" -ForegroundColor Cyan
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & $Command
      $code = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousPreference
    }
    if ($code -eq 0) {
      Write-Host "PASS: $Name" -ForegroundColor Green
      return
    }
    if ($attempt -eq $Attempts) {
      throw "$Name failed after $Attempts attempts. Last exit code: $code."
    }
    $delay = 10 * $attempt
    Write-Host "Retrying in $delay seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds $delay
  }
}

function Invoke-Firebase {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $firebase = Get-Command firebase.cmd -ErrorAction SilentlyContinue
    if ($null -ne $firebase) {
      $output = & $firebase.Source @Arguments 2>&1
    } else {
      $output = & $Npx --yes firebase-tools @Arguments 2>&1
    }
    $code = [int]$LASTEXITCODE
    foreach ($line in @($output)) {
      Write-Host $line
    }
    return $code
  } finally {
    $ErrorActionPreference = $previous
  }
}

function Ensure-SupabaseLogin {
  # A fresh source folder has no project ref yet. `projects list` can fail with
  # "Cannot find project ref" before authentication is even evaluated.
  # The linked-project command below is the authoritative authentication check.
  Write-Host 'Supabase authentication will be validated during project linking.' -ForegroundColor Green
}

function Ensure-SupabaseLink {
  $refFile = 'supabase\.temp\project-ref'
  $linked = if (Test-Path $refFile) {
    (Get-Content $refFile -Raw).Trim()
  } else {
    ''
  }
  if ($linked -eq $SupabaseProjectRef) {
    Write-Host "Supabase project is already linked: $linked" -ForegroundColor Green
    return
  }

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Npx --no-install supabase link `
      --project-ref $SupabaseProjectRef `
      --yes
    $linkCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }

  if ($linkCode -ne 0) {
    Write-Host 'Supabase authentication may have expired. Opening login once.' -ForegroundColor Yellow
    Invoke-Checked 'Sign in to Supabase CLI' {
      & $Npx --no-install supabase login
    }
    Invoke-WithRetry 'Link Supabase project' {
      & $Npx --no-install supabase link `
        --project-ref $SupabaseProjectRef `
        --yes
    }
  }

  if (-not (Test-Path $refFile)) {
    throw 'Supabase link completed without creating supabase\.temp\project-ref.'
  }
  $linked = (Get-Content $refFile -Raw).Trim()
  if ($linked -ne $SupabaseProjectRef) {
    throw "The folder is linked to '$linked' instead of '$SupabaseProjectRef'."
  }
  Write-Host "Supabase project linked successfully: $linked" -ForegroundColor Green
}

function Move-MigrationBackups {
  $backupDirectory = 'supabase\migration_backups'
  New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
  Get-ChildItem 'supabase\migrations' -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match '\.bak$' -or
      $_.Name -match '\.before_' -or
      $_.Name -match '\.before_case_expression_fix$'
    } |
    Move-Item -Destination $backupDirectory -Force
}

Resolve-FlutterTools
Move-MigrationBackups

if ($ReconfigureRuntime) {
  Invoke-Checked 'Configure production runtime values' {
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
      -File tool\configure_production.ps1
  }
} elseif (-not (Test-Path 'dart_defines.json')) {
  throw 'dart_defines.json is missing. Restore the existing production runtime file or rerun with -ReconfigureRuntime intentionally.'
} else {
  Write-Host 'Using the existing dart_defines.json unchanged.' -ForegroundColor Green
}

if (-not (Test-Path 'node_modules')) {
  Invoke-Checked 'Install Node deployment tools' { & $Npm ci }
}
Invoke-Checked 'Resolve Flutter packages' { flutter.bat pub get }
Invoke-Checked 'Verify deployment target' {
  python tool\verify_deployment_target.py
}
Invoke-Checked 'Verify final acceptance gates' {
  & $Npm run verify:final
}

if (-not $SkipBuild) {
  Invoke-Checked 'Analyze, test, and build current release' {
    & $Npm run check:release
  }
} elseif (-not (Test-Path 'build\web\index.html')) {
  throw 'SkipBuild was requested but build\web\index.html does not exist.'
}

if ($RunSupabase) {
  Ensure-SupabaseLogin
  Ensure-SupabaseLink

  if (-not $SkipDatabaseDryRun) {
    Invoke-WithRetry 'Preview pending database migrations' {
      python -B tool\guarded_supabase_db_push.py --linked --dry-run-only --yes
    }
  }

  if ($RequireConfirmation) {
    $confirmation = Read-Host "Type DEPLOY to apply migrations to $SupabaseProjectRef"
    if ($confirmation.Trim().ToUpperInvariant() -ne 'DEPLOY') {
      throw 'Deployment cancelled.'
    }
  }

  Invoke-WithRetry 'Apply Supabase database migrations' {
    python -B tool\guarded_supabase_db_push.py --linked --yes
  }

  if (-not $SkipAuthConfig) {
    Invoke-WithRetry 'Push Supabase Auth configuration' {
      & $Npx --no-install supabase config push `
        --project-ref $SupabaseProjectRef `
        --yes
    }
  }

  Invoke-WithRetry 'Deploy admin-create-user Edge Function' {
    & $Npx --no-install supabase functions deploy admin-create-user `
      --project-ref $SupabaseProjectRef `
      --yes
  }
  Invoke-WithRetry 'Deploy admin-manage-user Edge Function' {
    & $Npx --no-install supabase functions deploy admin-manage-user `
      --project-ref $SupabaseProjectRef `
      --yes
  }

  Invoke-WithRetry 'Confirm no migrations remain' {
    python -B tool\guarded_supabase_db_push.py --linked --dry-run-only --yes
  }
}

if ($RunHosting) {
  Write-Host "`n==> Deploy Firebase Hosting" -ForegroundColor Cyan
  $firebaseCode = Invoke-Firebase deploy `
    --only hosting `
    --project $FirebaseProjectId `
    --non-interactive

  if ($firebaseCode -ne 0) {
    Write-Host 'Firebase authentication may have expired. Opening no-localhost login once.' -ForegroundColor Yellow
    $loginCode = Invoke-Firebase login --reauth --no-localhost

    # On Windows, some Firebase/Node builds can save the login successfully and
    # then exit with a libuv assertion code while closing. Always retry deploy;
    # the deploy result, not the login process code, is authoritative.
    if ($loginCode -ne 0) {
      Write-Host "Firebase login returned exit code $loginCode; retrying deployment because credentials may still have been saved." -ForegroundColor Yellow
    }

    $firebaseCode = Invoke-Firebase deploy `
      --only hosting `
      --project $FirebaseProjectId `
      --non-interactive
  }

  if ($firebaseCode -ne 0) {
    throw "Firebase Hosting deployment failed with exit code $firebaseCode."
  }

  Write-Host "`n==> Verify Firebase Hosting URL" -ForegroundColor Cyan
  $hostingUrl = "https://$FirebaseProjectId.web.app"
  $statusCode = $null
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      $response = Invoke-WebRequest `
        -Uri $hostingUrl `
        -UseBasicParsing `
        -TimeoutSec 30
      $statusCode = [int]$response.StatusCode
      break
    } catch {
      if ($attempt -eq 5) {
        throw
      }
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
  if ($statusCode -ne 200) {
    throw "Firebase Hosting returned unexpected HTTP status $statusCode."
  }
  Write-Host "PASS: Firebase Hosting returned HTTP $statusCode" -ForegroundColor Green
}

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host 'QUALITY LINE ERP DEPLOYED SUCCESSFULLY' -ForegroundColor Green
Write-Host "Application: https://$FirebaseProjectId.web.app" -ForegroundColor Green
Write-Host "Supabase: https://$SupabaseProjectRef.supabase.co" -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Green
