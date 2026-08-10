begin;

-- Quality Line ERP 17.60.0 compatibility-safe foundation.
-- The complete fixed-asset upgrade is applied by 20260729000200 because an
-- older erp_fixed_assets table already exists in production.

alter table public.erp_purchase_orders_cloud add column if not exists opportunity_id text;

create unique index if not exists erp_purchase_orders_one_active_opportunity_uq
on public.erp_purchase_orders_cloud(company_id,opportunity_id)
where opportunity_id is not null and btrim(opportunity_id)<>'' and not is_deleted;

create or replace function public.erp_sync_opportunity_from_purchase_order()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_status text; v_id text; v_number text;
begin
  v_id:=coalesce(new.opportunity_id,old.opportunity_id);
  if nullif(btrim(coalesce(v_id,'')),'') is null then return coalesce(new,old); end if;
  v_number:=coalesce(new.order_number,old.order_number,'');
  v_status:=case
    when coalesce(new.is_deleted,false) or lower(coalesce(new.status,'')) in ('cancelled','canceled','deleted','void','rejected') then 'lost'
    when lower(coalesce(new.status,''))='approved' then 'won'
    else 'pending' end;
  update public.erp_records
  set payload=payload||jsonb_build_object('status',v_status,'purchaseOrderId',coalesce(new.id,old.id)::text,
      'purchaseOrderNumber',v_number,'closedAt',case when v_status in ('won','lost') then now() else null end,'updatedAt',now()),
      updated_at=now()
  where company_id=coalesce(new.company_id,old.company_id) and entity_type='opportunities'
    and record_id=v_id and deleted_at is null;
  return coalesce(new,old);
end $$;

drop trigger if exists erp_purchase_order_opportunity_sync on public.erp_purchase_orders_cloud;
create trigger erp_purchase_order_opportunity_sync
after insert or update of status,is_deleted,opportunity_id,order_number
on public.erp_purchase_orders_cloud for each row execute function public.erp_sync_opportunity_from_purchase_order();

create or replace function public.erp_create_cloud_purchase_order(
  p_company_id uuid,p_supplier_id text,p_currency text,p_exchange_rate numeric,
  p_items jsonb,p_discount numeric default 0,p_notes text default null,p_opportunity_id text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_existing uuid;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is not null then
    select id into v_existing from public.erp_purchase_orders_cloud
    where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
    order by updated_at desc limit 1;
    if v_existing is not null then return v_existing; end if;
  end if;
  v_id:=public.erp_create_cloud_purchase_order(p_company_id,p_supplier_id,p_currency,p_exchange_rate,p_items,p_discount,p_notes);
  update public.erp_purchase_orders_cloud set opportunity_id=nullif(btrim(coalesce(p_opportunity_id,'')),'') where id=v_id;
  return v_id;
end $$;

-- Warehouse accounting metadata is persisted in the table's canonical JSON data.
create or replace function public.erp_post_scrap_warehouse_value(
  p_company_id uuid,p_movement_id text,p_warehouse_id text,p_direction text,
  p_amount numeric,p_currency text,p_inventory_account_id text,p_expense_account_id text,
  p_description text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_entry_id text:=gen_random_uuid()::text; v_entry jsonb; v_lines jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'لا توجد صلاحية على الشركة'; end if;
  if p_amount<=0 then raise exception 'قيمة حركة التوالف يجب أن تكون موجبة'; end if;
  if lower(p_direction) not in ('in','out') then raise exception 'اتجاه حركة التوالف غير صحيح'; end if;
  if exists(select 1 from public.erp_journal_entries where company_id=p_company_id and not is_deleted
      and data->>'referenceType'='scrap_warehouse' and data->>'referenceId'=p_movement_id) then
    select id::uuid into v_entry_id from public.erp_journal_entries where company_id=p_company_id and not is_deleted
      and data->>'referenceType'='scrap_warehouse' and data->>'referenceId'=p_movement_id limit 1;
    return v_entry_id::uuid;
  end if;
  v_entry:=jsonb_build_object('id',v_entry_id,'entryNumber','SCR-'||p_movement_id,'entryDate',current_date,
    'description',coalesce(p_description,'حركة مخزن توالف واستهلاك'),'referenceType','scrap_warehouse',
    'referenceId',p_movement_id,'currency',upper(p_currency),'createdAt',now());
  if lower(p_direction)='in' then
    v_lines:=jsonb_build_array(
      jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id,'accountId',p_expense_account_id,'debit',p_amount,'credit',0,'currency',upper(p_currency)),
      jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id,'accountId',p_inventory_account_id,'debit',0,'credit',p_amount,'currency',upper(p_currency)));
  else
    v_lines:=jsonb_build_array(
      jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id,'accountId',p_inventory_account_id,'debit',p_amount,'credit',0,'currency',upper(p_currency)),
      jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id,'accountId',p_expense_account_id,'debit',0,'credit',p_amount,'currency',upper(p_currency)));
  end if;
  perform public.erp_post_cloud_manual_journal(p_company_id,v_entry,v_lines);
  return v_entry_id::uuid;
end $$;

grant execute on function public.erp_create_cloud_purchase_order(uuid,text,text,numeric,jsonb,numeric,text,text) to authenticated;
grant execute on function public.erp_post_scrap_warehouse_value(uuid,text,text,text,numeric,text,text,text,text) to authenticated;

commit;
