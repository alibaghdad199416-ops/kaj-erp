$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedMigrations = @(
    '20260808043000_r22_production_accounting_consolidation.sql'
)
$SupabaseProject = 'havlqebmnjdcwmpaaqew'
$FirebaseProject = 'kaj-erp'

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
}

. "$PSScriptRoot/native_cli_runner.ps1"

Invoke-Step 'R22 installed-workspace validation and fresh web build' {
    npm run validate:r22:workspace
}

$dryRun = Invoke-NativeCaptured -Label 'Supabase R22 migration dry run' -CommandLine 'npx supabase db push --linked --dry-run'
$dryRunText = $dryRun.Combined
$migrationMatches = [regex]::Matches($dryRunText, '20\d{12}_[A-Za-z0-9_]+\.sql')
$pending = @($migrationMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unexpected = @($pending | Where-Object { $_ -notin $ExpectedMigrations })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

$expectedPending = @($ExpectedMigrations | Where-Object { $_ -in $pending })
if ($expectedPending.Count -gt 0) {
    Invoke-NativeCaptured -Label "Push R22 accounting consolidation to Supabase production: $($expectedPending -join ', ')" -CommandLine 'npx supabase db push --linked --yes' | Out-Null
} else {
    Write-Host 'R22 consolidation migration is already applied; continuing without replay.' -ForegroundColor Yellow
}

# A second dry-run is the deployment postcondition: no local migration may
# remain unapplied before Hosting is released.
$postDryRun = Invoke-NativeCaptured -Label 'Supabase post-push migration verification' -CommandLine 'npx supabase db push --linked --dry-run'
$postMatches = [regex]::Matches($postDryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$postPending = @($postMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($postPending.Count -gt 0) {
    throw "Supabase still has pending migrations after R22 push. Refusing Hosting release: $($postPending -join ', ')"
}

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated R22 build/web to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R22 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
