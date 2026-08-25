$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedMigrations = @(
    '20260808085021_r24_runtime_accounting_payment_performance_closure.sql'
    '20260808085451_r24_journal_currency_invoice_closure.sql'
    '20260808090027_r24_sales_invoice_immutable_logistics_closure.sql'
    '20260808090250_r24_sales_fifo_alias_closure.sql'
    '20260808091343_r24_partner_dual_ledger_canonical_closure.sql'
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

Invoke-Step 'R24 installed-workspace validation and fresh web build' {
    npm run validate:r24:workspace
}

$dryRun = Invoke-NativeCaptured -Label 'Supabase R24 migration dry run' -CommandLine 'npx supabase db push --linked --dry-run'
$matches = [regex]::Matches($dryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$pending = @($matches | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unexpected = @($pending | Where-Object { $_ -notin $ExpectedMigrations })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

$expectedPending = @($ExpectedMigrations | Where-Object { $_ -in $pending })
if ($expectedPending.Count -gt 0) {
    Invoke-NativeCaptured -Label "Push R24 migrations to Supabase production: $($expectedPending -join ', ')" -CommandLine 'npx supabase db push --linked --yes' | Out-Null
} else {
    Write-Host 'R24 migrations are already applied; continuing without replay.' -ForegroundColor Yellow
}

$postDryRun = Invoke-NativeCaptured -Label 'Supabase post-push migration verification' -CommandLine 'npx supabase db push --linked --dry-run'
$postMatches = [regex]::Matches($postDryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$postPending = @($postMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($postPending.Count -gt 0) {
    throw "Supabase still has pending migrations after R24 push. Refusing Hosting release: $($postPending -join ', ')"
}

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated web build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R24 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
