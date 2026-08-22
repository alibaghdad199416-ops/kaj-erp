$ErrorActionPreference = "Stop"

Set-Location C:\Projects\kaj-erp

$path = Join-Path (Get-Location) "tool\verify_r88_phase11.py"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " FIX R88 VERIFIER FOR R95 CONTRACT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing file: $path"
}

$backup = "$path.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $path -Destination $backup -Force

Write-Host "Backup: $backup" -ForegroundColor DarkGray

$content = [System.IO.File]::ReadAllText(
    $path,
    [System.Text.Encoding]::UTF8
)

$old = @"
    'granular client actions': ('lib/features/settings/access/controllers/access_controller.dart', ['actions.restrict', 'hasLegacy &&']),
"@

$new = @"
    'granular client actions': (
        'lib/features/settings/access/controllers/access_controller.dart',
        ['PermissionContract.hasRestrictedActions', 'PermissionContract.canPerformAction'],
    ),
    'canonical granular action contract': (
        'lib/core/security/permission_contract.dart',
        [
            'actionRestriction(resource)',
            'hasRestrictedActions(permissionCodes, resource)',
            'permissionCodes.contains(action(resource, actionName))',
            'permissionCodes.contains(legacyPermission)',
        ],
    ),
"@

if (-not $content.Contains($old)) {
    Write-Host "" -ForegroundColor Yellow
    Write-Host "Expected old R88 verifier marker was not found." -ForegroundColor Red
    Write-Host "No file was changed." -ForegroundColor Yellow
    throw "R88 verifier source drift detected"
}

$content = $content.Replace($old, $new)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

[System.IO.File]::WriteAllText(
    $path,
    $content,
    $utf8NoBom
)

Write-Host "`n=== VERIFY PATCHED MARKERS ===" -ForegroundColor Cyan

$patched = [System.IO.File]::ReadAllText(
    $path,
    [System.Text.Encoding]::UTF8
)

$required = @(
    "PermissionContract.hasRestrictedActions",
    "PermissionContract.canPerformAction",
    "lib/core/security/permission_contract.dart",
    "actionRestriction(resource)",
    "hasRestrictedActions(permissionCodes, resource)",
    "permissionCodes.contains(action(resource, actionName))",
    "permissionCodes.contains(legacyPermission)"
)

foreach ($marker in $required) {
    if (-not $patched.Contains($marker)) {
        throw "Missing patched R88 marker: $marker"
    }

    Write-Host "PASS: $marker" -ForegroundColor Green
}

if ($patched.Contains("hasLegacy &&")) {
    throw "Obsolete hasLegacy verifier marker still exists."
}

Write-Host "`n=== R88 DIFF ===" -ForegroundColor Cyan
git --no-pager diff -- tool/verify_r88_phase11.py

Write-Host "`n=== RUN R88 VERIFIER ===" -ForegroundColor Cyan
python -B tool/verify_r88_phase11.py

if ($LASTEXITCODE -ne 0) {
    throw "R88 verifier FAILED"
}

Write-Host "`n=== R95 PERMISSION CONTRACT TEST ===" -ForegroundColor Cyan
flutter test test/r95_enterprise_permission_contract_test.dart

if ($LASTEXITCODE -ne 0) {
    throw "R95 permission contract regression test FAILED"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " R88 VERIFIER CONTRACT FIX PASSED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green