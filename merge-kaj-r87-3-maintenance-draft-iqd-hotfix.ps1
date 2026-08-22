param(
  [Parameter(Mandatory = $true)][string]$UpdateZip,
  [Parameter(Mandatory = $true)][string]$TargetRoot
)

$ErrorActionPreference = 'Stop'
$expected = @(
  'lib/features/maintenance/pages/add_maintenance_order_page.dart',
  'lib/features/maintenance/pages/maintenance_order_details_dialog.dart',
  'test/features/maintenance/r87_3_maintenance_draft_iqd_regression_test.dart',
  'tool/verify_r87_3_maintenance_draft_iqd_regression.py'
)
$expectedHashes = @{
  'lib/features/maintenance/pages/add_maintenance_order_page.dart' = '8e9e3c5909440670845667957d0f61f994133013af27344ca7b25e5d2a85f38a'
  'lib/features/maintenance/pages/maintenance_order_details_dialog.dart' = '2a2c9cddd15cdb30ab2651851706d2519b21c225980436de44038ec6f888fec9'
  'test/features/maintenance/r87_3_maintenance_draft_iqd_regression_test.dart' = 'b727b0d6b2da3e209e1eaabfaf28ac867cc75fb35f741f60eb24b96fb7e22a6c'
  'tool/verify_r87_3_maintenance_draft_iqd_regression.py' = '2331ba62828fcd58a1ee773be4c5b7453f951028115941733cb062997cb881bf'
}

$zipPath = (Resolve-Path -LiteralPath $UpdateZip).Path
$targetPath = (Resolve-Path -LiteralPath $TargetRoot).Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path (Split-Path -Parent $targetPath) ("kaj-erp-r87-3-maintenance-draft-iqd-hotfix-backup-$stamp")
$temp = Join-Path $env:TEMP ("kaj-r87-3-$stamp")
New-Item -ItemType Directory -Path $temp -Force | Out-Null
New-Item -ItemType Directory -Path $backup -Force | Out-Null

try {
  Expand-Archive -LiteralPath $zipPath -DestinationPath $temp -Force

  foreach ($rel in $expected) {
    $source = Join-Path $temp ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Hotfix is missing expected file: $rel"
    }
    $actualHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHashes[$rel]) {
      throw "SHA256 mismatch before merge: $rel"
    }
  }

  $files = Get-ChildItem -LiteralPath $temp -Recurse -File
  if ($files.Count -ne $expected.Count) {
    throw "Unexpected hotfix file count. Expected $($expected.Count), found $($files.Count)."
  }

  # Back up all existing targets before replacing the first one.
  foreach ($rel in $expected) {
    $target = Join-Path $targetPath ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $target -PathType Leaf) {
      $backupTarget = Join-Path $backup ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
      New-Item -ItemType Directory -Path (Split-Path -Parent $backupTarget) -Force | Out-Null
      Copy-Item -LiteralPath $target -Destination $backupTarget -Force
    }
  }

  foreach ($rel in $expected) {
    $source = Join-Path $temp ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    $target = Join-Path $targetPath ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHashes[$rel]) {
      throw "SHA256 mismatch after merge: $rel"
    }
  }

  $manifest = Join-Path $backup 'merge-manifest.txt'
  @(
    'KAJ ERP R87.3 Maintenance Draft/IQD Hotfix',
    "Applied: $(Get-Date -Format o)",
    "Target: $targetPath",
    "Source ZIP: $zipPath",
    '',
    'Files:'
  ) + $expected | Set-Content -LiteralPath $manifest -Encoding UTF8

  Write-Host "Merged and SHA256-verified $($expected.Count) files without deleting any other project file."
  Write-Host "Backup: $backup"
  Write-Host "Manifest: $manifest"
}
finally {
  if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
