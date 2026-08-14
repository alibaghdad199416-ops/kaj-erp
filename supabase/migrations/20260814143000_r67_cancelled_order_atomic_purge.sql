begin;

-- Cancellation owns reversal; deletion of a cancelled lifecycle only retires
-- the already-reversed records.  The private marker lets the established
-- delete-owned reversal helpers run beneath maintenance.cancel without
-- granting maintenance.delete to the caller.
create table if not exists erp_private.maintenance_cancel_contexts (
  transaction_id bigint not null,
  user_id uuid not null,
  company_id uuid not null,
  order_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(transaction_id,user_id,company_id,order_id)
);
alter table erp_private.maintenance_cancel_contexts enable row level security;
revoke all on table erp_private.maintenance_cancel_contexts from public,anon,authenticated;

create or replace function public.erp_require_any_cloud_permission(
  p_company_id uuid,p_permissions text[]
) returns void language plpgsql stable security definer set search_path=public as $$
declare p text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant_denied' using errcode='42501';
  end if;
  if auth.uid() is not null and (
    exists(select 1 from erp_private.commercial_cancel_contexts c
      where c.transaction_id=txid_current() and c.user_id=auth.uid()
        and c.company_id=p_company_id)
    or exists(select 1 from erp_private.maintenance_cancel_contexts c
      where c.transaction_id=txid_current() and c.user_id=auth.uid()
        and c.company_id=p_company_id)
  ) then return; end if;
  foreach p in array p_permissions loop
    if public.erp_cloud_user_has_permission(p_company_id,p) then return; end if;
  end loop;
  raise exception 'operation_permission_required' using errcode='42501';
end $$;

create or replace function public.erp_r67_cancel_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_stage text; v_reason text:=coalesce(nullif(btrim(p_reason),''),'Maintenance order cancelled');
  v_result jsonb; v_active_part_ids uuid[];
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.cancel')
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:maintenance.cancel' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_company_id::text||':maintenance:cancel-order:'||p_order_id::text,0));
  select lower(coalesce(workflow_stage,status)) into v_stage
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0001'; end if;
  if v_stage='cancelled' then
    return jsonb_build_object('ok',true,'status','cancelled','idempotent',true,
      'paymentsPreserved',true);
  end if;
  if v_stage in ('draft','order_draft') then
    raise exception 'draft_does_not_require_cancellation' using errcode='P0001';
  end if;
  select coalesce(array_agg(id),'{}'::uuid[]) into v_active_part_ids
  from public.erp_maintenance_parts
  where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;

  insert into erp_private.maintenance_cancel_contexts(
    transaction_id,user_id,company_id,order_id
  ) values(txid_current(),auth.uid(),p_company_id,p_order_id);

  v_result:=public.erp_delete_cloud_maintenance_order_v3(
    p_company_id,p_order_id,v_reason);

  update public.erp_maintenance_orders set
    workflow_stage='cancelled',status='cancelled',is_deleted=false,
    deleted_at=null,cancelled_at=coalesce(cancelled_at,now()),
    cancel_reason=v_reason,updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  update public.erp_maintenance_parts set
    is_deleted=false,deleted_at=null,updated_at=now()
  where company_id=p_company_id and maintenance_order_id=p_order_id
    and id=any(v_active_part_ids);

  delete from erp_private.maintenance_cancel_contexts c
  where c.transaction_id=txid_current() and c.user_id=auth.uid()
    and c.company_id=p_company_id and c.order_id=p_order_id;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'status','cancelled','orderPreserved',true,
    'paymentsPreserved',true,'reason',v_reason);
end $$;

create or replace function public.erp_r67_delete_commercial_order(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_status text; v_deleted boolean; v_permission text;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module' using errcode='22023';
  end if;
  v_permission:=p_module||'.delete';
  if not public.erp_cloud_user_has_permission(p_company_id,v_permission)
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;
  if p_module='sales' then
    select lower(status),is_deleted into v_status,v_deleted
    from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id for update;
  else
    select lower(status),is_deleted into v_status,v_deleted
    from public.erp_purchase_orders_cloud where company_id=p_company_id and id=p_order_id for update;
  end if;
  if not found or v_deleted then
    return jsonb_build_object('deleted',true,'alreadyDeleted',true,
      'paymentsPreserved',true,'module',p_module,'orderId',p_order_id);
  end if;
  if v_status='draft' then
    return public.erp_r66_delete_commercial_draft(p_company_id,p_order_id,p_module);
  end if;
  if v_status<>'cancelled' then
    raise exception 'cancel_required_before_delete' using errcode='P0001';
  end if;
  return case when p_module='sales'
    then public.erp_delete_cloud_sales_order_v3(p_company_id,p_order_id)
    else public.erp_delete_cloud_purchase_order_v3(p_company_id,p_order_id) end;
end $$;

create or replace function public.erp_r67_delete_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_stage text; v_deleted boolean;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.delete')
    and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:maintenance.delete' using errcode='42501';
  end if;
  select lower(coalesce(workflow_stage,status)),is_deleted into v_stage,v_deleted
  from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id for update;
  if not found or v_deleted then
    return jsonb_build_object('deleted',true,'alreadyDeleted',true,
      'paymentsPreserved',true,'module','maintenance','orderId',p_order_id);
  end if;
  if v_stage in ('draft','order_draft') then
    return public.erp_r66_delete_maintenance_draft(p_company_id,p_order_id,p_reason);
  end if;
  if v_stage<>'cancelled' then
    raise exception 'cancel_required_before_delete' using errcode='P0001';
  end if;
  return public.erp_delete_cloud_maintenance_order_v3(p_company_id,p_order_id,p_reason);
end $$;

revoke all on function public.erp_r67_cancel_maintenance_order(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r67_cancel_maintenance_order(uuid,uuid,text)
  to authenticated,service_role;
revoke all on function public.erp_r67_delete_commercial_order(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r67_delete_commercial_order(uuid,uuid,text)
  to authenticated,service_role;
revoke all on function public.erp_r67_delete_maintenance_order(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r67_delete_maintenance_order(uuid,uuid,text)
  to authenticated,service_role;
revoke all on function public.erp_require_any_cloud_permission(uuid,text[])
  from public,anon,authenticated;
grant execute on function public.erp_require_any_cloud_permission(uuid,text[])
  to service_role;

commit;
