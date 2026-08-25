$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-QualityCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    Invoke-QualityCommand 'npm ci' { npm ci }
    Invoke-QualityCommand 'flutter pub get' { flutter pub get }

    # Normalize every Dart source before the no-change formatting gate.
    Invoke-QualityCommand 'dart format' { npm run format }

    # verify:all includes database/source/localization, R8/R9/R10, package and deployment gates.
    Invoke-QualityCommand 'verify:all' { npm run verify:all }
    Invoke-QualityCommand 'format:check' { npm run format:check }
    Invoke-QualityCommand 'flutter analyze' { npm run analyze }
    Invoke-QualityCommand 'flutter test' { npm run test }
    Invoke-QualityCommand 'Flutter web release build' { npm run build:web }

    Write-Host "`nPASS R10 Windows release validation" -ForegroundColor Green
    Write-Host 'The source is formatted and all verification/analyzer/test/build gates passed.' -ForegroundColor Green
}
finally {
    Pop-Location
}
