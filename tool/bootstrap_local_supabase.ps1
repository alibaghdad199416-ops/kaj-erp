param(
  [string]$Email = "dev@kaj.local",
  [string]$Password = "KajLocalDev!2026-LocalOnly",
  [switch]$ResetDatabase
)

$ErrorActionPreference = "Stop"
$ApiUrl = "http://127.0.0.1:54321"
$ExpectedProjectId = "quality_line_erp_local_dev"
$CompanyId = "11111111-1111-4111-8111-111111111111"
$BranchId = "22222222-2222-4222-8222-222222222222"
$Npx = (Get-Command npx.cmd -ErrorAction Stop).Source
$Docker = (Get-Command docker.exe -ErrorAction Stop).Source

function Assert-LocalOnlyUrl([string]$Url) {
  $uri = [Uri]$Url
  if ($uri.Scheme -ne "http" -or $uri.Host -notin @("127.0.0.1", "localhost", "::1")) {
    throw "Refusing to bootstrap Auth against non-local Supabase URL: $Url"
  }
}

function Invoke-LocalSupabase {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$Capture
  )

  # Windows PowerShell 5.1 can wrap native stderr as NativeCommandError when
  # ErrorActionPreference=Stop. Supabase writes informational status lines such
  # as "Stopped services: [...]" to stderr even when the command exits 0.
  # Judge native CLI success by LASTEXITCODE and keep the global fail-closed
  # PowerShell preference for actual script/cmdlet failures.
  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = @(& $Npx --no-install supabase @Arguments 2>&1)
    $code = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }

  if ($code -ne 0) {
    foreach ($line in $output) { Write-Host ([string]$line) }
    throw "Supabase command failed: supabase $($Arguments -join ' ') (exit $code)"
  }

  if ($Capture) {
    return @($output | ForEach-Object { [string]$_ })
  }

  foreach ($line in $output) { Write-Host ([string]$line) }
}

function Invoke-LocalDocker {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$Capture
  )

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = @(& $Docker @Arguments 2>&1)
    $code = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousPreference
  }

  if ($code -ne 0) {
    foreach ($line in $output) { Write-Host ([string]$line) }
    throw "Docker command failed: docker $($Arguments -join ' ') (exit $code)"
  }

  if ($Capture) {
    return @($output | ForEach-Object { [string]$_ })
  }

  foreach ($line in $output) { Write-Host ([string]$line) }
}

function Get-LocalServiceRoleKey {
  $statusLines = Invoke-LocalSupabase -Arguments @("status", "-o", "env") -Capture
  $status = ($statusLines -join "`n")
  $match = [regex]::Match($status, '(?m)^SERVICE_ROLE_KEY="?([^"\r\n]+)"?$')
  if (-not $match.Success) {
    throw "Could not read the local SERVICE_ROLE_KEY from 'supabase status -o env'."
  }
  return $match.Groups[1].Value.Trim()
}

function Invoke-LocalJsonRequest {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Uri,
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    $Body = $null
  )
  Assert-LocalOnlyUrl $Uri
  $params = @{
    Method = $Method
    Uri = $Uri
    Headers = $Headers
    ContentType = "application/json"
  }
  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
  }
  return Invoke-RestMethod @params
}

function Invoke-LocalMembershipBootstrap {
  param(
    [Parameter(Mandatory = $true)][string]$UserId,
    [Parameter(Mandatory = $true)][string]$UserEmail
  )

  if ($UserId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
    throw "Local Auth returned an invalid user UUID: $UserId"
  }

  # Service-role REST access is intentionally not assumed for tenant identity
  # tables. The historical schema grants service_role EXECUTE on bootstrap RPCs
  # but not necessarily table privileges on profiles/company_memberships.
  # This LOCAL-ONLY bootstrap therefore writes the two deterministic seed rows
  # through the local Postgres container as postgres, without changing grants,
  # RLS, migrations, or any hosted project.
  $expectedDbContainer = "supabase_db_$ExpectedProjectId"
  $containers = Invoke-LocalDocker -Arguments @("ps", "--format", "{{.Names}}") -Capture
  $dbContainer = @($containers | Where-Object { $_.Trim() -eq $expectedDbContainer } | Select-Object -First 1)
  if ($dbContainer.Count -eq 0) {
    throw "Expected local Supabase database container '$expectedDbContainer' is not running."
  }

  $emailSql = $UserEmail.ToLowerInvariant().Replace("'", "''")
  $sql = @"
insert into public.profiles(id, full_name, is_active, updated_at)
values ('$UserId'::uuid, 'KAJ Local Developer', true, now())
on conflict (id) do update
set full_name = excluded.full_name,
    is_active = true,
    updated_at = now();

insert into public.company_memberships(
  company_id, user_id, user_uid, user_email, local_user_id,
  default_branch_id, role_code, is_system_admin, is_active, updated_at
) values (
  '$CompanyId'::uuid,
  '$UserId'::uuid,
  '$UserId',
  '$emailSql',
  'kaj-local-dev',
  '$BranchId'::uuid,
  'owner',
  true,
  true,
  now()
)
on conflict (company_id, user_id) do update
set user_uid = excluded.user_uid,
    user_email = excluded.user_email,
    local_user_id = excluded.local_user_id,
    default_branch_id = excluded.default_branch_id,
    role_code = excluded.role_code,
    is_system_admin = true,
    is_active = true,
    updated_at = now();
"@

  Invoke-LocalDocker -Arguments @(
    "exec",
    $expectedDbContainer,
    "psql",
    "-U", "postgres",
    "-d", "postgres",
    "-v", "ON_ERROR_STOP=1",
    "-c", $sql
  )
}

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $root
try {
  if (-not (Test-Path "supabase/config.toml")) {
    throw "supabase/config.toml is missing. Run this script from the KAJ ERP repository."
  }

  $config = Get-Content "supabase/config.toml" -Raw
  if ($config -notmatch ('project_id\s*=\s*"' + [regex]::Escape($ExpectedProjectId) + '"')) {
    throw "Unexpected local Supabase project_id. Refusing to start an unknown stack."
  }
  if ($config -match 'https://[^\s"'']+\.supabase\.co') {
    throw "Hosted Supabase reference found in local config.toml. Refusing to continue."
  }

  Invoke-LocalSupabase -Arguments @("start")

  if ($ResetDatabase) {
    Invoke-LocalSupabase -Arguments @("db", "reset", "--local")
  }

  Assert-LocalOnlyUrl $ApiUrl
  $serviceRoleKey = Get-LocalServiceRoleKey
  $headers = @{
    apikey = $serviceRoleKey
    Authorization = "Bearer $serviceRoleKey"
  }

  $usersResponse = Invoke-LocalJsonRequest -Method "GET" -Uri "$ApiUrl/auth/v1/admin/users?per_page=1000" -Headers $headers
  $users = @()
  if ($usersResponse.users) { $users = @($usersResponse.users) }
  elseif ($usersResponse -is [System.Array]) { $users = @($usersResponse) }
  $user = $users | Where-Object { $_.email -eq $Email } | Select-Object -First 1

  if (-not $user) {
    $user = Invoke-LocalJsonRequest -Method "POST" -Uri "$ApiUrl/auth/v1/admin/users" -Headers $headers -Body @{
      email = $Email
      password = $Password
      email_confirm = $true
      user_metadata = @{ full_name = "KAJ Local Developer"; local_only = $true }
    }
  } else {
    $user = Invoke-LocalJsonRequest -Method "PUT" -Uri "$ApiUrl/auth/v1/admin/users/$($user.id)" -Headers $headers -Body @{
      password = $Password
      email_confirm = $true
      user_metadata = @{ full_name = "KAJ Local Developer"; local_only = $true }
    }
  }

  if (-not $user.id) { throw "Local Auth user creation returned no user id." }
  $userId = [string]$user.id

  Invoke-LocalMembershipBootstrap -UserId $userId -UserEmail $Email

  Write-Host "Local Supabase is ready." -ForegroundColor Green
  Write-Host "API: $ApiUrl"
  Write-Host "Auth user: $Email"
  Write-Host "Local-only password: $Password"
  Write-Host "Run KAJ with: npm run run:web:local"
  Write-Host "No hosted Supabase project was contacted by this bootstrap script."
}
finally {
  Pop-Location
}
