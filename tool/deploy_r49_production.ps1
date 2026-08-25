$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedMigrations = @(
    '20260810021000_r49_crm_business_reference_closure.sql'
    '20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql'
    '20260810031000_r49_master_business_references.sql'
    '20260810040000_r49_invoice_idempotency_quality_closure.sql'
    '20260810050000_r49_installment_currency_fixed_asset_boundary.sql'
    '20260810060000_r49_product_identity_accounting_integrity.sql'
    '20260810070000_r49_permission_scope_integrity.sql'
    '20260810080000_r49_independent_delivery_search_traceability.sql'
    '20260810090000_r49_focused_final_permission_runtime_closure.sql'
    '20260810100000_r49_financial_subledger_currency_integrity.sql'
    '20260810110000_r49_accounting_profit_installment_surface_closure.sql'
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

Invoke-Step 'R49 installed-workspace validation and fresh web build' {
    powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r49_workspace.ps1
}

$dryRun = Invoke-NativeCaptured -Label 'Supabase R49 migration dry run' -CommandLine 'npx supabase db push --linked --dry-run'
$matches = [regex]::Matches($dryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$pending = @($matches | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unexpected = @($pending | Where-Object { $_ -notin $ExpectedMigrations })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

$expectedPending = @($ExpectedMigrations | Where-Object { $_ -in $pending })
if ($expectedPending.Count -gt 0) {
    Invoke-NativeCaptured -Label "Push R49 migrations to Supabase production: $($expectedPending -join ', ')" -CommandLine 'npx supabase db push --linked --yes' | Out-Null
} else {
    Write-Host 'R49 migrations are already applied; continuing without replay.' -ForegroundColor Yellow
}

$postDryRun = Invoke-NativeCaptured -Label 'Supabase post-push migration verification' -CommandLine 'npx supabase db push --linked --dry-run'
$postMatches = [regex]::Matches($postDryRun.Combined, '20\d{12}_[A-Za-z0-9_]+\.sql')
$postPending = @($postMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($postPending.Count -gt 0) {
    throw "Supabase still has pending migrations after R49 push. Refusing Hosting release: $($postPending -join ', ')"
}

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated web build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R49 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
