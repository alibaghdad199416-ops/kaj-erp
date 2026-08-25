$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedMigrations = @(
    '20260808052709_r23_canonical_vehicle_lifecycle_and_phase26_contract.sql',
    '20260808062444_r23_cashbox_ledger_alias_contract.sql',
    '20260808062519_r23_deterministic_cashbox_rebinding.sql',
    '20260808063806_r23_cashbox_rebind_lock_safety.sql'
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

Invoke-Step 'R23 installed-workspace validation and fresh web build' {
    npm run validate:r23:workspace
}

$dryRun = Invoke-NativeCaptured -Label 'Supabase R23 migration dry run' -CommandLine 'npx supabase db push --linked --dry-run'
$matches = [regex]::Matches($dryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$pending = @($matches | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unexpected = @($pending | Where-Object { $_ -notin $ExpectedMigrations })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

$expectedPending = @($ExpectedMigrations | Where-Object { $_ -in $pending })
if ($expectedPending.Count -gt 0) {
    Invoke-NativeCaptured -Label "Push R23 migrations to Supabase production: $($expectedPending -join ', ')" -CommandLine 'npx supabase db push --linked --yes' | Out-Null
} else {
    Write-Host 'R23 migrations are already applied; continuing without replay.' -ForegroundColor Yellow
}

$postDryRun = Invoke-NativeCaptured -Label 'Supabase post-push migration verification' -CommandLine 'npx supabase db push --linked --dry-run'
$postMatches = [regex]::Matches($postDryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$postPending = @($postMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($postPending.Count -gt 0) {
    throw "Supabase still has pending migrations after R23 push. Refusing Hosting release: $($postPending -join ', ')"
}

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated web build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R23 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
