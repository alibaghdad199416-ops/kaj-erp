$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command
  )

  Write-Host "`n> $Command" -ForegroundColor Cyan
  Invoke-Expression $Command
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command"
  }
}

Write-Host 'Quality Line ERP 22.8.1 final release check' -ForegroundColor Cyan
Invoke-Checked 'npm ci'
Invoke-Checked 'flutter clean'
Invoke-Checked 'flutter pub get'
Invoke-Checked 'npm run verify:final'
Invoke-Checked 'flutter analyze --fatal-infos --fatal-warnings'
Invoke-Checked 'npm run test'
Invoke-Checked 'npm run build:web'
Write-Host "`nFINAL RELEASE CHECK PASSED" -ForegroundColor Green
