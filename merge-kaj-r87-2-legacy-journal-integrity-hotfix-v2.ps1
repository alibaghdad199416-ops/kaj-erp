param(
  [Parameter(Mandatory=$true)][string]$UpdateZip,
  [Parameter(Mandatory=$true)][string]$TargetRoot
)

$ErrorActionPreference = 'Stop'

$expected = [ordered]@{
  'supabase/migrations/20260819023800_r87_2_legacy_journal_integrity_metadata_guard.sql' = '20883461196cc308dd2ca867f7f9a2abcea01b56f1214cc7863d2db0130efb34'
  'tool/verify_r87_2_legacy_journal_integrity_metadata_guard.py' = '5cff73ea5591a8e16a9af14a4e8edf5cbc873cb7b4789968f67ec0acdf8e48ab'
}

$zipPath = (Resolve-Path -LiteralPath $UpdateZip).Path
$root = (Resolve-Path -LiteralPath $TargetRoot).Path
$temp = Join-Path $env:TEMP ('kaj-r87-2-hotfix-' + [guid]::NewGuid().ToString('N'))
$backup = $root + '-r87-2-legacy-journal-integrity-hotfix-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$manifest = Join-Path $backup 'merge-manifest.txt'

try {
  New-Item -ItemType Directory -Path $temp -Force | Out-Null
  Expand-Archive -LiteralPath $zipPath -DestinationPath $temp -Force

  $files = @(Get-ChildItem -LiteralPath $temp -File -Recurse)
  if ($files.Count -ne $expected.Count) {
    throw "Unexpected hotfix file count: expected $($expected.Count), found $($files.Count)."
  }

  foreach ($relative in $expected.Keys) {
    $nativeRelative = $relative.Replace('/', [string][IO.Path]::DirectorySeparatorChar)
    $source = Join-Path $temp $nativeRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Expected hotfix file is missing: $relative"
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash.ToLowerInvariant()
    if ($hash -ne $expected[$relative]) {
      throw "SHA256 mismatch before merge: $relative"
    }
  }

  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  $manifestLines = New-Object System.Collections.Generic.List[string]

  foreach ($relative in $expected.Keys) {
    $nativeRelative = $relative.Replace('/', [string][IO.Path]::DirectorySeparatorChar)
    $target = Join-Path $root $nativeRelative
    if (Test-Path -LiteralPath $target -PathType Leaf) {
      $backupTarget = Join-Path $backup $nativeRelative
      New-Item -ItemType Directory -Path (Split-Path -Parent $backupTarget) -Force | Out-Null
      Copy-Item -LiteralPath $target -Destination $backupTarget -Force
      $manifestLines.Add("BACKUP $relative")
    } else {
      $manifestLines.Add("NEW $relative")
    }
  }

  $manifestLines | Set-Content -LiteralPath $manifest -Encoding UTF8

  foreach ($relative in $expected.Keys) {
    $nativeRelative = $relative.Replace('/', [string][IO.Path]::DirectorySeparatorChar)
    $source = Join-Path $temp $nativeRelative
    $target = Join-Path $root $nativeRelative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force

    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant()
    if ($hash -ne $expected[$relative]) {
      throw "SHA256 mismatch after merge: $relative"
    }
  }

  Write-Host "Merged and SHA256-verified $($expected.Count) files without deleting any other project file."
  Write-Host "Backup: $backup"
  Write-Host "Manifest: $manifest"
}
finally {
  if (Test-Path -LiteralPath $temp) {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
