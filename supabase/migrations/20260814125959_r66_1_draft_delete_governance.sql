begin;

create or replace function public.erp_r66_delete_commercial_draft(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_status text; v_permission text;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module' using errcode='22023';
  end if;
  v_permission:=case when p_module='sales' then 'sales.delete' else 'purchases.delete' end;
  if not public.erp_cloud_user_has_permission(p_company_id,v_permission)
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;
  if p_module='sales' then
    select lower(status) into v_status from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  else
    select lower(status) into v_status from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  end if;
  if not found then raise exception 'order_not_found' using errcode='P0001'; end if;
  if v_status<>'draft' then
    raise exception 'draft_delete_only:use_cancel_reverse' using errcode='P0001';
  end if;
  if exists(select 1 from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module
      and not d.is_deleted) then
    raise exception 'draft_has_linked_business_history:use_cancel_reverse' using errcode='P0001';
  end if;
  return case when p_module='sales'
    then public.erp_delete_cloud_sales_order_v4(p_company_id,p_order_id)
    else public.erp_delete_cloud_purchase_order_v3(p_company_id,p_order_id) end;
end $$;

create or replace function public.erp_r66_delete_maintenance_draft(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_stage text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.delete')
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:maintenance.delete' using errcode='42501';
  end if;
  select lower(coalesce(workflow_stage,status)) into v_stage
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0001'; end if;
  if v_stage not in ('draft','order_draft') then
    raise exception 'draft_delete_only:use_cancel_reverse' using errcode='P0001';
  end if;
  if exists(select 1 from public.erp_maintenance_parts p
      where p.company_id=p_company_id and p.maintenance_order_id=p_order_id and not p.is_deleted)
    or exists(select 1 from public.erp_maintenance_payments p
      where p.company_id=p_company_id and p.maintenance_order_id=p_order_id and not p.is_deleted)
    or exists(select 1 from public.erp_maintenance_material_issues d
      where d.company_id=p_company_id and d.maintenance_order_id=p_order_id and not d.is_deleted) then
    raise exception 'draft_has_linked_business_history:use_cancel_reverse' using errcode='P0001';
  end if;
  return public.erp_delete_cloud_maintenance_order_v3(p_company_id,p_order_id,p_reason);
end $$;

revoke all on function public.erp_r66_delete_commercial_draft(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r66_delete_commercial_draft(uuid,uuid,text)
  to authenticated,service_role;
revoke all on function public.erp_r66_delete_maintenance_draft(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r66_delete_maintenance_draft(uuid,uuid,text)
  to authenticated,service_role;

commit;
