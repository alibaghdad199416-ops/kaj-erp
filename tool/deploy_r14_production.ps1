$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedMigration = '20260808001500_r14_runtime_rpc_invoice_root_closure.sql'
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

# Never regenerate/replace dart_defines.json here. R14 keeps the production
# Supabase/Firebase configuration byte-identical to the validated release.
Invoke-Step 'R14 Windows validation' { npm run validate:r14:windows }

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
$unexpected = @($pending | Where-Object { $_ -ne $ExpectedMigration })
if ($unexpected.Count -gt 0) {
    throw "Unexpected pending migrations. Refusing production push: $($unexpected -join ', ')"
}

if ($pending -contains $ExpectedMigration) {
    Invoke-Step 'Push R14 migration to Supabase production' {
        npx supabase db push --linked --yes
    }
} else {
    Write-Host "R14 migration is not pending; it may already be applied. Continuing without replay." -ForegroundColor Yellow
}

Invoke-Step 'List remote Supabase migrations' {
    npx supabase migration list --linked
}

# The R14 Edge Functions were not changed; do not redeploy them unnecessarily.
Invoke-Step 'Select Firebase production project' {
    npx firebase-tools use $FirebaseProject
}
Invoke-Step 'Deploy validated build/web to Firebase Hosting' {
    npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive
}

Write-Host "`nPASS R14 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host "Firebase Hosting: https://kaj-erp.web.app"
