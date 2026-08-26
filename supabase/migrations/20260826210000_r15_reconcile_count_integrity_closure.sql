begin;

-- Cross-stage database integrity closure.
-- Fixes the reconciliation result contract: counters must be cumulative across
-- every optional master relation, not overwritten by the last relation visited.
-- This is data-preserving and independent of Quality Gate/Quality Line status.

create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_table text;
  v_touched bigint:=0;
  v_scanned bigint:=0;
  v_table_scanned bigint:=0;
  v_table_touched bigint:=0;
  v_company_slug text;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;

  select slug into v_company_slug from public.companies where id=p_company_id;
  if v_company_slug is null then raise exception 'company_not_found'; end if;

  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r where r.company_id=$1',v_table
      ) into v_table_scanned using p_company_id;
      v_scanned:=v_scanned+coalesce(v_table_scanned,0);

      execute format(
        'update public.%I r set is_deleted=true, '
        ||'deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=coalesce(r.version,0)+1 '
        ||'where r.company_id=$1 and not coalesce(r.is_deleted,false) '
        ||'and public.erp_r15_pending_delete_exists($1,$2,r.id)',v_table
      ) using p_company_id,v_table;
      get diagnostics v_table_touched = row_count;
      v_touched:=v_touched+coalesce(v_table_touched,0);
    end if;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'companyId',p_company_id,
    'companySlug',v_company_slug,
    'scanned',v_scanned,
    'reconciled',v_touched,
    'checkedAt',timezone('utc',now()),
    'stateVersion',15
  );
end;
$$;

notify pgrst,'reload schema';
commit;
