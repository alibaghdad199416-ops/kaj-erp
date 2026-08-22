param(
  [string]$UpdateZip = ".\kaj-erp-r87-r86-fixture-hotfix.zip",
  [string]$TargetRoot = "C:\Projects\kaj-erp"
)
$ErrorActionPreference = 'Stop'
$TargetRoot = (Resolve-Path $TargetRoot).Path
$UpdateZip = (Resolve-Path $UpdateZip).Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "${TargetRoot}-r87-r86-fixture-hotfix-backup-$stamp"
$temp = Join-Path $env:TEMP "kaj-r87-r86-fixture-$stamp"
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
  Expand-Archive -LiteralPath $UpdateZip -DestinationPath $temp -Force
  $files = Get-ChildItem -Path $temp -File -Recurse
  if ($files.Count -ne 1) { throw "Expected exactly 1 hotfix file, found $($files.Count)." }
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($temp.Length).TrimStart('\','/')
    $dest = Join-Path $TargetRoot $rel
    if (Test-Path $dest) {
      $bak = Join-Path $backup $rel
      New-Item -ItemType Directory -Path (Split-Path $bak) -Force | Out-Null
      Copy-Item -LiteralPath $dest -Destination $bak -Force
    }
  }
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($temp.Length).TrimStart('\','/')
    $dest = Join-Path $TargetRoot $rel
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    if ((Get-FileHash $f.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $dest -Algorithm SHA256).Hash) { throw "SHA256 mismatch: $rel" }
  }
  Write-Host "Merged and SHA256-verified 1 file without deleting any other project file."
  Write-Host "Backup: $backup"
} finally {
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
