$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

# The guard executes normal chronological db push by default. It permits
# --include-all only for the exact R57 compatibility-history gap, after a
# bounded dry-run proves that no unexpected historical migration is pending.
Invoke-NativeCaptured `
    -Label 'Guarded Supabase migration preflight and push' `
    -CommandLine 'python -B tool/guarded_supabase_db_push.py --linked --yes' | Out-Null

Invoke-NativeCaptured -Label 'List remote Supabase migrations' -CommandLine 'npx supabase migration list --linked' | Out-Null
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated web build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R49 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
