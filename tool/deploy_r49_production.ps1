$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$SupabaseProject = 'havlqebmnjdcwmpaaqew'
$FirebaseProject = 'kaj-erp'
$MigrationDirectory = Join-Path $PSScriptRoot '..\supabase\migrations'

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
}

function Get-LocalMigrationNames {
    if (-not (Test-Path -LiteralPath $MigrationDirectory)) {
        throw "Supabase migration directory not found: $MigrationDirectory"
    }
    return @(
        Get-ChildItem -LiteralPath $MigrationDirectory -File -Filter '*.sql' |
            Where-Object { $_.Name -match '^20\d{12}_[A-Za-z0-9_]+\.sql$' } |
            Select-Object -ExpandProperty Name |
            Sort-Object -Unique
    )
}

function Get-PendingMigrationNames {
    param([string]$Output)
    $matches = [regex]::Matches($Output, '20\d{12}_[A-Za-z0-9_]+\.sql')
    return @($matches | ForEach-Object { $_.Value } | Sort-Object -Unique)
}

. "$PSScriptRoot/native_cli_runner.ps1"

$localMigrations = Get-LocalMigrationNames
if ($localMigrations.Count -eq 0) {
    throw 'No local Supabase migrations were discovered; refusing deployment.'
}

Invoke-Step 'Authoritative workspace verification' {
    npm run verify:workspace
}

Invoke-Step 'Fresh validated web build' {
    npm run build:web
}

$dryRun = Invoke-NativeCaptured -Label 'Supabase migration dry run' -CommandLine 'npx supabase db push --linked --dry-run'
$pending = Get-PendingMigrationNames -Output $dryRun.Combined

$unknownPending = @($pending | Where-Object { $_ -notin $localMigrations })
if ($unknownPending.Count -gt 0) {
    throw "Supabase reports migrations that are not present in this repository. Refusing production push: $($unknownPending -join ', ')"
}

$missingFromDryRun = @($localMigrations | Where-Object { $_ -in $pending })
if ($missingFromDryRun.Count -gt 0) {
    Write-Host "Discovered pending repository migrations: $($missingFromDryRun -join ', ')" -ForegroundColor Yellow
    Invoke-NativeCaptured -Label "Push pending repository migrations" -CommandLine 'npx supabase db push --linked --yes' | Out-Null
} else {
    Write-Host 'No repository migrations are pending on the linked Supabase target.' -ForegroundColor Yellow
}

$postDryRun = Invoke-NativeCaptured -Label 'Supabase post-push migration verification' -CommandLine 'npx supabase db push --linked --dry-run'
$postPending = Get-PendingMigrationNames -Output $postDryRun.Combined
if ($postPending.Count -gt 0) {
    throw "Supabase still has pending migrations after the push. Refusing Hosting release: $($postPending -join ', ')"
}

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated web build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS production deployment orchestration" -ForegroundColor Green
Write-Host "Canonical application version: 22.9.8+229008"
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
