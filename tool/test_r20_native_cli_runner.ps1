$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/native_cli_runner.ps1"

$ok = Invoke-NativeCaptured -Label 'R20 stderr zero-exit probe' -CommandLine 'echo R20_STDERR_ZERO_EXIT 1>&2 & exit /b 0'
if ($ok.ExitCode -ne 0 -or $ok.StdErr -notmatch 'R20_STDERR_ZERO_EXIT') {
    throw 'R20 native runner did not preserve zero-exit stderr correctly.'
}

$nonZeroRejected = $false
try {
    Invoke-NativeCaptured -Label 'R20 non-zero exit probe' -CommandLine 'echo R20_EXPECTED_FAILURE 1>&2 & exit /b 7' | Out-Null
} catch {
    if ($_.Exception.Message -match 'native exit code 7') {
        $nonZeroRejected = $true
    } else {
        throw
    }
}
if (-not $nonZeroRejected) {
    throw 'R20 native runner did not reject native exit code 7.'
}

Write-Host 'PASS R20 native CLI stderr/exit-code self-test' -ForegroundColor Green
