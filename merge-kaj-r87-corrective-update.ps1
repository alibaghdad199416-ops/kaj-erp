[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$UpdateZip,
  [string]$TargetRoot = 'C:\Projects\kaj-erp'
)

$ErrorActionPreference = 'Stop'
$ExpectedFileCount = 44

function Get-NormalizedFullPath([string]$Path) {
  return [System.IO.Path]::GetFullPath($Path).TrimEnd([char]92)
}

function Assert-ChildPath([string]$Root, [string]$Candidate, [string]$Label) {
  $rootFull = Get-NormalizedFullPath $Root
  $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
  $prefix = $rootFull + [char]92
  if (-not $candidateFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label escapes the allowed root: $candidateFull"
  }
  return $candidateFull
}

$UpdateZip = (Resolve-Path -LiteralPath $UpdateZip).Path
$TargetRoot = Get-NormalizedFullPath $TargetRoot
if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) {
  throw "Target project does not exist: $TargetRoot"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$parent = Split-Path -Parent $TargetRoot
$backupRoot = Join-Path $parent "kaj-erp-r87-backup-$stamp"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "kaj-erp-r87-$stamp-$PID"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$archive = $null
try {
  # Validate every archive path BEFORE extracting anything.
  $archive = [System.IO.Compression.ZipFile]::OpenRead($UpdateZip)
  $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) })
  if ($entries.Count -ne $ExpectedFileCount) {
    throw "Unexpected update package: expected $ExpectedFileCount files, found $($entries.Count)."
  }

  $seen = @{}
  $plan = @()
  foreach ($entry in $entries) {
    $relative = $entry.FullName.Replace([char]47, [char]92).TrimStart([char]92)
    if ([string]::IsNullOrWhiteSpace($relative) -or [System.IO.Path]::IsPathRooted($relative)) {
      throw "Unsafe ZIP path: $($entry.FullName)"
    }

    $segments = @($relative.Split([char]92))
    if ($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' -or $_.Contains(':') }) {
      throw "Unsafe ZIP path segment: $($entry.FullName)"
    }

    $key = $relative.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
      throw "Duplicate ZIP path (case-insensitive): $relative"
    }
    $seen[$key] = $true

    $source = Assert-ChildPath $tempRoot (Join-Path $tempRoot $relative) 'ZIP extraction path'
    $destination = Assert-ChildPath $TargetRoot (Join-Path $TargetRoot $relative) 'Target path'

    $plan += [pscustomobject]@{
      Relative = $relative
      Entry = $entry
      Source = $source
      Destination = $destination
      Exists = Test-Path -LiteralPath $destination -PathType Leaf
    }
  }

  # Extract only the already-validated entries to the private temp directory.
  foreach ($item in $plan) {
    $sourceDir = Split-Path -Parent $item.Source
    New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($item.Entry, $item.Source, $true)
  }
  $archive.Dispose()
  $archive = $null

  # Compute all incoming hashes before touching the target project.
  foreach ($item in $plan) {
    $item | Add-Member -NotePropertyName IncomingSha256 -NotePropertyValue ((Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash.ToLowerInvariant())
  }

  # Phase 1: back up EVERY existing destination before replacing ANY file.
  New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
  foreach ($item in $plan | Where-Object { $_.Exists }) {
    $backupPath = Assert-ChildPath $backupRoot (Join-Path $backupRoot $item.Relative) 'Backup path'
    $backupDir = Split-Path -Parent $backupPath
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -LiteralPath $item.Destination -Destination $backupPath -Force
  }

  $manifestPath = Join-Path $backupRoot 'merge-manifest.txt'
  @(
    'KAJ ERP R87 Corrective Update Merge Manifest'
    "Target: $TargetRoot"
    "Update ZIP: $UpdateZip"
    "Created: $(Get-Date -Format o)"
    "Files: $($plan.Count)"
    ''
    $plan | ForEach-Object {
      "{0}`t{1}`tSHA256={2}" -f ($(if ($_.Exists) {'REPLACE'} else {'NEW'})), $_.Relative, $_.IncomingSha256
    }
  ) | Set-Content -LiteralPath $manifestPath -Encoding UTF8

  # Phase 2: overlay only the validated files. No reset, clean, delete, or repository-wide copy.
  foreach ($item in $plan) {
    $destDir = Split-Path -Parent $item.Destination
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force
  }

  # Verify the copied bytes before reporting success.
  $mismatches = @()
  foreach ($item in $plan) {
    $actual = (Get-FileHash -LiteralPath $item.Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.IncomingSha256) {
      $mismatches += $item.Relative
    }
  }
  if ($mismatches.Count -gt 0) {
    throw "Post-merge SHA256 verification failed for: $($mismatches -join ', '). Backup is available at $backupRoot"
  }

  Write-Host "Merged and SHA256-verified $($plan.Count) files without deleting any other project file."
  Write-Host "Backup: $backupRoot"
  Write-Host "Manifest: $manifestPath"
}
finally {
  if ($null -ne $archive) { $archive.Dispose() }
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
