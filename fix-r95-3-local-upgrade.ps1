$ErrorActionPreference = "Stop"

Set-Location C:\Projects\kaj-erp

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " R95.3 SAFE LOCAL PAYMENT PREFLIGHT FIX" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$r95Path = Join-Path (Get-Location) `
    "supabase\migrations\20260821053500_r95_3_granular_payment_backend_guard.sql"

$preflightPath = Join-Path (Get-Location) `
    "supabase\migrations\20260821053000_r95_3_payment_guard_text_normalization.sql"

if (-not (Test-Path -LiteralPath $r95Path)) {
    throw "Historical R95.3 migration is missing."
}

$dbContainer = docker ps --format "{{.Names}}" |
    Where-Object { $_ -eq "supabase_db_quality_line_erp_local_dev" } |
    Select-Object -First 1

if (-not $dbContainer) {
    throw "LOCAL Supabase PostgreSQL container is not running."
}

Write-Host "PASS: Local DB = $dbContainer" -ForegroundColor Green

# ----------------------------------------------------------
# 1. Verify exact migration state.
# ----------------------------------------------------------

$historySql = @"
select version
from supabase_migrations.schema_migrations
where version >= '20260821044500'
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

foreach ($required in @(
    "20260821044500",
    "20260821044900",
    "20260821051000",
    "20260821051500"
)) {
    if (-not $history.Contains($required)) {
        throw "Required prior migration is not applied: $required"
    }
}

if ($history.Contains("20260821053500")) {
    throw "STOP: R95.3 is already applied."
}

Write-Host "PASS: database is safely positioned before R95.3." `
    -ForegroundColor Green

# ----------------------------------------------------------
# 2. Inspect payment function before modifying anything.
# ----------------------------------------------------------

$definitionSql = @"
select pg_get_functiondef(
 'public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)'::regprocedure
);
"@

$rawDefinition = & docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -A `
    -t `
    -c $definitionSql 2>&1

if ($LASTEXITCODE -ne 0) {
    $rawDefinition | ForEach-Object { Write-Host $_ }
    throw "Could not read secure payment engine."
}

$definition = ($rawDefinition -join "`n")

if ([string]::IsNullOrWhiteSpace($definition)) {
    throw "Secure payment engine definition is empty."
}

$hasBroad = $definition.Contains(
    "erp_require_any_cloud_permission"
)

$hasGranular = $definition.Contains(
    "erp_r95_user_can_perform_action"
)

if (-not $hasBroad) {
    throw "Expected historical broad payment guard is missing."
}

if ($hasGranular) {
    throw "Unexpected granular payment guard already exists before R95.3."
}

Write-Host "PASS: historical broad payment guard is present." `
    -ForegroundColor Green
Write-Host "PASS: R95 granular payment guard is not yet present." `
    -ForegroundColor Green

# ----------------------------------------------------------
# 3. Match EOL convention of R95.3.
# ----------------------------------------------------------

$r95Text = [System.IO.File]::ReadAllText(
    $r95Path,
    [System.Text.Encoding]::UTF8
)

if ($r95Text.Contains("`r`n")) {
    $targetEol = "`r`n"
    Write-Host "R95.3 file EOL: CRLF"
}
else {
    $targetEol = "`n"
    Write-Host "R95.3 file EOL: LF"
}

# ----------------------------------------------------------
# 4. Create forward-only normalization migration.
# ----------------------------------------------------------

$sqlTemplate = @'
begin;

-- R95.3 preflight normalization.
--
-- Normalize only the textual representation of the historical V757 payment
-- permission guard so R95.3 can perform its deliberately strict replacement.
--
-- Payment amounts, FX, cashbox routing, accounting, journals and settlement
-- behavior are intentionally untouched.
--
-- Fail closed unless exactly one semantically equivalent historical guard
-- exists and no R95 granular guard has already been installed.

do $r95_3_preflight$
declare
  v_definition text;

  v_canonical_guard text := $canonical_guard$
  perform public.erp_require_any_cloud_permission(
    p_company_id,case when p_module='purchases' then array['cashbox.payment'] else array['cashbox.receipt'] end);
$canonical_guard$;

  v_guard_pattern text := $guard_pattern$perform[[:space:]]+public\.erp_require_any_cloud_permission[[:space:]]*\([[:space:]]*p_company_id[[:space:]]*,[[:space:]]*case[[:space:]]+when[[:space:]]+p_module[[:space:]]*=[[:space:]]*'purchases'[[:space:]]+then[[:space:]]+array[[:space:]]*\[[[:space:]]*'cashbox\.payment'[[:space:]]*\][[:space:]]+else[[:space:]]+array[[:space:]]*\[[[:space:]]*'cashbox\.receipt'[[:space:]]*\][[:space:]]+end[[:space:]]*\)[[:space:]]*;$guard_pattern$;

  v_match_count integer;
  v_at integer;
  v_after text;
begin
  select pg_get_functiondef(
    'public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'r95_3_preflight_secure_payment_engine_missing';
  end if;

  if strpos(v_definition, 'erp_r95_user_can_perform_action') > 0 then
    raise exception 'r95_3_preflight_unexpected_granular_guard';
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
      'r95_3_preflight_guard_match_count:%',
      v_match_count;
  end if;

  v_at := strpos(v_definition, v_canonical_guard);

  if v_at = 0 then
    v_after := regexp_replace(
      v_definition,
      v_guard_pattern,
      v_canonical_guard
    );

    if v_after = v_definition then
      raise exception 'r95_3_preflight_normalization_noop';
    end if;

    execute v_after;
  end if;

  -- Re-read PostgreSQL authoritative representation and prove that the exact
  -- string expected by R95.3 now occurs once and only once.
  select pg_get_functiondef(
    'public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)'::regprocedure
  )
  into v_definition;

  v_at := strpos(v_definition, v_canonical_guard);

  if v_at = 0 then
    raise exception 'r95_3_preflight_canonical_guard_not_materialized';
  end if;

  v_after := substr(
    v_definition,
    v_at + length(v_canonical_guard)
  );

  if strpos(v_after, v_canonical_guard) > 0 then
    raise exception 'r95_3_preflight_canonical_guard_ambiguous';
  end if;
end;
$r95_3_preflight$;

commit;
'@

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
        throw "Existing R95.3 preflight migration differs. Nothing overwritten."
    }

    Write-Host "PASS: existing R95.3 preflight matches." `
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
# 5. Verify migration ordering.
# ----------------------------------------------------------

Write-Host "`n=== MIGRATION ORDER ===" -ForegroundColor Cyan

Get-ChildItem ".\supabase\migrations\2026082105*.sql" |
    Sort-Object Name |
    Select-Object -ExpandProperty Name

$preflightName = Split-Path $preflightPath -Leaf
$r95Name = Split-Path $r95Path -Leaf

if ($preflightName -ge $r95Name) {
    throw "R95.3 preflight does not sort before R95.3."
}

Write-Host "PASS: 53000 preflight sorts before 53500 R95.3." `
    -ForegroundColor Green

# ----------------------------------------------------------
# 6. Verify historical R95.3 source contract.
# ----------------------------------------------------------

Write-Host "`n=== STATIC R95.3 CONTRACT ===" -ForegroundColor Cyan

python -B .\tool\verify_r95_3_granular_payment_backend_guard.py

if ($LASTEXITCODE -ne 0) {
    throw "R95.3 static source contract FAILED."
}

# ----------------------------------------------------------
# 7. Show exactly what local source changed.
# ----------------------------------------------------------

Write-Host "`n=== LOCAL DIFF ===" -ForegroundColor Cyan

git --no-pager diff -- `
    supabase/migrations/20260821051000_r95_2_invoice_guard_text_normalization.sql `
    supabase/migrations/20260821053000_r95_3_payment_guard_text_normalization.sql

# ----------------------------------------------------------
# 8. Apply pending migrations to EXISTING LOCAL Supabase.
# ----------------------------------------------------------

Write-Host "`n=== APPLY REMAINING LOCAL MIGRATIONS ===" `
    -ForegroundColor Cyan

powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File .\tool\prepare_local_current_database.ps1

if ($LASTEXITCODE -ne 0) {
    throw "LOCAL migration preparation FAILED."
}

# ----------------------------------------------------------
# 9. Verify final migration history.
# ----------------------------------------------------------

Write-Host "`n=== FINAL R95 MIGRATION HISTORY ===" `
    -ForegroundColor Cyan

$finalHistorySql = @"
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
    -c $finalHistorySql 2>&1

if ($LASTEXITCODE -ne 0) {
    $finalHistory | ForEach-Object { Write-Host $_ }
    throw "Could not verify final migration history."
}

$finalHistory | ForEach-Object { Write-Host $_ }

$finalHistoryText = ($finalHistory -join "`n")

foreach ($required in @(
    "20260821044500",
    "20260821044900",
    "20260821051000",
    "20260821051500",
    "20260821053000",
    "20260821053500"
)) {
    if (-not $finalHistoryText.Contains($required)) {
        throw "Missing applied migration: $required"
    }

    Write-Host "PASS migration: $required" `
        -ForegroundColor Green
}

# ----------------------------------------------------------
# 10. Prove payment engine now uses granular guard.
# ----------------------------------------------------------

Write-Host "`n=== VERIFY PAYMENT ENGINE AUTHORIZATION ===" `
    -ForegroundColor Cyan

$postDefinition = & docker exec `
    $dbContainer `
    psql `
    -U postgres `
    -d postgres `
    -X `
    -A `
    -t `
    -c $definitionSql 2>&1

if ($LASTEXITCODE -ne 0) {
    throw "Could not re-read payment engine."
}

$postText = ($postDefinition -join "`n")

foreach ($marker in @(
    "erp_r95_user_can_perform_action",
    "sales.actions.restrict",
    "sales.payment",
    "purchases.actions.restrict",
    "purchases.payment"
)) {
    if (-not $postText.Contains($marker)) {
        throw "Payment engine is missing expected R95.3 marker: $marker"
    }

    Write-Host "PASS: $marker" -ForegroundColor Green
}

# ----------------------------------------------------------
# 11. Runtime verification.
# ----------------------------------------------------------

Write-Host "`n=== R89-R94 LOCAL POSTGRES RUNTIME ===" `
    -ForegroundColor Cyan

python -B .\tool\run_r89_r92_local_runtime_tests.py

if ($LASTEXITCODE -ne 0) {
    throw "LOCAL PostgreSQL runtime verification FAILED."
}

# ----------------------------------------------------------
# 12. Canonical project verification.
# ----------------------------------------------------------

Write-Host "`n=== FINAL PROJECT VERIFICATION ===" `
    -ForegroundColor Cyan

python -B .\tool\verify_project.py

if ($LASTEXITCODE -ne 0) {
    throw "Final project verification FAILED."
}

Write-Host "`n============================================" `
    -ForegroundColor Green
Write-Host " R95.3 LOCAL UPGRADE + RUNTIME PASSED" `
    -ForegroundColor Green
Write-Host "============================================" `
    -ForegroundColor Green

Write-Host ""
Write-Host "No db reset used."
Write-Host "No db push used."
Write-Host "No Supabase link used."
Write-Host "No migration history manually edited."
Write-Host "Historical R95.2/R95.3 migrations remain unchanged."