param(
  [Parameter(Mandatory=$true)][string]$UpdateZip,
  [Parameter(Mandatory=$true)][string]$TargetRoot
)
$ErrorActionPreference = 'Stop'
$expected = @(
  'supabase/migrations/20260819023000_r87_1_legacy_journal_metadata_guard.sql',
  'tool/verify_r87_1_legacy_journal_metadata_guard.py'
)
$zipPath = (Resolve-Path $UpdateZip).Path
$root = (Resolve-Path $TargetRoot).Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path (Split-Path $root -Parent) "kaj-erp-r87-1-legacy-journal-hotfix-backup-$stamp"
$temp = Join-Path $env:TEMP "kaj-r87-1-legacy-$stamp"
New-Item -ItemType Directory -Force -Path $temp | Out-Null
try {
  Expand-Archive -LiteralPath $zipPath -DestinationPath $temp -Force
  $files = Get-ChildItem -LiteralPath $temp -Recurse -File
  if ($files.Count -ne $expected.Count) { throw "Unexpected hotfix file count: $($files.Count)" }
  foreach ($rel in $expected) {
    $src = Join-Path $temp ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing expected hotfix file: $rel" }
  }
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  $manifest = Join-Path $backup 'merge-manifest.txt'
  foreach ($rel in $expected) {
    $native = $rel -replace '/', [IO.Path]::DirectorySeparatorChar
    $src = Join-Path $temp $native
    $dst = Join-Path $root $native
    if (Test-Path -LiteralPath $dst -PathType Leaf) {
      $bak = Join-Path $backup $native
      New-Item -ItemType Directory -Force -Path (Split-Path $bak -Parent) | Out-Null
      Copy-Item -LiteralPath $dst -Destination $bak -Force
      "BACKUP`t$rel" | Add-Content -LiteralPath $manifest
    } else {
      "NEW`t$rel" | Add-Content -LiteralPath $manifest
    }
  }
  foreach ($rel in $expected) {
    $native = $rel -replace '/', [IO.Path]::DirectorySeparatorChar
    $src = Join-Path $temp $native
    $dst = Join-Path $root $native
    New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $a = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash
    $b = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash
    if ($a -ne $b) { throw "SHA256 verification failed: $rel" }
  }
  Write-Host "Merged and SHA256-verified 2 files without deleting any other project file."
  Write-Host "Backup: $backup"
  Write-Host "Manifest: $manifest"
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
