$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RequiredRemoteMigrations = @('20260809170859','20260809213000','20260809223000')
$FirebaseProject='kaj-erp'
function Invoke-Step { param([string]$Label,[scriptblock]$Action); Write-Host "`n==> $Label" -ForegroundColor Cyan; & $Action; if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" } }
. "$PSScriptRoot/native_cli_runner.ps1"
Invoke-Step 'R44 installed-workspace validation and fresh web build' { powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r44_workspace.ps1 }
$migrations=Invoke-NativeCaptured -Label 'Verify authoritative Supabase production migration history' -CommandLine 'npx supabase migration list --linked'
foreach($version in $RequiredRemoteMigrations){ if($migrations.Combined -notmatch [regex]::Escape($version)){ throw "Required production migration $version is missing. Refusing Firebase release." } }
Write-Host 'PASS authoritative Supabase R44 migration is present; no database replay required.' -ForegroundColor Green
Invoke-NativeCaptured -Label 'Select Firebase production project' -CommandLine "npx firebase-tools use $FirebaseProject" | Out-Null
Invoke-NativeCaptured -Label 'Deploy freshly validated build to Firebase Hosting' -CommandLine "npx firebase-tools deploy --only hosting --project $FirebaseProject --non-interactive" | Out-Null
Write-Host "`nPASS R44 production deployment" -ForegroundColor Green
