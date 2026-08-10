-- Quality Line ERP 17.63.4
-- Repair opportunity lifecycle synchronization with sales orders.
begin;

create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,
  p_opportunity_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_order public.erp_sales_orders_cloud%rowtype;
  v_status text := 'pending';
  v_closed_at timestamptz;
  v_order_id text;
  v_order_number text;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then
    return;
  end if;

  select slug into v_slug
  from public.companies
  where id=p_company_id;

  if v_slug is null then
    return;
  end if;

  select * into v_order
  from public.erp_sales_orders_cloud
  where company_id=p_company_id
    and opportunity_id=p_opportunity_id
    and not is_deleted
  order by
    case when lower(coalesce(status,''))='approved' then 0 else 1 end,
    updated_at desc,
    created_at desc,
    id desc
  limit 1;

  if found and lower(coalesce(v_order.status,''))='approved' then
    v_status := 'won';
    v_closed_at := now();
    v_order_id := v_order.id::text;
    v_order_number := v_order.order_number;
  else
    -- A draft, reopened, cancelled, deleted, or detached sales order must not
    -- leave the opportunity won/lost. It returns to the pending pipeline.
    v_status := 'pending';
    v_closed_at := null;
    if found then
      v_order_id := v_order.id::text;
      v_order_number := v_order.order_number;
    end if;
  end if;

  update public.erp_records
  set payload = payload || jsonb_build_object(
        'status',v_status,
        'salesOrderId',v_order_id,
        'salesOrderNumber',v_order_number,
        'saleId',v_order_id,
        'invoiceNumber',v_order_number,
        'closedAt',v_closed_at,
        'opportunityStatusSource','sales_order',
        'updatedAt',now()
      ),
      updated_at=now()
  where company_id=v_slug
    and entity_type='opportunities'
    and record_id=p_opportunity_id
    and deleted_at is null;
end;
$$;

create or replace function public.erp_sales_order_opportunity_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  -- Synchronize the old link first when an order is detached, moved to another
  -- opportunity, or soft-deleted.
  if tg_op='UPDATE'
     and nullif(btrim(coalesce(old.opportunity_id,'')),'') is not null
     and (
       old.opportunity_id is distinct from new.opportunity_id
       or old.is_deleted is distinct from new.is_deleted
     ) then
    perform public.erp_sync_opportunity_sales_lifecycle(
      old.company_id,
      old.opportunity_id
    );
  end if;

  if tg_op='DELETE' then
    perform public.erp_sync_opportunity_sales_lifecycle(
      old.company_id,
      old.opportunity_id
    );
    return old;
  end if;

  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is not null then
    perform public.erp_sync_opportunity_sales_lifecycle(
      new.company_id,
      new.opportunity_id
    );
  end if;

  return new;
end;
$$;

drop trigger if exists erp_sales_order_opportunity_sync
on public.erp_sales_orders_cloud;

create trigger erp_sales_order_opportunity_sync
after insert or update of status,is_deleted,opportunity_id,order_number or delete
on public.erp_sales_orders_cloud
for each row
execute function public.erp_sales_order_opportunity_sync_trigger();

grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text)
to authenticated;

-- Repair existing records immediately when this migration is applied.
do $$
declare r record;
begin
  for r in
    select distinct company_id,opportunity_id
    from public.erp_sales_orders_cloud
    where opportunity_id is not null and btrim(opportunity_id)<>''
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(
      r.company_id,
      r.opportunity_id
    );
  end loop;
end;
$$;

commit;
