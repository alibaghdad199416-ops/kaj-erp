begin;

-- R56 / Stage 10 integrity closure.
-- Correct the canonical state-health aggregators introduced by R53.
-- The previous implementation overwrote the conflict count on every table,
-- so the reported value represented only the last existing table.  This
-- forward-only migration preserves all data and makes both health functions
-- aggregate conflicts across every participating table.

create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  t text;
  tables text[]:=array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers',
    'erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'
  ];
  checked bigint:=0;
  conflicts bigint:=0;
  v_table_conflicts bigint:=0;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  foreach t in array tables loop
    if to_regclass('public.'||t) is not null then
      checked:=checked+1;
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones z on z.company_id=r.company_id and z.source_table=$2 and z.record_id=r.id::text where r.company_id=$1 and z.restored_at is null and not coalesce(r.is_deleted,false)',
        t
      ) into v_table_conflicts using p_company_id,t;
      conflicts:=conflicts+coalesce(v_table_conflicts,0);
    end if;
  end loop;

  return jsonb_build_object(
    'companyId',p_company_id,
    'checkedTables',checked,
    'openCanonicalConflicts',conflicts,
    'status',case when conflicts=0 then 'ok' else 'conflict' end
  );
end;
$$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  t text;
  tables text[]:=array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers',
    'erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'
  ];
  conflicts bigint:=0;
  v_table_conflicts bigint:=0;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;

  foreach t in array tables loop
    if to_regclass('public.'||t) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones z on z.company_id=r.company_id and z.source_table=$2 and z.record_id=r.id::text where r.company_id=$1 and z.restored_at is null and not coalesce(r.is_deleted,false)',
        t
      ) into v_table_conflicts using p_company_id,t;
      conflicts:=conflicts+coalesce(v_table_conflicts,0);
    end if;
  end loop;

  return jsonb_build_object(
    'companyId',p_company_id,
    'canonicalConflicts',conflicts,
    'healthy',conflicts=0
  );
end;
$$;

revoke all on function public.erp_r15_reconcile_company_state(uuid) from anon;
revoke all on function public.erp_r16_current_state_health(uuid) from anon;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated,service_role;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
