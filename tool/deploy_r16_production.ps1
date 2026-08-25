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

# Never regenerate/replace dart_defines.json here. R16 keeps the production
# Supabase/Firebase configuration byte-identical to the validated release.
Invoke-Step 'R16 Windows validation' { npm run validate:r16:windows }

Write-Host "`n==> Supabase migration dry run" -ForegroundColor Cyan
$dryRunLines = & npx supabase db push --linked --dry-run 2>&1
$dryRunExit = $LASTEXITCODE
$dryRunText = ($dryRunLines | Out-String)
Write-Host $dryRunText
if ($dryRunExit -ne 0) {
    throw "Supabase dry run failed with exit code $dryRunExit"
}

$migrationMatches = [regex]::Matches($dryRunText, '20\d{12}_[A-Za-z0-9_]+\.sql')
$pending = @($migrationMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
$unexpected = @($pending | Where-Object { $_ -notin $ExpectedMigrations })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

$expectedPending = @($ExpectedMigrations | Where-Object { $_ -in $pending })
if ($expectedPending.Count -gt 0) {
    # R14/R15 may still be pending on a production database currently running R13.
    # Supabase applies migrations in timestamp order: R14 -> R15 -> R16.
    Invoke-Step "Push canonical runtime/state migrations to Supabase production: $($expectedPending -join ', ')" {
        npx supabase db push --linked --yes
    }
} else {
    Write-Host "R14/R15/R16 migrations are not pending; they may already be applied. Continuing without replay." -ForegroundColor Yellow
}

Invoke-Step 'List remote Supabase migrations' {
    npx supabase migration list --linked
}

# The R16 Edge Functions were not changed; do not redeploy them unnecessarily.
Invoke-Step 'Select Firebase production project' {
    npx firebase-tools use $FirebaseProject
}
Invoke-Step 'Deploy validated build/web to Firebase Hosting' {
    npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive
}

Write-Host "`nPASS R16 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host "Firebase Hosting: https://kaj-erp.web.app"
