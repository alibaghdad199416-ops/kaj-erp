$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE" }
}
Invoke-Step 'verify:delivery (pristine extracted package)' { npm run verify:delivery }
Invoke-Step 'R22 installed-workspace release validation' { npm run validate:r22:workspace }
Write-Host "`nPASS R22 Windows release validation" -ForegroundColor Green
