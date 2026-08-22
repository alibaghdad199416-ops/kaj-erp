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