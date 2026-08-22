param(
  [Parameter(Mandatory=$true)][string]$UpdateZip,
  [Parameter(Mandatory=$true)][string]$TargetRoot
)
$ErrorActionPreference = 'Stop'
$TargetRoot = [IO.Path]::GetFullPath($TargetRoot)
$UpdateZip = [IO.Path]::GetFullPath($UpdateZip)
if (-not (Test-Path -LiteralPath $UpdateZip -PathType Leaf)) { throw "Update ZIP not found: $UpdateZip" }
if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) { throw "Target root not found: $TargetRoot" }
$expected = @{
  'supabase/tests/verify_r58_maintenance_item_accounting_runtime.sql' = 'b1a430c18b3ef8bfc731331f1d6ae7a8f5b14847afbc93500af0b7b8fd1107b0'
  'tool/verify_r58_maintenance_item_accounting.py' = 'ac0cc6d67f4c967616f6290dea38530d94f5b1d2915c1cffca2f5355a0519361'
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('kaj-r58-hotfix-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  Expand-Archive -LiteralPath $UpdateZip -DestinationPath $temp -Force
  $files = @(Get-ChildItem -LiteralPath $temp -Recurse -File)
  if ($files.Count -ne 2) { throw "Expected exactly 2 files in hotfix ZIP; found $($files.Count)." }
  foreach ($rel in $expected.Keys) {
    $src = Join-Path $temp ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing expected hotfix file: $rel" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash.ToLowerInvariant()
    if ($actual -ne $expected[$rel]) { throw "Hotfix SHA256 mismatch before merge: $rel" }
  }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $parent = Split-Path -Parent $TargetRoot
  $backup = Join-Path $parent ('kaj-erp-r87-r58-current-ownership-test-hotfix-backup-' + $stamp)
  New-Item -ItemType Directory -Path $backup | Out-Null
  $manifest = Join-Path $backup 'merge-manifest.txt'
  foreach ($rel in $expected.Keys) {
    $dest = Join-Path $TargetRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
      $bak = Join-Path $backup ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
      New-Item -ItemType Directory -Path (Split-Path -Parent $bak) -Force | Out-Null
      Copy-Item -LiteralPath $dest -Destination $bak -Force
      Add-Content -LiteralPath $manifest -Value ("BACKUP " + $rel)
    } else {
      Add-Content -LiteralPath $manifest -Value ("NEW " + $rel)
    }
  }
  foreach ($rel in $expected.Keys) {
    $src = Join-Path $temp ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    $dest = Join-Path $TargetRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dest -Force
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash.ToLowerInvariant()
    if ($actual -ne $expected[$rel]) { throw "Post-merge SHA256 mismatch: $rel" }
  }
  Write-Host 'Merged and SHA256-verified 2 files without deleting any other project file.'
  Write-Host ('Backup: ' + $backup)
  Write-Host ('Manifest: ' + $manifest)
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
