$ErrorActionPreference = "Stop"

Set-Location C:\Projects\kaj-erp

$path = Join-Path (Get-Location) "tool\run_current_web.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " FIX R79 LAUNCHER CONTRACT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing file: $path"
}

$content = [System.IO.File]::ReadAllText(
    $path,
    [System.Text.Encoding]::UTF8
)

# Required verifier calls.
$hasR78 = $content.Contains("verify_r78_complete_requirements.py")
$hasR79 = $content.Contains("verify_r79_media_export_stabilization.py")

if ($hasR78 -and $hasR79) {
    Write-Host "R78/R79 calls already exist. No patch required." -ForegroundColor Yellow
}
else {
    $anchor = "python -B tool/verify_project.py"

    $anchorIndex = $content.IndexOf($anchor)

    if ($anchorIndex -lt 0) {
        throw "Could not find canonical verify_project.py launcher anchor."
    }

    $insert = @'
Write-Host "`nRunning R78 complete-requirements preflight..." -ForegroundColor Cyan
python -B tool/verify_r78_complete_requirements.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`nRunning R79 media/export stabilization preflight..." -ForegroundColor Cyan
python -B tool/verify_r79_media_export_stabilization.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

'@

    # Insert immediately before canonical verify_project.py.
    $content =
        $content.Substring(0, $anchorIndex) +
        $insert +
        $content.Substring($anchorIndex)

    # Update stale launcher description only if present.
    $content = $content.Replace(
        "Running canonical current source verification (through R95)...",
        "Running canonical current source verification (through R97)..."
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $path,
        $content,
        $utf8NoBom
    )

    Write-Host "Launcher patched successfully." -ForegroundColor Green
}

Write-Host "`n=== VERIFY REQUIRED CONTENT ===" -ForegroundColor Cyan

$final = [System.IO.File]::ReadAllText(
    $path,
    [System.Text.Encoding]::UTF8
)

$required = @(
    "verify_r76_local_current_database.py",
    "verify_r78_complete_requirements.py",
    "verify_r79_media_export_stabilization.py",
    "verify_project.py",
    "prepare_local_current_database.ps1",
    "dart_defines.local.generated.json"
)

foreach ($item in $required) {
    if (-not $final.Contains($item)) {
        throw "Missing launcher requirement: $item"
    }

    Write-Host "PASS: $item" -ForegroundColor Green
}

if ($final.ToLowerInvariant().Contains("db push")) {
    throw "Unsafe db push reference detected."
}

Write-Host "`n=== GIT DIFF ===" -ForegroundColor Cyan
git diff -- tool/run_current_web.ps1

Write-Host "`n=== RUN R79 VERIFIER ===" -ForegroundColor Cyan
python -B tool/verify_r79_media_export_stabilization.py

if ($LASTEXITCODE -ne 0) {
    throw "R79 verifier FAILED"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " R79 LAUNCHER FIX PASSED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green