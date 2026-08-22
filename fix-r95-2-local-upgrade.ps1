$ErrorActionPreference = "Stop"

Set-Location C:\Projects\kaj-erp

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " R95.2 SAFE LOCAL MIGRATION PREFLIGHT FIX" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$r95Path = Join-Path (Get-Location) `
    "supabase\migrations\20260821051500_r95_2_granular_invoice_approval_backend_guard.sql"

$preflightPath = Join-Path (Get-Location) `
    "supabase\migrations\20260821051000_r95_2_invoice_guard_text_normalization.sql"

if (-not (Test-Path -LiteralPath $r95Path)) {
    throw "Historical R95.2 migration is missing: $r95Path"
}

# ----------------------------------------------------------
# 1. Find LOCAL Supabase PostgreSQL only.
# ----------------------------------------------------------

$dbContainer = docker ps --format "{{.Names}}" |
    Where-Object { $_ -eq "supabase_db_quality_line_erp_local_dev" } |
    Select-Object -First 1

if (-not $dbContainer) {
    throw "LOCAL Supabase database container is not running."
}

Write-Host "PASS: Local DB = $dbContainer" -ForegroundColor Green

# ----------------------------------------------------------
# 2. Confirm R95.2 has NOT already been applied.
# ----------------------------------------------------------

$historySql = @"
select version
from supabase_migrations.schema_migrations
where version in (
  '20260821044500',
  '20260821044900',
  '20260821051000',
  '20260821051500',
  '20260821053500'
)
order by version;
"@

$historyRaw = & docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -A `
    -t `
    -c $historySql 2>&1

if ($LASTEXITCODE -ne 0) {
    $historyRaw | ForEach-Object { Write-Host $_ }
    throw "Could not read LOCAL migration history."
}

$history = ($historyRaw -join "`n")

Write-Host "`n=== CURRENT R95 MIGRATION HISTORY ===" -ForegroundColor Cyan
$historyRaw | ForEach-Object {
    if (-not [string]::IsNullOrWhiteSpace($_)) {
        Write-Host $_
    }
}

if ($history.Contains("20260821051500")) {
    throw "STOP: R95.2 is already recorded as applied. This repair path must not be used."
}

if (-not $history.Contains("20260821044500")) {
    throw "STOP: R95 base migration is not applied."
}

if (-not $history.Contains("20260821044900")) {
    throw "STOP: R95.1 migration is not applied."
}

Write-Host "PASS: database is exactly in the safe pre-R95.2 state." `
    -ForegroundColor Green

# ----------------------------------------------------------
# 3. Match the new migration's line endings to R95.2.
#    This removes CRLF/LF drift as a source of exact-match
#    failure while the SQL also tolerates whitespace drift.
# ----------------------------------------------------------

$r95Bytes = [System.IO.File]::ReadAllBytes($r95Path)
$r95Text = [System.Text.Encoding]::UTF8.GetString($r95Bytes)

if ($r95Text.Contains("`r`n")) {
    $targetEol = "`r`n"
    Write-Host "R95.2 file EOL: CRLF"
}
else {
    $targetEol = "`n"
    Write-Host "R95.2 file EOL: LF"
}

$sqlTemplate = @'
begin;

-- R95.2 preflight normalization.
--
-- Purpose:
-- Normalize ONLY the textual representation of the historical V742 broad
-- invoice authorization guard before R95.2 performs its deliberately strict
-- exact-text replacement.
--
-- Business/accounting/FIFO/valuation behavior is not rewritten here.
-- The migration fails closed unless exactly one semantically equivalent
-- historical broad guard is present.

do $r95_2_preflight$
declare
  v_definition text;

  v_canonical_guard text := $canonical_guard$
  perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.approve','sales.update'] else array['purchases.approve','purchases.update'] end);
$canonical_guard$;

  v_guard_pattern text := $guard_pattern$perform[[:space:]]+public\.erp_require_any_cloud_permission[[:space:]]*\([[:space:]]*p_company_id[[:space:]]*,[[:space:]]*case[[:space:]]+when[[:space:]]+p_module[[:space:]]*=[[:space:]]*'sales'[[:space:]]+then[[:space:]]+array[[:space:]]*\[[[:space:]]*'sales\.approve'[[:space:]]*,[[:space:]]*'sales\.update'[[:space:]]*\][[:space:]]+else[[:space:]]+array[[:space:]]*\[[[:space:]]*'purchases\.approve'[[:space:]]*,[[:space:]]*'purchases\.update'[[:space:]]*\][[:space:]]+end[[:space:]]*\)[[:space:]]*;$guard_pattern$;

  v_match_count integer;
  v_at integer;
  v_after text;
begin
  select pg_get_functiondef(
    'public.erp_approve_cloud_workflow_invoice(uuid,uuid,text)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'r95_2_preflight_invoice_posting_engine_missing';
  end if;

  -- R95.2 must still be pending. A granular guard here would indicate
  -- unexpected migration/history drift and must not be silently overwritten.
  if strpos(v_definition, 'erp_r95_user_can_perform_action') > 0 then
    raise exception 'r95_2_preflight_unexpected_granular_guard';
  end if;

  select count(*)
  into v_match_count
  from regexp_matches(
    v_definition,
    v_guard_pattern,
    'g'
  );

  if v_match_count <> 1 then
    raise exception
      'r95_2_preflight_guard_match_count:%',
      v_match_count;
  end if;

  -- If the exact representation already matches R95.2, leave the
  -- proven posting engine entirely untouched.
  v_at := strpos(v_definition, v_canonical_guard);

  if v_at = 0 then
    v_after := regexp_replace(
      v_definition,
      v_guard_pattern,
      v_canonical_guard
    );

    if v_after = v_definition then
      raise exception 'r95_2_preflight_normalization_noop';
    end if;

    execute v_after;
  end if;

  -- Re-read PostgreSQL's authoritative definition and prove that
  -- R95.2's exact-text guard will now be found exactly once.
  select pg_get_functiondef(
    'public.erp_approve_cloud_workflow_invoice(uuid,uuid,text)'::regprocedure
  )
  into v_definition;

  v_at := strpos(v_definition, v_canonical_guard);

  if v_at = 0 then
    raise exception 'r95_2_preflight_canonical_guard_not_materialized';
  end if;

  v_after := substr(
    v_definition,
    v_at + length(v_canonical_guard)
  );

  if strpos(v_after, v_canonical_guard) > 0 then
    raise exception 'r95_2_preflight_canonical_guard_ambiguous';
  end if;
end;
$r95_2_preflight$;

commit;
'@

# Normalize template internally first, then emit using the exact
# same EOL convention as the pending R95.2 migration.
$sql = $sqlTemplate.Replace("`r`n", "`n").Replace("`r", "`n")

if ($targetEol -eq "`r`n") {
    $sql = $sql.Replace("`n", "`r`n")
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (Test-Path -LiteralPath $preflightPath) {

    $existing = [System.IO.File]::ReadAllText(
        $preflightPath,
        [System.Text.Encoding]::UTF8
    )

    if ($existing -ne $sql) {
        throw "Existing preflight migration differs. Nothing was overwritten."
    }

    Write-Host "PASS: preflight migration already exists and matches." `
        -ForegroundColor Green
}
else {

    [System.IO.File]::WriteAllText(
        $preflightPath,
        $sql,
        $utf8NoBom
    )

    Write-Host "Created: $preflightPath" -ForegroundColor Green
}

# ----------------------------------------------------------
# 4. Safety checks: historical R95.2 was NOT edited.
# ----------------------------------------------------------

Write-Host "`n=== MIGRATION ORDER ===" -ForegroundColor Cyan

Get-ChildItem `
    ".\supabase\migrations\202608210*.sql" |
    Sort-Object Name |
    Select-Object -ExpandProperty Name

if (-not (Test-Path -LiteralPath $preflightPath)) {
    throw "Preflight migration creation failed."
}

$preflightName = Split-Path $preflightPath -Leaf
$r95Name = Split-Path $r95Path -Leaf

if ($preflightName -ge $r95Name) {
    throw "Preflight migration does not sort before R95.2."
}

Write-Host "PASS: preflight sorts before R95.2." -ForegroundColor Green

Write-Host "`n=== STATIC R95.2 CONTRACT ===" -ForegroundColor Cyan

python -B .\tool\verify_r95_2_granular_invoice_approval_backend_guard.py

if ($LASTEXITCODE -ne 0) {
    throw "Existing R95.2 static contract FAILED."
}

# ----------------------------------------------------------
# 5. Apply pending migrations to EXISTING LOCAL DB only.
#    prepare_local_current_database.ps1 creates backups first.
# ----------------------------------------------------------

Write-Host "`n=== APPLY LOCAL MIGRATIONS ===" -ForegroundColor Cyan

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File .\tool\prepare_local_current_database.ps1

if ($LASTEXITCODE -ne 0) {
    throw "LOCAL migration preparation still FAILED."
}

# ----------------------------------------------------------
# 6. Verify expected migration history.
# ----------------------------------------------------------

Write-Host "`n=== VERIFY R95 MIGRATION HISTORY ===" -ForegroundColor Cyan

$verifyHistorySql = @"
select version, name
from supabase_migrations.schema_migrations
where version >= '20260821044500'
order by version;
"@

$finalHistory = & docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -P pager=off `
    -c $verifyHistorySql 2>&1

if ($LASTEXITCODE -ne 0) {
    $finalHistory | ForEach-Object { Write-Host $_ }
    throw "Could not verify final LOCAL migration history."
}

$finalHistory | ForEach-Object { Write-Host $_ }

$finalHistoryText = ($finalHistory -join "`n")

foreach ($requiredVersion in @(
    "20260821044500",
    "20260821044900",
    "20260821051000",
    "20260821051500",
    "20260821053500"
)) {
    if (-not $finalHistoryText.Contains($requiredVersion)) {
        throw "Missing applied migration: $requiredVersion"
    }

    Write-Host "PASS migration: $requiredVersion" -ForegroundColor Green
}

# ----------------------------------------------------------
# 7. PostgreSQL runtime regression verification.
# ----------------------------------------------------------

Write-Host "`n=== R89-R94 LOCAL POSTGRES RUNTIME ===" `
    -ForegroundColor Cyan

python -B .\tool\run_r89_r92_local_runtime_tests.py

if ($LASTEXITCODE -ne 0) {
    throw "LOCAL PostgreSQL runtime verification FAILED."
}

# ----------------------------------------------------------
# 8. Final canonical source verification.
# ----------------------------------------------------------

Write-Host "`n=== FINAL PROJECT VERIFICATION ===" -ForegroundColor Cyan

python -B .\tool\verify_project.py

if ($LASTEXITCODE -ne 0) {
    throw "Final project verification FAILED."
}

Write-Host "`n============================================" `
    -ForegroundColor Green
Write-Host " R95.2 LOCAL UPGRADE + RUNTIME PASSED" `
    -ForegroundColor Green
Write-Host "============================================" `
    -ForegroundColor Green

Write-Host ""
Write-Host "No db reset was used."
Write-Host "No db push was used."
Write-Host "No Supabase link was used."
Write-Host "No migration history was manually edited."
Write-Host "Historical R95.2 migration remains unchanged."