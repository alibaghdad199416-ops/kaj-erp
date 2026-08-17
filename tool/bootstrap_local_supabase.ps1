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

function Assert-LocalOnlyUrl([string]$Url) {
  $uri = [Uri]$Url
  if ($uri.Scheme -ne "http" -or $uri.Host -notin @("127.0.0.1", "localhost", "::1")) {
    throw "Refusing to bootstrap Auth against non-local Supabase URL: $Url"
  }
}

function Get-LocalServiceRoleKey {
  $status = (& npx --yes supabase status -o env 2>&1 | Out-String)
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

  & npx --yes supabase start
  if ($LASTEXITCODE -ne 0) { throw "supabase start failed" }

  if ($ResetDatabase) {
    & npx --yes supabase db reset --local
    if ($LASTEXITCODE -ne 0) { throw "supabase db reset --local failed" }
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

  $upsertHeaders = @{
    apikey = $serviceRoleKey
    Authorization = "Bearer $serviceRoleKey"
    Prefer = "resolution=merge-duplicates,return=representation"
  }

  Invoke-LocalJsonRequest -Method "POST" -Uri "$ApiUrl/rest/v1/profiles?on_conflict=id" -Headers $upsertHeaders -Body @{
    id = $userId
    full_name = "KAJ Local Developer"
    is_active = $true
  } | Out-Null

  Invoke-LocalJsonRequest -Method "POST" -Uri "$ApiUrl/rest/v1/company_memberships?on_conflict=company_id,user_id" -Headers $upsertHeaders -Body @{
    company_id = $CompanyId
    user_id = $userId
    user_uid = $userId
    user_email = $Email.ToLowerInvariant()
    local_user_id = "kaj-local-dev"
    default_branch_id = $BranchId
    role_code = "owner"
    is_system_admin = $true
    is_active = $true
  } | Out-Null

  Write-Host "Local Supabase is ready." -ForegroundColor Green
  Write-Host "API: $ApiUrl"
  Write-Host "Auth user: $Email"
  Write-Host "Local-only password: $Password"
  Write-Host "Run Flutter with: flutter run -d chrome --web-port 5000 --dart-define-from-file=dart_defines.json"
  Write-Host "No hosted Supabase project was contacted by this bootstrap script."
}
finally {
  Pop-Location
}
