begin;

-- The shared validator is also used to replay approved logistics while posting
-- invoices. Remove only R59's creation-capacity clause from that shared path;
-- a table trigger below owns the new-document invariant atomically.
do $$
declare v_definition text; v_old text;
begin
  select pg_get_functiondef('public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean)'::regprocedure)
    into v_definition;
  v_old:='    v_fulfilled:=public.erp_r59_commercial_fulfilled_quantity(p_company_id,p_order_id,p_module,a."itemType",a."itemId");'||chr(10)||
    '    if v_fulfilled+a.quantity>v_ordered then raise exception ''commercial_over_fulfillment:%'',a."itemId"; end if;'||chr(10)||
    '    if a."itemType"=''car'' and (a.quantity<>1 or v_ordered<>1 or v_fulfilled<>0) then raise exception ''car_allocation_must_be_unique''; end if;';
  if strpos(v_definition,v_old)=0 then raise exception 'r59_validator_capacity_clause_not_found'; end if;
  execute replace(v_definition,v_old,'');
end $$;

create or replace function public.erp_r59_guard_new_commercial_logistics()
returns trigger language plpgsql security definer set search_path=public as $$
declare a record; v_ordered numeric; v_fulfilled numeric;
begin
  if new.module not in ('sales','purchases') or new.document_type not in ('delivery','receipt')
     or new.status<>'draft' or new.is_deleted then return new; end if;
  if (new.module='sales') is distinct from (new.document_type='delivery') then
    raise exception 'commercial_logistics_module_type_mismatch';
  end if;
  for a in select x."itemType",x."itemId",sum(x.quantity) quantity
    from jsonb_to_recordset(coalesce(new.payload->'allocations','[]'::jsonb))
      as x("itemType" text,"itemId" text,"warehouseId" text,quantity numeric)
    group by 1,2
  loop
    if new.module='sales' then
      select quantity into v_ordered from public.erp_sales_order_items_cloud
      where company_id=new.company_id and order_id=new.parent_id and not is_deleted
        and item_type=a."itemType" and item_id=a."itemId";
    else
      select quantity into v_ordered from public.erp_purchase_order_items_cloud
      where company_id=new.company_id and order_id=new.parent_id and not is_deleted
        and item_type=a."itemType" and item_id=a."itemId";
    end if;
    if not found then raise exception 'commercial_order_item_mismatch:%',a."itemId"; end if;
    v_fulfilled:=public.erp_r59_commercial_fulfilled_quantity(
      new.company_id,new.parent_id,new.module,a."itemType",a."itemId");
    if v_fulfilled+a.quantity>v_ordered then
      raise exception 'commercial_over_fulfillment:%',a."itemId" using errcode='23514';
    end if;
    if a."itemType"='car' and (a.quantity<>1 or v_ordered<>1 or v_fulfilled<>0) then
      raise exception 'car_allocation_must_be_unique' using errcode='23514';
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists erp_r59_guard_new_commercial_logistics on public.erp_commercial_workflow_documents;
create trigger erp_r59_guard_new_commercial_logistics
before insert on public.erp_commercial_workflow_documents
for each row execute function public.erp_r59_guard_new_commercial_logistics();

revoke all on function public.erp_r59_guard_new_commercial_logistics() from public,anon,authenticated;

commit;
