$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$productionRef = 'havlqebmnjdcwmpaaqew'
$cli = Join-Path $repoRoot 'node_modules\.bin\supabase.cmd'
$bootstrap = Join-Path $repoRoot 'supabase\fresh_install\r35_cloud_command_compatibility.sql'
$finalStateTest = Join-Path $repoRoot 'supabase\tests\verify_fresh_install_final_state.sql'
$runtimeTest = Join-Path $repoRoot 'supabase\tests\verify_r50_r52_runtime.sql'
$r49TransactionTest = Join-Path $repoRoot 'supabase\tests\verify_r49_erp_transactions_runtime.sql'
$r55NotificationTest = Join-Path $repoRoot 'supabase\tests\verify_r55_opportunity_notifications.sql'
$r551TerminalTest = Join-Path $repoRoot 'supabase\tests\verify_r55_1_opportunity_terminal_semantics.sql'
$r56RelationshipTest = Join-Path $repoRoot 'supabase\tests\verify_r56_opportunity_maintenance_vehicle_partner_360.sql'
$migrationSource = Join-Path $repoRoot 'supabase\migrations'
$configSource = Join-Path $repoRoot 'supabase\config.toml'

function Assert-File([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    Write-Host "`n==> $Label" -ForegroundColor Cyan
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Replace-ExactlyOne {
    param(
        [Parameter(Mandatory = $true)][string]$InputText,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $matches = [regex]::Matches($InputText, $Pattern)
    if ($matches.Count -ne 1) {
        throw "$Label expected exactly one config match, found $($matches.Count)"
    }
    return [regex]::Replace($InputText, $Pattern, $Replacement)
}

function Assert-NoNonLocalEnvironment {
    foreach ($name in @('SUPABASE_DB_URL', 'DATABASE_URL', 'SUPABASE_URL')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value.IndexOf($productionRef, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Fresh database verification refuses Production environment variable $name"
        }
        $uri = $null
        if ([Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri)) {
            if ($uri.Host -notin @('localhost', '127.0.0.1', '::1')) {
                throw "Fresh database verification refuses non-local target in $name ($($uri.Host))"
            }
        } else {
            throw "Fresh database verification refuses unparseable target variable $name"
        }
    }
}

Assert-File $cli
Assert-File $bootstrap
Assert-File $finalStateTest
Assert-File $runtimeTest
Assert-File $r49TransactionTest
Assert-File $r55NotificationTest
Assert-File $r56RelationshipTest
Assert-File $r551TerminalTest
Assert-File $configSource
Assert-NoNonLocalEnvironment

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI is required for LOCAL fresh database verification'
}

$runId = [Guid]::NewGuid().ToString('N').Substring(0, 10)
$localProjectId = "quality_line_erp_fresh_verify_$runId"
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase "quality-line-erp-fresh-$runId"
$tempRootFull = [IO.Path]::GetFullPath($tempRoot)
if (-not $tempRootFull.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFileName($tempRootFull)).StartsWith('quality-line-erp-fresh-', [StringComparison]::Ordinal)) {
    throw "Unsafe temporary path rejected: $tempRootFull"
}

$tempSupabase = Join-Path $tempRootFull 'supabase'
$tempMigrations = Join-Path $tempSupabase 'migrations'
$container = "supabase_db_$localProjectId"
$started = $false

try {
    New-Item -ItemType Directory -Path $tempMigrations -Force | Out-Null

    $config = [IO.File]::ReadAllText($configSource)
    $config = Replace-ExactlyOne $config '(?m)^project_id\s*=\s*"[^"]+"\s*$' "project_id = `"$localProjectId`"" 'project_id'
    $dbPort = 56000 + ([int]([Convert]::ToUInt32($runId.Substring(0, 4), 16)) % 4000)
    $shadowPort = $dbPort + 1
    $config = Replace-ExactlyOne $config '(?ms)(^\[db\]\s*.*?^port\s*=\s*)\d+' "`${1}$dbPort" 'db.port'
    $config = Replace-ExactlyOne $config '(?m)^(shadow_port\s*=\s*)\d+' "`${1}$shadowPort" 'db.shadow_port'
    if ($config.IndexOf($productionRef, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw 'Temporary local config unexpectedly contains the Production project reference'
    }
    [IO.File]::WriteAllText((Join-Path $tempSupabase 'config.toml'), $config, [Text.UTF8Encoding]::new($false))

    Write-Host "LOCAL ONLY project: $localProjectId" -ForegroundColor Yellow
    Write-Host "LOCAL ONLY temporary root: $tempRootFull" -ForegroundColor Yellow
    Write-Host 'No --linked or --db-url command is permitted by this tool.' -ForegroundColor Yellow

    Invoke-Checked 'Supabase CLI version' $cli @('--version')
    Invoke-Checked 'Start empty LOCAL Postgres' $cli @('db', 'start', '--workdir', $tempRootFull)
    $started = $true

    $inspectJson = (& docker inspect $container) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect LOCAL container $container" }
    $inspection = @($inspectJson | ConvertFrom-Json)
    $label = $inspection[0].Config.Labels.'com.supabase.cli.project'
    if ($label -ne $localProjectId) {
        throw "Docker project identity mismatch for $container (label=$label)"
    }

    Invoke-Checked 'Copy fresh-install compatibility prerequisite' 'docker' @(
        'cp', $bootstrap, "${container}:/tmp/r35_cloud_command_compatibility.sql"
    )
    Invoke-Checked 'Apply fail-closed prerequisite to empty LOCAL database' 'docker' @(
        'exec', $container, 'psql', '-U', 'postgres', '-d', 'postgres', '-X',
        '-v', 'ON_ERROR_STOP=1', '-f', '/tmp/r35_cloud_command_compatibility.sql'
    )

    Copy-Item -Path (Join-Path $migrationSource '*.sql') -Destination $tempMigrations
    $expectedMigrationCount = @(Get-ChildItem -LiteralPath $migrationSource -Filter '*.sql' -File).Count
    $copiedMigrationCount = @(Get-ChildItem -LiteralPath $tempMigrations -Filter '*.sql' -File).Count
    if ($expectedMigrationCount -ne $copiedMigrationCount) {
        throw "Migration copy count mismatch: source=$expectedMigrationCount copied=$copiedMigrationCount"
    }

    Invoke-Checked 'Apply immutable authoritative history to LOCAL database' $cli @(
        'migration', 'up', '--local', '--include-all', '--workdir', $tempRootFull
    )
    Invoke-Checked 'List LOCAL migration history' $cli @(
        'migration', 'list', '--local', '--workdir', $tempRootFull
    )

    $appliedText = (& docker exec $container psql -U postgres -d postgres -X -Atc 'select count(*) from supabase_migrations.schema_migrations').Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not count LOCAL applied migrations' }
    $appliedMigrationCount = [int]$appliedText
    if ($appliedMigrationCount -ne $expectedMigrationCount) {
        throw "Applied migration count mismatch: expected=$expectedMigrationCount applied=$appliedMigrationCount"
    }

    foreach ($test in @($finalStateTest, $r49TransactionTest, $runtimeTest, $r55NotificationTest, $r551TerminalTest, $r56RelationshipTest)) {
        $remotePath = "/tmp/$([IO.Path]::GetFileName($test))"
        Invoke-Checked "Copy $([IO.Path]::GetFileName($test))" 'docker' @('cp', $test, "${container}:$remotePath")
        Invoke-Checked "Run $([IO.Path]::GetFileName($test))" 'docker' @(
            'exec', $container, 'psql', '-U', 'postgres', '-d', 'postgres', '-X',
            '-v', 'ON_ERROR_STOP=1', '-f', $remotePath
        )
    }

    Invoke-Checked 'Lint LOCAL public schema' $cli @(
        'db', 'lint', '--local', '--schema', 'public', '--level', 'error',
        '--fail-on', 'error', '--workdir', $tempRootFull
    )
    Invoke-Checked 'Run LOCAL security and performance advisors' $cli @(
        'db', 'advisors', '--local', '--type', 'all', '--level', 'info',
        '--fail-on', 'error', '--workdir', $tempRootFull
    )

    Write-Host "`nPASS fresh LOCAL database verification - $appliedMigrationCount authoritative migrations" -ForegroundColor Green
} finally {
    if ($started) {
        Write-Host "`n==> Delete only LOCAL disposable stack $localProjectId" -ForegroundColor Cyan
        & $cli stop --project-id $localProjectId --no-backup --workdir $tempRootFull
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "LOCAL disposable cleanup returned exit code $LASTEXITCODE"
        }
    }
    if (Test-Path -LiteralPath $tempRootFull) {
        $resolved = [IO.Path]::GetFullPath($tempRootFull)
        if ($resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
            ([IO.Path]::GetFileName($resolved)).StartsWith('quality-line-erp-fresh-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        } else {
            throw "Refused unsafe temporary cleanup path: $resolved"
        }
    }
}
