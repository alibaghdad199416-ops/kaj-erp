begin;

-- Unique cloud command endpoint for the R35 client. Keeping a new function name
-- avoids stale PostgREST function-cache entries seen with the R28 endpoint.
create or replace function public.erp_r35_cloud_command(
  p_area text,p_action text,p_payload jsonb
) returns jsonb
language sql
security definer
set search_path=public
as $$ select public.erp_r27_cloud_command($1,$2,coalesce($3,'{}'::jsonb)) $$;
revoke all on function public.erp_r35_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r35_cloud_command(text,text,jsonb) to authenticated,service_role;

-- Canonical maintenance creation: sold-car identity comes from the approved
-- sales invoice/order chain, not the legacy erp_sales projection.
create or replace function public.erp_r35_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default now()
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid; v_car public.erp_cars%rowtype; v_totals jsonb;
  v_customer text; v_customer_name text; v_price numeric; v_warehouse text;
begin
  perform public.erp_active_company_context(p_company_id);
  perform public.erp_validate_operational_date(p_company_id,'maintenance',coalesce(p_effective_at,now()));
  if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then
    raise exception 'maintenance_input_invalid' using errcode='22023';
  end if;
  if coalesce(jsonb_typeof(p_parts),'null')<>'array' or jsonb_array_length(p_parts)=0 then
    raise exception 'maintenance_parts_required' using errcode='22023';
  end if;

  select * into v_car from public.erp_cars
  where company_id=p_company_id and id=p_car_id and not is_deleted
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',id)
  limit 1 for update;
  if not found then raise exception 'maintenance_vehicle_not_found' using errcode='23503'; end if;

  select o.customer_id into v_customer
  from public.erp_sales_order_items_cloud i
  join public.erp_sales_orders_cloud o on o.company_id=i.company_id and o.id=i.order_id and not o.is_deleted
  join public.erp_commercial_workflow_documents d on d.company_id=i.company_id and d.parent_id=i.order_id
    and d.module='sales' and d.document_type='invoice' and not d.is_deleted
    and lower(coalesce(d.status,'')) in ('approved','paid','completed')
  where i.company_id=p_company_id and i.item_type='car' and i.item_id=p_car_id and not i.is_deleted
  order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  limit 1;
  if v_customer is null then
    raise exception 'maintenance_requires_approved_sold_vehicle' using errcode='P0001';
  end if;

  select coalesce(nullif(data->>'name',''),nullif(data->>'fullName',''),
                  nullif(concat_ws(' ',data->>'firstName',data->>'lastName'),' '),v_customer)
  into v_customer_name
  from public.erp_customers where company_id=p_company_id and id=v_customer and not is_deleted limit 1;
  v_customer_name:=coalesce(v_customer_name,v_customer);

  if nullif(btrim(p_maintenance_expense_account_id),'') is not null then
    perform public.erp_phase2_account_guard(p_company_id,p_maintenance_expense_account_id,'expense',upper(p_currency_code));
  end if;

  v_warehouse:=coalesce(nullif(btrim(p_warehouse_id),''),nullif((
    select value->>'warehouse_id' from jsonb_array_elements(p_parts) value
    where nullif(value->>'warehouse_id','') is not null limit 1
  ),''));
  v_price:=case when p_pricing_type='paid' then p_sale_price else 0 end;

  insert into public.erp_maintenance_orders(
    company_id,order_number,car_id,source_car_id,car_name,customer_id,customer_name,
    warehouse_id,source_warehouse_id,is_sold_car,pricing_type,labor_cost,sale_price,
    maintenance_date,notes,currency_code,exchange_rate,maintenance_expense_account_id
  ) values(
    p_company_id,null,public.erp_stage3_stable_uuid(v_car.id),v_car.id,
    coalesce(nullif(v_car.data->>'displayName',''),nullif(v_car.data->>'name',''),
      nullif(concat_ws(' ',v_car.data->>'brand',v_car.data->>'model',v_car.data->>'year'),' '),v_car.id),
    case when v_customer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then v_customer::uuid else null end,
    v_customer_name,
    case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
    v_warehouse,true,case when p_pricing_type in ('paid','free') then p_pricing_type else 'paid' end,
    p_labor_cost,v_price,coalesce(p_effective_at,now()),nullif(btrim(p_notes),''),upper(p_currency_code),p_exchange_rate,
    nullif(btrim(p_maintenance_expense_account_id),'')
  ) returning id into v_id;

  v_totals:=public.erp_phase3_prepare_maintenance_lines(p_company_id,v_id,upper(p_currency_code),p_parts);
  update public.erp_maintenance_orders
  set parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),
      total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
      sale_price=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
      profit=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost)-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) else -(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) end,
      amount_usd=case when upper(p_currency_code)='USD' and pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
      amount_iqd=case when upper(p_currency_code)='IQD' and pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_id;
  return v_id;
end $$;
revoke all on function public.erp_r35_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_r35_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;

-- Opportunity state follows the authoritative sales workflow all the way to
-- approved delivery/invoice/payment instead of stopping at order approval.
create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,p_opportunity_id text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_slug text; o public.erp_sales_orders_cloud%rowtype;
  d public.erp_commercial_workflow_documents%rowtype;
  i public.erp_commercial_workflow_documents%rowtype;
  v_paid numeric:=0; v_remaining numeric:=0; v_status text:='pending'; v_closed timestamptz;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;
  select * into o from public.erp_sales_orders_cloud
  where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
  order by updated_at desc,created_at desc,id desc limit 1;
  if o.id is not null then
    select * into d from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales' and document_type='delivery'
      and not is_deleted and lower(coalesce(status,'')) in ('approved','delivered','completed')
    order by updated_at desc,created_at desc,id desc limit 1;
    select * into i from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales' and document_type='invoice'
      and not is_deleted and lower(coalesce(status,'')) in ('approved','paid','completed')
    order by updated_at desc,created_at desc,id desc limit 1;
    if i.id is not null then
      v_paid:=public.erp_try_numeric(i.payload->>'paidAmount',0);
      v_remaining:=public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0));
      v_status:='won'; v_closed:=coalesce(i.effective_at,i.updated_at,i.created_at,now());
    elsif d.id is not null then
      v_status:='pending';
    end if;
  end if;
  update public.erp_records set payload=payload||jsonb_build_object(
    'status',v_status,'closedAt',v_closed,
    'salesOrderId',case when o.id is null then null else o.id::text end,'salesOrderNumber',o.order_number,'salesOrderStatus',o.status,
    'deliveryId',case when d.id is null then null else d.id::text end,'deliveryNumber',d.document_number,'deliveryStatus',d.status,
    'invoiceId',case when i.id is null then null else i.id::text end,'invoiceNumber',i.document_number,'invoiceStatus',i.status,
    'invoiceCurrency',i.payload->>'currency','paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case when i.id is null then 'not_invoiced' when v_remaining<=0.001 then 'paid' when v_paid>0 then 'partial' else 'unpaid' end,
    'workflowLinked',o.id is not null,'workflowCanOpen',o.id is not null,
    'workflowCompleted',i.id is not null,'opportunityStatusSource','canonical_sales_invoice','updatedAt',now()
  ),updated_at=now()
  where company_id=v_slug and entity_type='opportunities' and record_id=p_opportunity_id and deleted_at is null;
end $$;
revoke all on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) from public,anon;
grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) to authenticated,service_role;

create or replace function public.erp_r35_sync_opportunity_from_workflow_document()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_opp text;
begin
  if new.module='sales' and new.document_type in ('delivery','invoice') then
    select opportunity_id into v_opp from public.erp_sales_orders_cloud
    where company_id=new.company_id and id=new.parent_id and not is_deleted;
    if nullif(btrim(coalesce(v_opp,'')),'') is not null then
      perform public.erp_sync_opportunity_sales_lifecycle(new.company_id,v_opp);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_r35_sync_opportunity_workflow on public.erp_commercial_workflow_documents;
create trigger trg_r35_sync_opportunity_workflow
after insert or update of status,payload,is_deleted on public.erp_commercial_workflow_documents
for each row execute function public.erp_r35_sync_opportunity_from_workflow_document();

-- Refresh all current opportunity projections immediately.
do $$ declare r record; begin
  for r in select distinct company_id,opportunity_id from public.erp_sales_orders_cloud
    where not is_deleted and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id); end loop;
end $$;

grant usage on schema public to authenticated,service_role;
notify pgrst,'reload schema';
commit;
