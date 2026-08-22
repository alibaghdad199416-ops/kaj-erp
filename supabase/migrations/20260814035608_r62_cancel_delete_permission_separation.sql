begin;

-- A cancellation is governed by *.cancel, while a destructive draft deletion
-- remains governed by *.delete.  The established reversal chain contains
-- delete-owned helpers, so an inaccessible transaction marker authorizes only
-- the nested work of a cancellation that already passed its exact permission.
create schema if not exists erp_private authorization postgres;
revoke all on schema erp_private from public,anon,authenticated;

create table if not exists erp_private.commercial_cancel_contexts (
  transaction_id bigint not null,
  user_id uuid not null,
  company_id uuid not null,
  order_id uuid not null,
  module text not null check (module in ('sales','purchases')),
  created_at timestamptz not null default clock_timestamp(),
  primary key(transaction_id,user_id,company_id,order_id,module)
);
alter table erp_private.commercial_cancel_contexts enable row level security;
revoke all on table erp_private.commercial_cancel_contexts from public,anon,authenticated;

create or replace function public.erp_require_any_cloud_permission(
  p_company_id uuid,p_permissions text[]
) returns void
language plpgsql
stable
security definer
set search_path=public
as $$
declare p text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant_denied' using errcode='42501';
  end if;

  -- Only the authoritative R62 function can create this row.  Browser roles
  -- have neither schema usage nor table privileges, and no public helper can
  -- mint a context.  This is intentionally broad for nested reversal helpers
  -- because a SQL function call cannot be interleaved by its caller.
  if auth.uid() is not null and exists(
    select 1 from erp_private.commercial_cancel_contexts c
    where c.transaction_id=txid_current()
      and c.user_id=auth.uid()
      and c.company_id=p_company_id
  ) then
    return;
  end if;

  foreach p in array p_permissions loop
    if public.erp_cloud_user_has_permission(p_company_id,p) then return; end if;
  end loop;
  raise exception 'operation_permission_required' using errcode='42501';
end;
$$;

create or replace function public.erp_r62_cancel_commercial_order(
  p_company_id uuid,p_order_id uuid,p_module text,p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_status text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Order cancelled');
  v_permission text;
  v_result jsonb;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module' using errcode='22023';
  end if;
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant_denied' using errcode='42501';
  end if;
  v_permission:=p_module||'.cancel';
  if not public.erp_cloud_user_has_permission(p_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_company_id::text||':'||p_module||':cancel-order:'||p_order_id::text,0
  ));
  if p_module='sales' then
    select lower(status) into v_status from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=p_order_id for update;
  else
    select lower(status) into v_status from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=p_order_id for update;
  end if;
  if not found then raise exception 'order_not_found' using errcode='P0001'; end if;
  if v_status='cancelled' then
    return jsonb_build_object('ok',true,'status','cancelled','idempotent',true);
  end if;

  insert into erp_private.commercial_cancel_contexts(
    transaction_id,user_id,company_id,order_id,module
  ) values(txid_current(),auth.uid(),p_company_id,p_order_id,p_module);

  if p_module='sales' then
    v_result:=public.erp_delete_cloud_sales_order_v3(p_company_id,p_order_id);
    update public.erp_sales_orders_cloud set status='cancelled',is_deleted=false,
      deleted_at=null,notes=concat_ws(E'\n',nullif(notes,''),'CANCEL: '||v_reason),
      updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_order_id;
    update public.erp_sales_order_items_cloud set is_deleted=false,
      deleted_at=null,updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and order_id=p_order_id;
  else
    v_result:=public.erp_delete_cloud_purchase_order_v3(p_company_id,p_order_id);
    update public.erp_purchase_orders_cloud set status='cancelled',is_deleted=false,
      deleted_at=null,notes=concat_ws(E'\n',nullif(notes,''),'CANCEL: '||v_reason),
      updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_order_id;
    update public.erp_purchase_order_items_cloud set is_deleted=false,
      deleted_at=null,updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and order_id=p_order_id;
  end if;

  delete from erp_private.commercial_cancel_contexts c
  where c.transaction_id=txid_current() and c.user_id=auth.uid()
    and c.company_id=p_company_id and c.order_id=p_order_id and c.module=p_module;

  perform public.erp_commercial_audit(
    p_company_id,p_module,p_order_id,p_order_id,null,
    'cancel_order',v_status,'cancelled',v_reason
  );
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'status','cancelled','orderPreserved',true,
    'paymentsPreserved',true,'permission',v_permission,'reason',v_reason
  );
end;
$$;

-- Preserve the R61 RPC contract for older clients, but route every call through
-- the corrected exact-permission authority.
create or replace function public.erp_r61_cancel_commercial_order(
  p_company_id uuid,p_order_id uuid,p_module text,p_reason text default null
) returns jsonb
language sql
security definer
set search_path=public
as $$
  select public.erp_r62_cancel_commercial_order(
    p_company_id,p_order_id,p_module,p_reason
  )
$$;

-- One database statement now supplies the complete commercial details and its
-- quantitative reconciliation.  Both component functions execute under the
-- same PostgreSQL statement snapshot, preventing a dialog refresh from mixing
-- two transaction moments.
create or replace function public.erp_r62_get_commercial_order_snapshot(
  p_company_id uuid,p_order_id uuid,p_purchase boolean
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_details jsonb;
  v_reconciliation jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  v_details:=public.erp_r28_get_commercial_order_complete_details(
    p_company_id,p_order_id,p_purchase
  );
  select coalesce(jsonb_agg(row_value),'[]'::jsonb)
    into v_reconciliation
  from public.erp_r57_commercial_reconciliation(
    p_company_id,p_order_id,case when p_purchase then 'purchases' else 'sales' end
  ) as row_value;
  return jsonb_set(
    coalesce(v_details,'{}'::jsonb),
    '{reconciliation}',coalesce(v_reconciliation,'[]'::jsonb),true
  );
end;
$$;

revoke all on function public.erp_r62_cancel_commercial_order(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.erp_r62_cancel_commercial_order(uuid,uuid,text,text)
  to authenticated,service_role;
revoke all on function public.erp_r61_cancel_commercial_order(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.erp_r61_cancel_commercial_order(uuid,uuid,text,text)
  to authenticated,service_role;
revoke all on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  from public,anon,authenticated;
grant execute on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  to authenticated,service_role;
revoke all on function public.erp_require_any_cloud_permission(uuid,text[])
  from public,anon,authenticated;
grant execute on function public.erp_require_any_cloud_permission(uuid,text[])
  to service_role;

commit;
