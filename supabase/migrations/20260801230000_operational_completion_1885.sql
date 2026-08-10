begin;

-- 18.8.5 removes the floating workspace from the runtime and completes the
-- cloud operations that were still visible to users: self profile images,
-- immediate user administration refresh and legacy sold-vehicle maintenance.

create or replace function public.erp_update_current_user_profile(
  p_full_name text,
  p_phone text default '',
  p_avatar_base64 text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_local_user_id text;
  v_company_slug text;
  v_payload jsonb;
  v_name text := nullif(btrim(coalesce(p_full_name, '')), '');
  v_phone text := btrim(coalesce(p_phone, ''));
  v_avatar text := nullif(regexp_replace(coalesce(p_avatar_base64, ''), '\s+', '', 'g'), '');
  v_now timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if v_name is null then
    raise exception 'full_name_required';
  end if;
  if length(v_name) > 160 or length(v_phone) > 80 then
    raise exception 'invalid_profile_input';
  end if;
  if v_avatar is not null and length(v_avatar) > 900000 then
    raise exception 'avatar_too_large';
  end if;

  select m.local_user_id, c.slug
    into v_local_user_id, v_company_slug
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
   where m.user_id = auth.uid()
     and m.is_active
   order by m.updated_at desc
   limit 1;

  if nullif(v_local_user_id, '') is null or nullif(v_company_slug, '') is null then
    raise exception 'membership_not_found';
  end if;

  select r.payload
    into v_payload
    from public.erp_records r
   where r.company_id = v_company_slug
     and r.entity_type = 'users'
     and r.record_id = v_local_user_id
     and not r.is_deleted
   for update;

  if not found then
    raise exception 'erp_user_not_found';
  end if;

  v_payload := v_payload || jsonb_build_object(
    'fullName', v_name,
    'phone', v_phone,
    'avatarBase64', to_jsonb(v_avatar),
    'updatedAt', v_now::text
  );

  update public.erp_records
     set payload = v_payload,
         updated_at = v_now,
         deleted_at = null,
         is_deleted = false
   where company_id = v_company_slug
     and entity_type = 'users'
     and record_id = v_local_user_id;

  insert into public.profiles(id, full_name, is_active, updated_at)
  values(auth.uid(), v_name, true, v_now)
  on conflict(id) do update
    set full_name = excluded.full_name,
        is_active = true,
        updated_at = excluded.updated_at;

  return v_payload;
end;
$$;

revoke all on function public.erp_update_current_user_profile(text,text,text)
  from public, anon;
grant execute on function public.erp_update_current_user_profile(text,text,text)
  to authenticated;

-- Authoritative maintenance selector. The cars table is the base so sold cars
-- remain selectable even when an old sale row omitted customerId or used the
-- vehicleId/clientId aliases.
drop function if exists public.erp_list_cloud_maintenance_eligible_cars(uuid);
create function public.erp_list_cloud_maintenance_eligible_cars(p_company_id uuid)
returns table(
  "carId" text,
  "displayName" text,
  "customerId" text,
  "customerName" text,
  "saleSequence" integer,
  brand text,
  model text,
  year integer,
  chassis text,
  "plateNumber" text,
  "carNumber" text,
  color text
)
language sql
security definer
set search_path=public
as $$
  with latest_sale as (
    select distinct on (
      coalesce(nullif(s.data->>'carId',''), nullif(s.data->>'vehicleId',''))
    )
      coalesce(nullif(s.data->>'carId',''), nullif(s.data->>'vehicleId','')) as car_id,
      coalesce(
        nullif(s.data->>'customerId',''),
        nullif(s.data->>'clientId',''),
        nullif(s.data->>'buyerId','')
      ) as customer_id,
      public.erp_try_numeric(
        coalesce(s.data->>'saleSequence', s.data->>'sequence'),
        0
      )::integer as sale_sequence,
      coalesce(s.data->>'saleDate', s.data->>'date', s.created_at::text) as sale_date
    from public.erp_sales s
    where s.company_id = p_company_id
      and not s.is_deleted
      and coalesce(nullif(s.data->>'carId',''), nullif(s.data->>'vehicleId','')) is not null
      and lower(coalesce(s.data->>'status', s.data->>'workflowStatus', 'completed'))
          not in ('cancelled','canceled','deleted','void','reversed','ملغاة','محذوفة')
    order by
      coalesce(nullif(s.data->>'carId',''), nullif(s.data->>'vehicleId','')),
      public.erp_try_numeric(coalesce(s.data->>'saleSequence', s.data->>'sequence'),0) desc,
      coalesce(s.data->>'saleDate', s.data->>'date', s.created_at::text) desc
  )
  select
    c.id::text,
    nullif(concat_ws(' ', c.data->>'brand', c.data->>'model', c.data->>'year'), ' '),
    coalesce(
      ls.customer_id,
      nullif(c.data->>'customerId',''),
      nullif(c.data->>'buyerId',''),
      nullif(c.data->>'clientId','')
    ),
    coalesce(
      nullif(cu.data->>'name',''),
      nullif(concat_ws(' ', cu.data->>'firstName', cu.data->>'lastName'), ' '),
      nullif(c.data->>'customerName',''),
      nullif(c.data->>'buyerName',''),
      '—'
    ),
    coalesce(ls.sale_sequence, 0),
    nullif(c.data->>'brand',''),
    nullif(c.data->>'model',''),
    public.erp_try_numeric(c.data->>'year',0)::integer,
    nullif(c.data->>'chassis',''),
    coalesce(nullif(c.data->>'plateNumber',''), nullif(c.data->>'plate','')),
    coalesce(nullif(c.data->>'carNumber',''), nullif(c.data->>'vehicleNumber','')),
    nullif(c.data->>'color','')
  from public.erp_cars c
  left join latest_sale ls on ls.car_id = c.id::text
  left join public.erp_customers cu
    on cu.company_id = p_company_id
   and cu.id::text = coalesce(
     ls.customer_id,
     nullif(c.data->>'customerId',''),
     nullif(c.data->>'buyerId',''),
     nullif(c.data->>'clientId','')
   )
   and not cu.is_deleted
  where c.company_id = p_company_id
    and not c.is_deleted
    and public.erp_active_company_context(p_company_id) is not null
    and (
      ls.car_id is not null
      or lower(coalesce(
        c.data->>'statusValue',
        c.data->>'status',
        c.data->>'carStatus',
        ''
      )) in ('sold','مباعة','مباع')
    )
  order by 2, c.created_at desc;
$$;

revoke all on function public.erp_list_cloud_maintenance_eligible_cars(uuid)
  from public, anon;
grant execute on function public.erp_list_cloud_maintenance_eligible_cars(uuid)
  to authenticated;

-- Accept the same sold-car rules during creation. Customer information is
-- useful but no longer blocks legitimate legacy sold vehicles.
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
  where id::text=p_car_id and company_id=p_company_id and not is_deleted
  for update;
 if not found then raise exception 'السيارة غير موجودة'; end if;

 select true,
        coalesce(nullif(data->>'customerId',''),nullif(data->>'clientId',''),nullif(data->>'buyerId',''))
   into v_has_sale, v_customer
   from public.erp_sales
  where company_id=p_company_id
    and not is_deleted
    and coalesce(nullif(data->>'carId',''),nullif(data->>'vehicleId',''))=p_car_id
    and lower(coalesce(data->>'status',data->>'workflowStatus','completed'))
        not in ('cancelled','canceled','deleted','void','reversed','ملغاة','محذوفة')
  order by public.erp_try_numeric(coalesce(data->>'saleSequence',data->>'sequence'),0) desc,
           coalesce(data->>'saleDate',data->>'date',created_at::text) desc
  limit 1;

 v_customer := coalesce(
   nullif(v_customer,''),
   nullif(v_car.data->>'customerId',''),
   nullif(v_car.data->>'buyerId',''),
   nullif(v_car.data->>'clientId','')
 );
 v_is_sold := coalesce(v_has_sale,false) or lower(coalesce(
   v_car.data->>'statusValue',
   v_car.data->>'status',
   v_car.data->>'carStatus',
   ''
 )) in ('sold','مباعة','مباع');
 if not v_is_sold then
   raise exception 'يمكن إنشاء الصيانة للسيارات المباعة فقط';
 end if;

 if v_customer is not null then
   select coalesce(
     nullif(data->>'name',''),
     nullif(concat_ws(' ',data->>'firstName',data->>'lastName'),' '),
     v_customer
   ) into v_customer_name
   from public.erp_customers
   where company_id=p_company_id and id::text=v_customer and not is_deleted
   limit 1;
 end if;
 v_customer_name := coalesce(
   v_customer_name,
   nullif(v_car.data->>'customerName',''),
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
   p_car_id::uuid,
   concat_ws(' ',v_car.data->>'brand',v_car.data->>'model',v_car.data->>'year'),
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

create index if not exists idx_erp_sales_maintenance_vehicle_1885
  on public.erp_sales(
    company_id,
    (coalesce(nullif(data->>'carId',''),nullif(data->>'vehicleId',''))),
    created_at desc
  ) where not is_deleted;

create index if not exists idx_erp_cars_sold_status_1885
  on public.erp_cars(
    company_id,
    (lower(coalesce(data->>'statusValue',data->>'status',data->>'carStatus','')))
  ) where not is_deleted;

commit;
