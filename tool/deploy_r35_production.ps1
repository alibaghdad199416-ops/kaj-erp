$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RequiredRemoteMigrations = @(
  '20260808052709', # R23 canonical vehicle lifecycle
  '20260808062444', # R23 cashbox ledger alias
  '20260808062519', # R23 deterministic rebinding
  '20260808063806', # R23 lock safety
  '20260808085021', # R24 runtime accounting/payment/performance
  '20260808085451', # R24 journal currency
  '20260808090027', # R24 sales immutable logistics
  '20260808090250', # R24 FIFO alias
  '20260808091343', # R24 partner dual ledger
  '20260808092239', # R24 runtime finance/UI closure applied directly in Production
  '20260808115929', # R25 functional runtime closure
  '20260808130614', # R26 runtime data/UI contract closure
  '20260808161756', # R27 complete functional closure
  '20260808162550', # R27 cashbox concurrency/readback repair
  '20260808165235', # R28 complete runtime closure
  '20260808165940', # R28 cloud command contract
  '20260809122052'  # R35 runtime/UI/opportunity/maintenance closure
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

Invoke-Step 'R35 installed-workspace validation and fresh web build' {
  powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r35_workspace.ps1
}

# R23-R28 database changes are already applied to the production project.
# Some were applied through the Supabase API and therefore have authoritative
# remote version timestamps that differ from the original local filenames.
# Never replay them with db push. Verify the production history instead.
$migrations = Invoke-NativeCaptured -Label 'Verify authoritative Supabase production migration history' -CommandLine 'npx supabase migration list --linked'
foreach ($version in $RequiredRemoteMigrations) {
  if ($migrations.Combined -notmatch [regex]::Escape($version)) {
    throw "Required production migration $version is missing. Refusing Firebase release."
  }
}
Write-Host 'PASS authoritative Supabase migrations are present; no database replay required.' -ForegroundColor Green

Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null

Write-Host "`nPASS R35 production deployment" -ForegroundColor Green
Write-Host "Supabase project: $SupabaseProject (verified, not replayed)"
Write-Host 'Firebase Hosting: https://kaj-erp.web.app'
