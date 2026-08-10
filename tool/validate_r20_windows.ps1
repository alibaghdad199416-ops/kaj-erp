$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

$GeneratedPaths = @('.dart_tool', 'node_modules', 'build', '.flutter-plugins-dependencies')
$present = @($GeneratedPaths | Where-Object { Test-Path $_ })
if ($present.Count -eq 0) {
    Invoke-Step 'verify:delivery (pristine extracted package)' { npm run verify:delivery }
} else {
    Write-Host "`nINFO: Installed workspace detected ($($present -join ', '))." -ForegroundColor Yellow
    Write-Host 'Delivery cleanliness is a property of the pristine ZIP and is not re-tested after dependency/build generation.' -ForegroundColor Yellow
}

Invoke-Step 'R20 installed-workspace release validation' { npm run validate:r20:workspace }
Write-Host "`nPASS R20 Windows release validation" -ForegroundColor Green
