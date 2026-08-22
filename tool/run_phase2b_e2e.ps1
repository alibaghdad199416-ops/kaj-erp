$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$AppUrl = 'http://127.0.0.1:8080'
$CompiledUrl = "$AppUrl/main.dart.js"
$RuntimeSpec = 'playwright-tests/phase2b_sales_workflow_flutter_runtime.spec.ts'

Write-Host "KAJ ERP Phase 2B E2E runner" -ForegroundColor Cyan
Write-Host "App: $AppUrl" -ForegroundColor DarkGray

try {
  $response = Invoke-WebRequest $CompiledUrl -UseBasicParsing -TimeoutSec 10
  if ($response.StatusCode -ne 200) {
    throw "Unexpected HTTP status $($response.StatusCode)."
  }
  Write-Host 'PASS: Flutter E2E web server is reachable on 127.0.0.1:8080.' -ForegroundColor Green
} catch {
  throw "Flutter E2E web server is not reachable at $CompiledUrl. Start it first with: powershell -NoProfile -ExecutionPolicy Bypass -File tool\run_e2e_web.ps1"
}

if ([string]::IsNullOrWhiteSpace($env:E2E_ADMIN_EMAIL)) {
  $env:E2E_ADMIN_EMAIL = Read-Host 'E2E admin email'
}
if ([string]::IsNullOrWhiteSpace($env:E2E_ADMIN_EMAIL)) {
  throw 'E2E admin email is required.'
}

if ([string]::IsNullOrWhiteSpace($env:E2E_ADMIN_PASSWORD)) {
  $secure = Read-Host 'E2E admin password' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $env:E2E_ADMIN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}
if ([string]::IsNullOrWhiteSpace($env:E2E_ADMIN_PASSWORD)) {
  throw 'E2E admin password is required.'
}

Write-Host 'PASS: E2E credentials are loaded for this runner process only.' -ForegroundColor Green
Write-Host 'Running USD + IQD Phase 2B Sales lifecycle in isolated browser workers...' -ForegroundColor Cyan

$finalExitCode = 0
try {
  foreach ($currency in @('USD', 'IQD')) {
    Write-Host "`n=== Phase 2B $currency ===" -ForegroundColor Cyan
    & npx playwright test $RuntimeSpec --grep "$currency$" --reporter=list --workers=1
    $currentExitCode = $LASTEXITCODE
    if ($currentExitCode -ne 0 -and $finalExitCode -eq 0) {
      $finalExitCode = $currentExitCode
    }
  }
} finally {
  Remove-Item Env:E2E_ADMIN_PASSWORD -ErrorAction SilentlyContinue
}

exit $finalExitCode
