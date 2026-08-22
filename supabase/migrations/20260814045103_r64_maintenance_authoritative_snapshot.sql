begin;

-- One Flutter-facing call, and therefore one PostgreSQL statement snapshot,
-- owns the complete Maintenance dialog read.  Existing bounded R9/R57 helpers
-- remain the canonical projections and execute within this statement snapshot.
create or replace function public.erp_r64_get_maintenance_order_snapshot(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_order jsonb;
  v_lines jsonb;
  v_reconciliation jsonb;
  v_issue_state jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;

  select row_value into v_order
  from public.erp_r9_list_cloud_maintenance_orders(p_company_id) row_value
  where row_value->>'id'=p_order_id::text
  limit 1;
  if v_order is null then
    raise exception 'maintenance_order_not_found' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(row_value),'[]'::jsonb) into v_lines
  from public.erp_r9_get_cloud_maintenance_order_lines(
    p_company_id,p_order_id
  ) row_value;
  v_reconciliation:=public.erp_r57_maintenance_cost_reconciliation(
    p_company_id,p_order_id
  );
  v_issue_state:=public.erp_r57_maintenance_material_issue_state(
    p_company_id,p_order_id
  );

  return jsonb_build_object(
    'order',v_order,
    'lines',coalesce(v_lines,'[]'::jsonb),
    'reconciliation',coalesce(v_reconciliation,'{}'::jsonb),
    'issueState',coalesce(v_issue_state,'{}'::jsonb),
    'snapshotAt',statement_timestamp()
  );
end;
$$;

revoke all on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
