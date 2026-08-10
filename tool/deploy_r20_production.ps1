$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedMigrations = @(
    '20260808001500_r14_runtime_rpc_invoice_root_closure.sql',
    '20260808014500_r15_canonical_state_reconciliation.sql',
    '20260808024500_r16_persistent_canonical_state.sql'
)
$SupabaseProject = 'havlqebmnjdcwmpaaqew'
$FirebaseProject = 'kaj-erp'

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

. "$PSScriptRoot/native_cli_runner.ps1"

# Deployment runs from an installed workspace. It must not rerun pristine
# delivery checks after npm/flutter/build generated local artifacts.
Invoke-Step 'R20 installed-workspace validation and fresh web build' {
    npm run validate:r20:workspace
}

# Supabase CLI writes normal progress such as "Initialising login role..." to
# stderr. Windows PowerShell 5.1 can promote that to NativeCommandError when
# $ErrorActionPreference='Stop'. Run all production native CLIs through a real
# Process and decide success exclusively from the native exit code.
$dryRun = Invoke-NativeCaptured -Label 'Supabase migration dry run' -CommandLine 'npx supabase db push --linked --dry-run'
$dryRunText = $dryRun.Combined

$migrationMatches = [regex]::Matches($dryRunText, '20\d{12}_[A-Za-z0-9_]+\.sql')
$pending = @($migrationMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unexpected = @($pending | Where-Object { $_ -notin $ExpectedMigrations })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

$expectedPending = @($ExpectedMigrations | Where-Object { $_ -in $pending })
if ($expectedPending.Count -gt 0) {
    Invoke-NativeCaptured -Label "Push canonical runtime/state migrations to Supabase production: $($expectedPending -join ', ')" -CommandLine 'npx supabase db push --linked --yes' | Out-Null
} else {
    Write-Host 'R14/R15/R16 migrations are already applied; continuing without replay.' -ForegroundColor Yellow
}

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated build/web to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R20 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
