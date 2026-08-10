[CmdletBinding()]
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$SkipDeploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $ProjectRoot

$navigationPath = Join-Path $ProjectRoot 'lib\core\widgets\app_top_navigation.dart'
$maintenancePath = Join-Path $ProjectRoot 'lib\features\maintenance\pages\maintenance_order_details_dialog.dart'

foreach ($path in @($navigationPath, $maintenancePath)) {
  if (-not (Test-Path $path)) {
    throw "Required source file not found: $path"
  }
  Copy-Item $path "$path.before_v731_analyzer_fix.bak" -Force
}

$navigation = Get-Content $navigationPath -Raw
if ($navigation -notmatch "(?m)^import 'dart:async';$") {
  $navigation = "import 'dart:async';`r`n`r`n$navigation"
}

$constructorPattern = '(?ms)class _NavigationActions extends StatelessWidget \{\s+const _NavigationActions\(\{\s+required this\.currentRoute,\s+this\.vertical = false,\s+this\.compact = false,\s+\}\);\s+final String currentRoute;\s+final bool vertical;\s+final bool compact;'
$constructorReplacement = @'
class _NavigationActions extends StatelessWidget {
  const _NavigationActions({required this.currentRoute});

  final String currentRoute;
'@
$navigation = [regex]::Replace(
  $navigation,
  $constructorPattern,
  $constructorReplacement,
  1
)

$layoutPattern = '(?ms)    if \(vertical && compact\) \{\s+return Column\(children: buttons\);\s+\}\s+return vertical\s+\? Padding\(\s+padding: const EdgeInsets\.symmetric\(horizontal: 8\),\s+child: Wrap\(alignment: WrapAlignment\.center, children: buttons\),\s+\)\s+: Row\(children: \[\.\.\.buttons, const SizedBox\(width: 6\)\]\);'
$layoutReplacement = '    return Row(children: [...buttons, const SizedBox(width: 6)]);'
$navigation = [regex]::Replace(
  $navigation,
  $layoutPattern,
  $layoutReplacement,
  1
)

Set-Content -Path $navigationPath -Value $navigation -Encoding UTF8

$maintenance = Get-Content $maintenancePath -Raw
if ($maintenance -notmatch "(?m)^import 'dart:async';$") {
  $maintenance = "import 'dart:async';`r`n`r`n$maintenance"
}
$maintenance = $maintenance.Replace(
  "    _loadLines();`r`n",
  "    unawaited(_loadLines());`r`n"
)
$maintenance = $maintenance.Replace(
  "    _loadLines();`n",
  "    unawaited(_loadLines());`n"
)
Set-Content -Path $maintenancePath -Value $maintenance -Encoding UTF8

$backupFolder = Join-Path $ProjectRoot 'supabase\migration_backups'
New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
Get-ChildItem (Join-Path $ProjectRoot 'supabase\migrations') -File |
  Where-Object {
    $_.Name -match '\.before_' -or
    $_.Name -match '_backup_' -or
    $_.Name -match '\.bak$'
  } |
  Move-Item -Destination $backupFolder -Force

$flutterCommand = Get-Command flutter -ErrorAction Stop
$flutterPath = if ($flutterCommand -is [System.IO.FileInfo]) {
  $flutterCommand.FullName
} else {
  $flutterCommand.Source
}
$flutterBin = Split-Path $flutterPath -Parent
$dartExe = Join-Path $flutterBin 'cache\dart-sdk\bin\dart.exe'
if (-not (Test-Path $dartExe)) {
  throw "Dart SDK not found: $dartExe"
}

& $dartExe format $navigationPath $maintenancePath
if ($LASTEXITCODE -ne 0) {
  throw "Dart formatting failed with exit code $LASTEXITCODE."
}

& npm.cmd run verify
if ($LASTEXITCODE -ne 0) {
  throw "Structural verification failed with exit code $LASTEXITCODE."
}

& flutter analyze --fatal-infos --fatal-warnings
if ($LASTEXITCODE -ne 0) {
  throw "Flutter analyzer failed with exit code $LASTEXITCODE."
}

Write-Host ''
Write-Host 'PASS: all eight analyzer findings were repaired.' -ForegroundColor Green

if (-not $SkipDeploy) {
  & npm.cmd run deploy:production
  if ($LASTEXITCODE -ne 0) {
    throw "Production deployment failed with exit code $LASTEXITCODE."
  }
}
