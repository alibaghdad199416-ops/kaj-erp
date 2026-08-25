begin;

create or replace function public.erp_r39_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_car_id text;
begin
  select c.id into v_car_id
  from public.erp_cars c
  where c.company_id=p_company_id and not c.is_deleted
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',c.id)
    and (
      c.id=p_car_id or
      nullif(c.data->>'carId','')=p_car_id or nullif(c.data->>'car_id','')=p_car_id or
      nullif(c.data->>'vehicleId','')=p_car_id or nullif(c.data->>'vehicle_id','')=p_car_id
    )
  order by case when c.id=p_car_id then 0 else 1 end,c.updated_at desc
  limit 1;
  if v_car_id is null then
    raise exception 'maintenance_vehicle_not_found' using errcode='23503';
  end if;
  return public.erp_r37_create_cloud_maintenance_order(
    p_company_id,v_car_id,p_warehouse_id,p_pricing_type,p_labor_cost,p_sale_price,
    upper(p_currency_code),p_exchange_rate,p_notes,coalesce(p_parts,'[]'::jsonb),
    p_maintenance_expense_account_id,p_effective_at
  );
end $$;

create or replace function public.erp_r39_update_cloud_maintenance_draft(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_snapshot jsonb; v_target_stage text; v_current_stage text; v_payment jsonb;
  v_guard integer:=0; v_paid numeric:=0; v_totals jsonb:=jsonb_build_object('costTotal',0,'priceTotal',0);
  v_parts jsonb:=coalesce(p_parts,'[]'::jsonb); v_order public.erp_maintenance_orders%rowtype;
  v_effective_at timestamptz; v_warehouse text; v_price numeric;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.update']);
  if jsonb_typeof(v_parts)<>'array' then raise exception 'maintenance_parts_invalid' using errcode='22023'; end if;
  if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then raise exception 'maintenance_input_invalid' using errcode='22023'; end if;

  v_snapshot:=public.erp_v67_prepare_maintenance_linked_edit(
    p_company_id,p_order_id,'Edit maintenance order and rebuild all generated links'
  );
  v_target_stage:=coalesce(v_snapshot->>'workflowStage','order_draft');

  select * into v_order from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='23503'; end if;
  v_effective_at:=coalesce(p_effective_at,v_order.maintenance_date,now());
  perform public.erp_validate_operational_date(p_company_id,'maintenance',v_effective_at);
  if nullif(btrim(p_maintenance_expense_account_id),'') is not null then
    perform public.erp_phase2_account_guard(p_company_id,p_maintenance_expense_account_id,'expense',upper(p_currency_code));
  end if;

  if jsonb_array_length(v_parts)>0 then
    v_totals:=public.erp_phase3_prepare_maintenance_lines(p_company_id,p_order_id,upper(p_currency_code),v_parts);
  else
    update public.erp_maintenance_parts
       set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
     where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
  end if;

  v_warehouse:=coalesce(
    nullif(btrim(p_warehouse_id),''),
    nullif((select value->>'warehouse_id' from jsonb_array_elements(v_parts) value
      where nullif(value->>'warehouse_id','') is not null limit 1),''),
    v_order.source_warehouse_id,v_order.warehouse_id::text
  );
  v_price:=case when p_pricing_type='paid' then
    greatest(p_sale_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost)
    else 0 end;

  update public.erp_maintenance_orders set
    warehouse_id=case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
    source_warehouse_id=v_warehouse,
    pricing_type=case when p_pricing_type in ('paid','free') then p_pricing_type else 'paid' end,
    labor_cost=p_labor_cost,
    parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),
    total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
    sale_price=v_price,
    profit=v_price-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost),
    currency_code=upper(p_currency_code),exchange_rate=p_exchange_rate,
    amount_usd=case when upper(p_currency_code)='USD' then v_price else 0 end,
    amount_iqd=case when upper(p_currency_code)='IQD' then v_price else 0 end,
    maintenance_date=v_effective_at,notes=nullif(btrim(p_notes),''),
    maintenance_expense_account_id=nullif(btrim(p_maintenance_expense_account_id),''),
    updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_order_id and not is_deleted;

  while v_guard<8 loop
    select workflow_stage into v_current_stage from public.erp_maintenance_orders
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    exit when v_current_stage=v_target_stage;
    exit when v_target_stage='paid' and v_current_stage='invoice_approved';
    exit when v_target_stage='completed' and v_current_stage='completed';
    perform public.erp_v67_advance_maintenance_internal(p_company_id,p_order_id);
    v_guard:=v_guard+1;
  end loop;

  if v_target_stage='paid' then
    for v_payment in select value from jsonb_array_elements(coalesce(v_snapshot->'payments','[]'::jsonb)) loop
      insert into public.erp_maintenance_payments(
        company_id,maintenance_order_id,amount,currency_code,exchange_rate,
        amount_in_order_currency,notes,created_at
      ) values(
        p_company_id,p_order_id,public.erp_try_numeric(v_payment->>'amount',0),
        coalesce(nullif(v_payment->>'currencyCode',''),upper(p_currency_code)),
        greatest(public.erp_try_numeric(v_payment->>'exchangeRate',p_exchange_rate),0.000001),
        public.erp_try_numeric(v_payment->>'amountInOrderCurrency',0),nullif(v_payment->>'notes',''),
        coalesce(public.erp_try_timestamptz(v_payment->>'createdAt',now()),now())
      );
      v_paid:=v_paid+public.erp_try_numeric(v_payment->>'amountInOrderCurrency',0);
    end loop;
    update public.erp_maintenance_orders
       set paid_amount=least(v_paid,sale_price),
           workflow_stage=case when v_paid+0.001>=sale_price then 'paid' else 'invoice_approved' end,
           status=case when v_paid+0.001>=sale_price then 'completed' else 'approved' end,
           updated_at=now(),updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  end if;

  select * into v_order from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  return jsonb_build_object('ok',true,'orderId',v_order.id,'workflowStage',v_order.workflow_stage,
    'status',v_order.status,'partsCount',jsonb_array_length(v_parts),'updatedAt',v_order.updated_at);
end $$;

revoke all on function public.erp_r39_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_r39_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;
revoke all on function public.erp_r39_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_r39_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
