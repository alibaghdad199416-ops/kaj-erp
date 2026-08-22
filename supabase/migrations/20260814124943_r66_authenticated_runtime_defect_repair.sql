begin;

-- Post-delivery invoice validation must validate immutable approved delivery
-- allocations. Current stock/car location is checked only while creating the
-- physical Sales delivery.
create or replace function public.erp_validate_commercial_warehouse_allocations(
  p_company_id uuid,p_order_id uuid,p_module text,p_allocations jsonb,
  p_check_sales_stock boolean default true
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  a record; v_ordered numeric; v_available numeric;
  v_expected_type text; v_description text; v_car_warehouse text;
  v_car_status text; v_normalized jsonb:='[]';
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  if jsonb_typeof(coalesce(p_allocations,'null'))<>'array' or jsonb_array_length(p_allocations)=0
    then raise exception 'warehouse_allocations_required'; end if;
  for a in select * from jsonb_to_recordset(p_allocations) as x(
    "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
  loop
    a."itemType":=lower(btrim(coalesce(a."itemType",'')));
    a."itemId":=btrim(coalesce(a."itemId",''));
    a."warehouseId":=btrim(coalesce(a."warehouseId",''));
    if a."itemType" not in ('car','product') or a."itemId"='' or a."warehouseId"=''
      or coalesce(a.quantity,0)<=0 or a.quantity<>trunc(a.quantity)
      then raise exception 'invalid_warehouse_allocation'; end if;
    if not exists(select 1 from public.erp_warehouses w where w.company_id=p_company_id
      and w.id=a."warehouseId" and not w.is_deleted
      and public.erp_try_boolean(w.data->>'isActive',true))
      then raise exception 'warehouse_not_found_or_inactive'; end if;
    if p_module='sales' then
      select item_type,quantity,description into v_expected_type,v_ordered,v_description
      from public.erp_sales_order_items_cloud where company_id=p_company_id
        and order_id=p_order_id and not is_deleted and item_id=a."itemId";
    else
      select item_type,quantity,description into v_expected_type,v_ordered,v_description
      from public.erp_purchase_order_items_cloud where company_id=p_company_id
        and order_id=p_order_id and not is_deleted and item_id=a."itemId";
    end if;
    if not found or v_expected_type<>a."itemType"
      then raise exception 'commercial_order_item_mismatch:%',a."itemId"; end if;
    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'itemType',a."itemType",'itemId',a."itemId",'description',v_description,
      'warehouseId',a."warehouseId",'quantity',trunc(a.quantity)::int));
  end loop;
  if p_module='sales' and p_check_sales_stock then
    for a in select x."itemType",x."itemId",x."warehouseId",sum(x.quantity) quantity
      from jsonb_to_recordset(v_normalized)
        as x("itemType" text,"itemId" text,"warehouseId" text,quantity numeric)
      group by 1,2,3
    loop
      if a."itemType"='product' then
        select coalesce(sum(greatest(public.erp_try_numeric(data->>'quantity',0)-
          public.erp_try_numeric(data->>'reservedQuantity',0),0)),0) into v_available
        from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted
          and data->>'productId'=a."itemId" and data->>'warehouseId'=a."warehouseId";
        if v_available<a.quantity
          then raise exception 'insufficient_warehouse_stock:%',a."itemId"; end if;
      else
        select coalesce(data->>'warehouseId',data->>'warehouse_id'),
          lower(btrim(coalesce(data->>'status','')))
          into v_car_warehouse,v_car_status from public.erp_cars
          where company_id=p_company_id and id=a."itemId" and not is_deleted;
        if not found or v_car_warehouse is distinct from a."warehouseId"
          then raise exception 'car_warehouse_mismatch'; end if;
        if v_car_status not in ('available','selling','pending_sale','متوفرة','متوفر','متاحة','متاح','قيد البيع')
          then raise exception 'car_not_available'; end if;
      end if;
    end loop;
  end if;
  return v_normalized;
end $$;

-- Saved notifications are shared event rows. Deletion is a recipient-local
-- tombstone and never mutates the shared event or its business source.
alter table public.erp_notification_user_states
  add column if not exists deleted boolean not null default false,
  add column if not exists deleted_at timestamptz;

create or replace function public.erp_r49_list_cloud_notifications(
  p_company_id uuid,p_unread_only boolean default false,
  p_limit integer default 100,p_offset integer default 0
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key();
begin
  perform public.erp_active_company_context(p_company_id);
  if v_key is null then raise exception 'notification_user_identity_required' using errcode='42501'; end if;
  return query select n.data||jsonb_build_object(
    'id',n.id,'createdAt',coalesce(n.data->>'createdAt',n.created_at::text),
    'updatedAt',n.updated_at::text,'isRead',coalesce(s.is_read,false))
  from public.erp_enterprise_notifications n
  left join public.erp_notification_user_states s
    on s.company_id=n.company_id and s.notification_id=n.id and s.user_key=v_key
  where n.company_id=p_company_id and not n.is_deleted
    and public.erp_r49_notification_visible(p_company_id,n.data)
    and not coalesce(s.archived,false) and not coalesce(s.deleted,false)
    and (not coalesce(p_unread_only,false) or not coalesce(s.is_read,false))
  order by coalesce(s.is_read,false),n.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500))
  offset greatest(coalesce(p_offset,0),0);
end $$;

create or replace function public.erp_r49_cloud_unread_notification_count(p_company_id uuid)
returns integer language plpgsql stable security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key(); v_count integer;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_key is null then raise exception 'notification_user_identity_required' using errcode='42501'; end if;
  select count(*)::integer into v_count from public.erp_enterprise_notifications n
  left join public.erp_notification_user_states s
    on s.company_id=n.company_id and s.notification_id=n.id and s.user_key=v_key
  where n.company_id=p_company_id and not n.is_deleted
    and public.erp_r49_notification_visible(p_company_id,n.data)
    and not coalesce(s.archived,false) and not coalesce(s.deleted,false)
    and not coalesce(s.is_read,false);
  return coalesce(v_count,0);
end $$;

create or replace function public.erp_r66_delete_cloud_notification(
  p_company_id uuid,p_notification_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key(); v_data jsonb; v_was_read boolean;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_key is null then raise exception 'notification_user_identity_required' using errcode='42501'; end if;
  select data into v_data from public.erp_enterprise_notifications
  where company_id=p_company_id and id=p_notification_id and not is_deleted;
  if not found or not public.erp_r49_notification_visible(p_company_id,v_data)
    then raise exception 'notification_not_found_or_forbidden' using errcode='42501'; end if;
  select coalesce(is_read,false) into v_was_read from public.erp_notification_user_states
  where company_id=p_company_id and notification_id=p_notification_id and user_key=v_key;
  insert into public.erp_notification_user_states(
    company_id,notification_id,user_key,is_read,deleted,deleted_at,updated_at)
  values(p_company_id,p_notification_id,v_key,coalesce(v_was_read,false),true,now(),now())
  on conflict(company_id,notification_id,user_key) do update
    set deleted=true,deleted_at=coalesce(erp_notification_user_states.deleted_at,excluded.deleted_at),updated_at=now();
  return jsonb_build_object('ok',true,'notificationId',p_notification_id,
    'deletedForUser',v_key,'wasUnread',not coalesce(v_was_read,false));
end $$;

revoke all on function public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean)
  from public,anon,authenticated;
grant execute on function public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean)
  to service_role;
revoke all on function public.erp_r66_delete_cloud_notification(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.erp_r66_delete_cloud_notification(uuid,uuid)
  to authenticated,service_role;

commit;
