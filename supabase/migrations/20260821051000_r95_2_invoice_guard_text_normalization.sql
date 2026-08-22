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