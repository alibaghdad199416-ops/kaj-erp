$ErrorActionPreference = "Stop"

Set-Location C:\Projects\kaj-erp

$path = Join-Path (Get-Location) "tool\run_current_web.ps1"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " RESTORE R88-R94 LAUNCHER GATES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing file: $path"
}

$backup = "$path.backup-r89-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $path -Destination $backup -Force

Write-Host "Backup: $backup" -ForegroundColor DarkGray

$content = [System.IO.File]::ReadAllText(
    $path,
    [System.Text.Encoding]::UTF8
)

$gates = @(
    "verify_r88_phase11.py",
    "verify_r89_phase11_completion.py",
    "verify_r90_phase11_final_acceptance.py",
    "verify_r91_phase11_material_issue_acceptance.py",
    "verify_r92_comprehensive_module_audit.py",
    "verify_r93_final_closure.py",
    "verify_r94_legacy_endpoint_acl_closure.py"
)

$missing = @()

foreach ($gate in $gates) {
    if (-not $content.Contains($gate)) {
        $missing += $gate
    }
}

if ($missing.Count -eq 0) {
    Write-Host "All R88-R94 launcher gates already exist." -ForegroundColor Yellow
}
else {
    $anchor = "python -B tool/verify_project.py"
    $anchorIndex = $content.IndexOf($anchor)

    if ($anchorIndex -lt 0) {
        throw "Canonical verify_project.py anchor not found."
    }

    $builder = New-Object System.Text.StringBuilder

    [void]$builder.AppendLine(
        'Write-Host "`nRunning explicit Phase 11 R88-R94 source gates..." -ForegroundColor Cyan'
    )

    foreach ($gate in $gates) {
        if (-not $content.Contains($gate)) {
            [void]$builder.AppendLine("python -B tool/$gate")
            [void]$builder.AppendLine(
                'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'
            )
            [void]$builder.AppendLine("")
        }
    }

    $insert = $builder.ToString()

    $content =
        $content.Substring(0, $anchorIndex) +
        $insert +
        $content.Substring($anchorIndex)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $path,
        $content,
        $utf8NoBom
    )

    Write-Host "Missing R88-R94 gates restored." -ForegroundColor Green
}

Write-Host "`n=== VERIFY LAUNCHER CONTRACT ===" -ForegroundColor Cyan

$final = [System.IO.File]::ReadAllText(
    $path,
    [System.Text.Encoding]::UTF8
)

$required = @(
    "verify_r76_local_current_database.py",
    "verify_r78_complete_requirements.py",
    "verify_r79_media_export_stabilization.py",
    "verify_r88_phase11.py",
    "verify_r89_phase11_completion.py",
    "verify_r90_phase11_final_acceptance.py",
    "verify_r91_phase11_material_issue_acceptance.py",
    "verify_r92_comprehensive_module_audit.py",
    "verify_r93_final_closure.py",
    "verify_r94_legacy_endpoint_acl_closure.py",
    "verify_project.py",
    "prepare_local_current_database.ps1",
    "run_r89_r92_local_runtime_tests.py",
    "dart_defines.local.generated.json"
)

foreach ($marker in $required) {
    if (-not $final.Contains($marker)) {
        throw "Missing launcher requirement: $marker"
    }

    Write-Host "PASS: $marker" -ForegroundColor Green
}

$forbidden = @(
    "supabase db reset",
    "supabase db push",
    "supabase link"
)

foreach ($token in $forbidden) {
    if ($final.ToLowerInvariant().Contains($token)) {
        throw "Unsafe launcher command detected: $token"
    }
}

Write-Host "`n=== LAUNCHER DIFF ===" -ForegroundColor Cyan
git --no-pager diff -- tool/run_current_web.ps1

Write-Host "`n=== RUN R89 VERIFIER ===" -ForegroundColor Cyan
python -B tool/verify_r89_phase11_completion.py

if ($LASTEXITCODE -ne 0) {
    throw "R89 verifier FAILED"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " R89 LAUNCHER CONTRACT FIX PASSED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green