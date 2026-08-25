-- Quality Line ERP 18.8.6: strict database lint repair.
-- erp_cars keeps canonical identifiers as text for compatibility, while
-- erp_maintenance_orders.car_id is UUID. Cast the selected canonical row id
-- explicitly after resolving all legacy aliases.
begin;

create or replace function public.erp_create_cloud_maintenance_order(
 p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,p_labor_cost numeric,p_sale_price numeric,
 p_currency_code text,p_exchange_rate numeric,p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
 v_id uuid;
 v_car public.erp_cars%rowtype;
 v_totals jsonb;
 v_customer text;
 v_customer_name text;
 v_price numeric;
 v_has_sale boolean := false;
 v_is_sold boolean := false;
begin
 perform public.erp_active_company_context(p_company_id);
 if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then
   raise exception 'بيانات الصيانة غير صحيحة';
 end if;
 select * into v_car
   from public.erp_cars
  where company_id=p_company_id
    and not is_deleted
    and (
      id::text=p_car_id
      or coalesce(
        nullif(data->>'carId',''),
        nullif(data->>'car_id',''),
        nullif(data->>'vehicleId',''),
        nullif(data->>'vehicle_id','')
      )=p_car_id
    )
  for update;
 if not found then raise exception 'السيارة غير موجودة'; end if;

 select true,
        coalesce(
          nullif(data->>'customerId',''),
          nullif(data->>'customer_id',''),
          nullif(data->>'clientId',''),
          nullif(data->>'client_id',''),
          nullif(data->>'buyerId',''),
          nullif(data->>'buyer_id','')
        )
   into v_has_sale, v_customer
   from public.erp_sales
  where company_id=p_company_id
    and not is_deleted
    and coalesce(
      nullif(data->>'carId',''),
      nullif(data->>'car_id',''),
      nullif(data->>'vehicleId',''),
      nullif(data->>'vehicle_id','')
    ) in (p_car_id, v_car.id::text)
    and lower(coalesce(
      data->>'status',
      data->>'statusValue',
      data->>'status_value',
      data->>'workflowStatus',
      data->>'workflow_status',
      data->>'saleStatus',
      data->>'sale_status',
      'completed'
    )) not in (
      'cancelled','canceled','deleted','void','reversed',
      'ملغاة','ملغي','ملغى','محذوفة','محذوف'
    )
  order by public.erp_try_numeric(
             coalesce(data->>'saleSequence',data->>'sale_sequence',data->>'sequence'),0
           ) desc,
           coalesce(data->>'saleDate',data->>'sale_date',data->>'date',created_at::text) desc
  limit 1;

 v_customer := coalesce(
   nullif(v_customer,''),
   nullif(v_car.data->>'customerId',''),
   nullif(v_car.data->>'customer_id',''),
   nullif(v_car.data->>'clientId',''),
   nullif(v_car.data->>'client_id',''),
   nullif(v_car.data->>'buyerId',''),
   nullif(v_car.data->>'buyer_id','')
 );
 v_is_sold := coalesce(v_has_sale,false) or lower(coalesce(
   v_car.data->>'statusValue',
   v_car.data->>'status_value',
   v_car.data->>'status',
   v_car.data->>'carStatus',
   v_car.data->>'car_status',
   v_car.data->>'vehicleStatus',
   v_car.data->>'vehicle_status',
   ''
 )) in (
   'sold','sold_out','soldout','completed_sale','sale_completed',
   'مباعة','مباع','تم البيع','تمت المبايعة'
 );
 if not v_is_sold then
   raise exception 'يمكن إنشاء الصيانة للسيارات المباعة فقط';
 end if;

 if v_customer is not null then
   select coalesce(
     nullif(data->>'name',''),
     nullif(data->>'fullName',''),
     nullif(data->>'full_name',''),
     nullif(concat_ws(' ',data->>'firstName',data->>'lastName'),' '),
     nullif(concat_ws(' ',data->>'first_name',data->>'last_name'),' '),
     v_customer
   ) into v_customer_name
   from public.erp_customers
   where company_id=p_company_id and id::text=v_customer and not is_deleted
   limit 1;
 end if;
 v_customer_name := coalesce(
   v_customer_name,
   nullif(v_car.data->>'customerName',''),
   nullif(v_car.data->>'customer_name',''),
   nullif(v_car.data->>'clientName',''),
   nullif(v_car.data->>'buyerName',''),
   '—'
 );

 perform public.erp_phase2_account_guard(
   p_company_id,p_maintenance_expense_account_id,'expense',p_currency_code
 );
 v_price:=case when p_pricing_type='paid' then p_sale_price else 0 end;
 insert into public.erp_maintenance_orders(
   company_id,order_number,car_id,car_name,customer_id,customer_name,
   warehouse_id,is_sold_car,pricing_type,labor_cost,sale_price,
   maintenance_date,notes,currency_code,exchange_rate,
   maintenance_expense_account_id
 ) values(
   p_company_id,
   'MO-'||extract(epoch from clock_timestamp())::bigint,
   v_car.id::uuid,
   coalesce(
     nullif(v_car.data->>'displayName',''),
     nullif(v_car.data->>'display_name',''),
     nullif(v_car.data->>'name',''),
     nullif(concat_ws(' ',v_car.data->>'brand',v_car.data->>'model',v_car.data->>'year'),' '),
     nullif(v_car.data->>'carNumber',''),
     nullif(v_car.data->>'car_number',''),
     nullif(v_car.data->>'chassis',''),
     v_car.id::text
   ),
   case
     when v_customer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     then v_customer::uuid
     else null
   end,
   v_customer_name,
   coalesce(
     nullif(p_warehouse_id,''),
     nullif((
       select value->>'warehouse_id'
       from jsonb_array_elements(p_parts) value
       where value->>'warehouse_id' is not null
       limit 1
     ),'')
   )::uuid,
   true,
   case when p_pricing_type in('paid','free') then p_pricing_type else 'paid' end,
   p_labor_cost,v_price,now(),p_notes,upper(p_currency_code),p_exchange_rate,
   p_maintenance_expense_account_id
 ) returning id into v_id;

 v_totals:=public.erp_phase3_prepare_maintenance_lines(
   p_company_id,v_id,upper(p_currency_code),p_parts
 );
 update public.erp_maintenance_orders
    set parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),
        total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
        sale_price=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
        profit=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost)-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) else -(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) end,
        amount_usd=case when upper(p_currency_code)='USD' then case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end else 0 end,
        amount_iqd=case when upper(p_currency_code)='IQD' then case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end else 0 end
  where id=v_id;
 return v_id;
end $$;


revoke all on function public.erp_create_cloud_maintenance_order(
 uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text
) from public,anon;
grant execute on function public.erp_create_cloud_maintenance_order(
 uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text
) to authenticated;

commit;
