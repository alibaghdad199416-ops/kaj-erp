create or replace function public.erp_r37_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid; v_car public.erp_cars%rowtype; v_totals jsonb:=jsonb_build_object('costTotal',0,'priceTotal',0);
  v_customer text; v_customer_name text; v_price numeric; v_warehouse text; v_parts jsonb:=coalesce(p_parts,'[]'::jsonb);
begin
  perform public.erp_active_company_context(p_company_id);
  perform public.erp_validate_operational_date(p_company_id,'maintenance',coalesce(p_effective_at,now()));
  if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then
    raise exception 'maintenance_input_invalid' using errcode='22023';
  end if;
  if jsonb_typeof(v_parts)<>'array' then raise exception 'maintenance_parts_invalid' using errcode='22023'; end if;

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
  if v_customer is null then raise exception 'maintenance_requires_approved_sold_vehicle' using errcode='P0001'; end if;

  select coalesce(nullif(data->>'name',''),nullif(data->>'fullName',''),
                  nullif(concat_ws(' ',data->>'firstName',data->>'lastName'),' '),v_customer)
  into v_customer_name from public.erp_customers
  where company_id=p_company_id and id=v_customer and not is_deleted limit 1;
  v_customer_name:=coalesce(v_customer_name,v_customer);

  if nullif(btrim(p_maintenance_expense_account_id),'') is not null then
    perform public.erp_phase2_account_guard(p_company_id,p_maintenance_expense_account_id,'expense',upper(p_currency_code));
  end if;
  v_warehouse:=coalesce(nullif(btrim(p_warehouse_id),''),nullif((
    select value->>'warehouse_id' from jsonb_array_elements(v_parts) value
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

  if jsonb_array_length(v_parts)>0 then
    v_totals:=public.erp_phase3_prepare_maintenance_lines(p_company_id,v_id,upper(p_currency_code),v_parts);
  end if;
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
revoke all on function public.erp_r37_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_r37_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;
notify pgrst,'reload schema';
