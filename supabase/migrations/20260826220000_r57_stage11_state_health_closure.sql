begin;

-- R57 / Stage 11 full-program integrity closure.
-- Restore the complete R16 health contract after the Stage 10 counter fix.
-- Stage 10 correctly made tombstone-conflict counting cumulative, but its
-- replacement also dropped the persistent reconciliation-issue and tombstone
-- health dimensions that R51 exposed.  Keep the cumulative counting while
-- preserving the complete read-only health contract used by the ERP.
--
-- This migration is forward-only, tenant-scoped, non-destructive, and does
-- not depend on CI/Quality Gate state.

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_table text;
  v_count bigint := 0;
  v_conflicts bigint := 0;
  v_open_issues bigint := 0;
  v_tombstones bigint := 0;
  v_checked_tables bigint := 0;
  v_issue_details jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  select count(*)
    into v_open_issues
  from public.erp_canonical_reconciliation_issues
  where company_id = p_company_id
    and resolved_at is null;

  select count(*)
    into v_tombstones
  from public.erp_canonical_deletion_tombstones
  where company_id = p_company_id
    and restored_at is null;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'issueType', q.issue_type,
        'entityType', q.entity_type,
        'entityId', q.entity_id,
        'details', q.details,
        'firstSeenAt', q.first_seen_at,
        'lastSeenAt', q.last_seen_at
      ) order by q.last_seen_at desc
    ),
    '[]'::jsonb
  )
    into v_issue_details
  from (
    select issue_type, entity_type, entity_id, details, first_seen_at, last_seen_at
    from public.erp_canonical_reconciliation_issues
    where company_id = p_company_id
      and resolved_at is null
    order by last_seen_at desc
    limit 25
  ) q;

  foreach v_table in array array[
    'erp_cars',
    'erp_car_images',
    'erp_customers',
    'erp_suppliers',
    'erp_warehouses',
    'erp_inventory',
    'erp_inventory_groups',
    'erp_product_images'
  ] loop
    if to_regclass('public.' || v_table) is not null then
      v_checked_tables := v_checked_tables + 1;
      execute format(
        'select count(*) from public.%I r '
        || 'join public.erp_canonical_deletion_tombstones t '
        || 'on t.company_id = r.company_id '
        || 'and t.source_table = $2 '
        || 'and t.record_id = r.id::text '
        || 'where r.company_id = $1 '
        || 'and t.restored_at is null '
        || 'and not coalesce(r.is_deleted, false)',
        v_table
      ) into v_count using p_company_id, v_table;
      v_conflicts := v_conflicts + coalesce(v_count, 0);
    end if;
  end loop;

  return jsonb_build_object(
    'ok', v_open_issues = 0 and v_conflicts = 0,
    'healthy', v_open_issues = 0 and v_conflicts = 0,
    'status', case when v_open_issues = 0 and v_conflicts = 0 then 'ok' else 'conflict' end,
    'companyId', p_company_id,
    'checkedTables', v_checked_tables,
    'persistentDeletionConflictCount', v_conflicts,
    'permanentDeletionTombstoneCount', v_tombstones,
    'unresolvedCanonicalReconciliationIssueCount', v_open_issues,
    'openCanonicalIssues', v_issue_details,
    'canonicalStateVersion', 16,
    'checkedAt', timezone('utc', now())
  );
end;
$$;

revoke all on function public.erp_r16_current_state_health(uuid) from anon;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
commit;
