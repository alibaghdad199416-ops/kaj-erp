-- Quality Line ERP 18.8.8 stage 3:
-- robust maintenance creation for legacy text identifiers, detailed customer
-- service reporting, and professional codes for master/operational records.
begin;

create or replace function public.erp_stage3_stable_uuid(p_value text)
returns uuid language sql immutable strict as $$
  select case
    when p_value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then p_value::uuid
    else (
      substr(md5(p_value),1,8)||'-'||substr(md5(p_value),9,4)||'-4'||
      substr(md5(p_value),14,3)||'-8'||substr(md5(p_value),18,3)||'-'||
      substr(md5(p_value),21,12)
    )::uuid
  end;
$$;

alter table public.erp_maintenance_orders
  add column if not exists source_car_id text,
  add column if not exists source_warehouse_id text;

alter table public.erp_maintenance_parts
  add column if not exists source_product_id text,
  add column if not exists source_warehouse_id text,
  alter column warehouse_id drop not null;

update public.erp_maintenance_orders
set source_car_id=coalesce(source_car_id,car_id::text),
    source_warehouse_id=coalesce(source_warehouse_id,warehouse_id::text)
where source_car_id is null or (source_warehouse_id is null and warehouse_id is not null);

update public.erp_maintenance_parts
set source_product_id=coalesce(source_product_id,product_id::text),
    source_warehouse_id=coalesce(source_warehouse_id,warehouse_id::text)
where source_product_id is null or (source_warehouse_id is null and warehouse_id is not null);

create index if not exists idx_erp_maintenance_order_source_car
  on public.erp_maintenance_orders(company_id,source_car_id)
  where not is_deleted;
create index if not exists idx_erp_maintenance_part_source_item
  on public.erp_maintenance_parts(company_id,source_product_id,source_warehouse_id)
  where not is_deleted;

create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,p_order_id uuid,p_currency text,p_lines jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  x jsonb; v_product text; v_warehouse text; v_qty numeric; v_name text;
  v_cost numeric; v_price numeric; v_available numeric; v_type text;
  v_stock public.erp_warehouse_stock%rowtype;
  v_cost_total numeric:=0; v_price_total numeric:=0;
begin
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'أضف مادة أو خدمة صيانة واحدة على الأقل';
  end if;

  if exists(
    with requested as (
      select nullif(btrim(value->>'product_id'),'') product_id,
             nullif(btrim(value->>'warehouse_id'),'') warehouse_id,
             sum(public.erp_try_numeric(value->>'quantity',0)) quantity
      from jsonb_array_elements(p_lines)
      group by 1,2
    )
    select 1 from requested r
    left join public.erp_warehouse_stock s
      on s.company_id=p_company_id and not s.is_deleted
     and s.data->>'warehouseId'=r.warehouse_id
     and s.data->>'productId'=r.product_id
    where r.warehouse_id is not null
      and public.erp_try_numeric(s.data->>'quantity',0)<r.quantity
  ) then
    raise exception 'إجمالي الكمية المطلوبة في بنود الصيانة يتجاوز رصيد المخزن';
  end if;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;

  for x in select value from jsonb_array_elements(p_lines) loop
    v_product:=nullif(btrim(x->>'product_id'),'');
    v_warehouse:=nullif(btrim(x->>'warehouse_id'),'');
    v_qty:=public.erp_try_numeric(x->>'quantity',0);
    v_price:=public.erp_try_numeric(x->>'unit_price',0);
    if v_product is null or v_qty<=0 or v_price<0 then
      raise exception 'بيانات بند الصيانة غير صحيحة';
    end if;

    select coalesce(data->>'name',data->>'nameAr',data->>'name_ar'),
           lower(coalesce(data->>'itemType',data->>'item_type','stock')),
           public.erp_try_numeric(coalesce(data->>'unitCost',data->>'purchasePrice',data->>'averageUnitCost'),0)
      into v_name,v_type,v_cost
      from public.erp_inventory
     where company_id=p_company_id and id=v_product and not is_deleted;
    if not found then raise exception 'بند الصيانة غير موجود: %',v_product; end if;

    if v_type='service' then
      v_warehouse:=null;
      v_cost:=0;
    else
      if v_warehouse is null then raise exception 'يجب اختيار مخزن لكل مادة مخزنية'; end if;
      select * into v_stock
        from public.erp_warehouse_stock
       where company_id=p_company_id and not is_deleted
         and data->>'warehouseId'=v_warehouse
         and data->>'productId'=v_product
       for update;
      v_available:=case when found then public.erp_try_numeric(v_stock.data->>'quantity',0) else 0 end;
      if v_available<v_qty then
        raise exception 'الرصيد غير كافٍ للمادة %؛ المتاح % والمطلوب %',coalesce(v_name,v_product),v_available,v_qty;
      end if;
      if found and public.erp_try_numeric(v_stock.data->>'averageUnitCost',0)>0 then
        v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
      end if;
      perform public.erp_phase2_item_accounts(p_company_id,'product',v_product,upper(p_currency));
    end if;

    insert into public.erp_maintenance_parts(
      company_id,maintenance_order_id,product_id,source_product_id,product_name,
      warehouse_id,source_warehouse_id,quantity,unit_cost,total_cost,line_type,
      unit_price,line_total_price
    ) values(
      p_company_id,p_order_id,public.erp_stage3_stable_uuid(v_product),v_product,
      coalesce(v_name,v_product),
      case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
      v_warehouse,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,
      v_type,v_price,v_price*v_qty
    );
    v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty;
    v_price_total:=v_price_total+v_price*v_qty;
  end loop;
  return jsonb_build_object('costTotal',v_cost_total,'priceTotal',v_price_total);
end $$;

-- Replace the creation RPC while preserving backwards-compatible default args.
drop function if exists public.erp_create_cloud_maintenance_order(
  uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text
);
create function public.erp_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,
  p_exchange_rate numeric,p_notes text,p_parts jsonb,
  p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_id uuid; v_car public.erp_cars%rowtype; v_totals jsonb;
  v_customer text; v_customer_name text; v_price numeric;
  v_has_sale boolean:=false; v_is_sold boolean:=false; v_warehouse text;
begin
  perform public.erp_active_company_context(p_company_id);
  perform public.erp_validate_operational_date(p_company_id,'maintenance',coalesce(p_effective_at,now()));
  if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then
    raise exception 'بيانات الصيانة غير صحيحة';
  end if;

  select * into v_car from public.erp_cars
   where company_id=p_company_id and not is_deleted
     and (id=p_car_id or coalesce(nullif(data->>'carId',''),nullif(data->>'car_id',''),nullif(data->>'vehicleId',''),nullif(data->>'vehicle_id',''))=p_car_id)
   limit 1 for update;
  if not found then raise exception 'السيارة غير موجودة أو غير متاحة للصيانة'; end if;

  select true,coalesce(nullif(data->>'customerId',''),nullif(data->>'customer_id',''),nullif(data->>'clientId',''),nullif(data->>'buyerId',''))
    into v_has_sale,v_customer
    from public.erp_sales
   where company_id=p_company_id and not is_deleted
     and coalesce(nullif(data->>'carId',''),nullif(data->>'car_id',''),nullif(data->>'vehicleId',''),nullif(data->>'vehicle_id','')) in (p_car_id,v_car.id)
     and lower(coalesce(data->>'status',data->>'statusValue',data->>'workflowStatus','completed')) not in ('cancelled','canceled','deleted','void','reversed','ملغاة','ملغي','ملغى','محذوفة','محذوف')
   order by public.erp_try_numeric(coalesce(data->>'saleSequence',data->>'sale_sequence',data->>'sequence'),0) desc,
            coalesce(data->>'saleDate',data->>'sale_date',data->>'date',created_at::text) desc
   limit 1;

  v_customer:=coalesce(v_customer,nullif(v_car.data->>'customerId',''),nullif(v_car.data->>'customer_id',''),nullif(v_car.data->>'buyerId',''));
  v_is_sold:=coalesce(v_has_sale,false) or lower(coalesce(v_car.data->>'statusValue',v_car.data->>'status_value',v_car.data->>'status','')) in ('sold','sold_out','soldout','completed_sale','sale_completed','مباعة','مباع','تم البيع','تمت المبايعة');
  if not v_is_sold then raise exception 'يمكن إنشاء الصيانة للسيارات المباعة فقط'; end if;

  if v_customer is not null then
    select coalesce(nullif(data->>'name',''),nullif(data->>'fullName',''),nullif(data->>'full_name',''),nullif(concat_ws(' ',data->>'firstName',data->>'lastName'),' '),v_customer)
      into v_customer_name
      from public.erp_customers
     where company_id=p_company_id and id=v_customer and not is_deleted limit 1;
  end if;
  v_customer_name:=coalesce(v_customer_name,nullif(v_car.data->>'customerName',''),nullif(v_car.data->>'customer_name',''),'—');
  if nullif(btrim(p_maintenance_expense_account_id),'') is not null then
    perform public.erp_phase2_account_guard(
      p_company_id,p_maintenance_expense_account_id,'expense',upper(p_currency_code)
    );
  end if;

  v_warehouse:=coalesce(nullif(btrim(p_warehouse_id),''),nullif((select value->>'warehouse_id' from jsonb_array_elements(p_parts) value where nullif(value->>'warehouse_id','') is not null limit 1),''));
  v_price:=case when p_pricing_type='paid' then p_sale_price else 0 end;

  insert into public.erp_maintenance_orders(
    company_id,order_number,car_id,source_car_id,car_name,customer_id,customer_name,
    warehouse_id,source_warehouse_id,is_sold_car,pricing_type,labor_cost,sale_price,
    maintenance_date,notes,currency_code,exchange_rate,maintenance_expense_account_id
  ) values(
    p_company_id,null,public.erp_stage3_stable_uuid(v_car.id),v_car.id,
    coalesce(nullif(v_car.data->>'displayName',''),nullif(v_car.data->>'display_name',''),nullif(v_car.data->>'name',''),nullif(concat_ws(' ',v_car.data->>'brand',v_car.data->>'model',v_car.data->>'year'),' '),v_car.id),
    case when v_customer ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then v_customer::uuid else null end,
    v_customer_name,
    case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
    v_warehouse,true,case when p_pricing_type in('paid','free') then p_pricing_type else 'paid' end,
    p_labor_cost,v_price,coalesce(p_effective_at,now()),nullif(btrim(p_notes),''),upper(p_currency_code),p_exchange_rate,p_maintenance_expense_account_id
  ) returning id into v_id;

  v_totals:=public.erp_phase3_prepare_maintenance_lines(p_company_id,v_id,upper(p_currency_code),p_parts);
  update public.erp_maintenance_orders
     set parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),
         total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
         sale_price=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
         profit=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost)-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) else -(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) end,
         amount_usd=case when upper(p_currency_code)='USD' and pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
         amount_iqd=case when upper(p_currency_code)='IQD' and pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end
   where id=v_id;
  return v_id;
end $$;

revoke all on function public.erp_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated;

-- Draft edits use the same legacy-safe identifiers and operational date rules.
drop function if exists public.erp_update_cloud_maintenance_draft(
  uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text
);
create function public.erp_update_cloud_maintenance_draft(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,
  p_exchange_rate numeric,p_notes text,p_parts jsonb,
  p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype; v_totals jsonb; v_price numeric;
  v_warehouse text; v_effective_at timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o from public.erp_maintenance_orders
   where id=p_order_id and company_id=p_company_id and not is_deleted
   for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;
  if o.workflow_stage not in ('order_draft','order_approved') then
    raise exception 'لا يمكن تعديل الأمر بعد إنشاء التجهيز المخزني';
  end if;

  v_effective_at:=coalesce(p_effective_at,o.maintenance_date,now());
  perform public.erp_validate_operational_date(p_company_id,'maintenance',v_effective_at);
  if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then
    raise exception 'بيانات الصيانة غير صحيحة';
  end if;
  if nullif(btrim(p_maintenance_expense_account_id),'') is not null then
    perform public.erp_phase2_account_guard(
      p_company_id,p_maintenance_expense_account_id,'expense',upper(p_currency_code)
    );
  end if;

  v_totals:=public.erp_phase3_prepare_maintenance_lines(
    p_company_id,p_order_id,upper(p_currency_code),p_parts
  );
  v_price:=case when p_pricing_type='paid' then
    greatest(p_sale_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost)
    else 0 end;
  v_warehouse:=coalesce(
    nullif(btrim(p_warehouse_id),''),
    nullif((select value->>'warehouse_id' from jsonb_array_elements(p_parts) value
      where nullif(value->>'warehouse_id','') is not null limit 1),''),
    o.source_warehouse_id,o.warehouse_id::text
  );

  update public.erp_maintenance_orders set
    warehouse_id=case when v_warehouse is null then null else public.erp_stage3_stable_uuid(v_warehouse) end,
    source_warehouse_id=v_warehouse,
    pricing_type=case when p_pricing_type in('paid','free') then p_pricing_type else 'paid' end,
    labor_cost=p_labor_cost,
    parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),
    total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
    sale_price=v_price,
    profit=v_price-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost),
    currency_code=upper(p_currency_code),exchange_rate=p_exchange_rate,
    amount_usd=case when upper(p_currency_code)='USD' then v_price else 0 end,
    amount_iqd=case when upper(p_currency_code)='IQD' then v_price else 0 end,
    maintenance_date=v_effective_at,notes=nullif(btrim(p_notes),''),
    maintenance_expense_account_id=p_maintenance_expense_account_id,
    updated_at=now()
  where id=p_order_id;
end $$;

revoke all on function public.erp_update_cloud_maintenance_draft(
  uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
) from public,anon;
grant execute on function public.erp_update_cloud_maintenance_draft(
  uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz
) to authenticated,service_role;

create or replace function public.erp_phase3_refresh_maintenance_products(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare p record;
begin
  for p in select distinct coalesce(source_product_id,product_id::text) product_id
    from public.erp_maintenance_parts
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service'
  loop
    perform public.erp_inventory_refresh_product(p_company_id,p.product_id);
  end loop;
end $$;

create or replace function public.erp_phase3_post_maintenance_issue(p_company_id uuid,p_order_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; ac jsonb; lines jsonb:='[]'; amount numeric; eid text; product_id text;
begin
  select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;
  perform public.erp_phase2_account_guard(p_company_id,o.maintenance_expense_account_id,'expense',o.currency_code);
  for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service' loop
    product_id:=coalesce(p.source_product_id,p.product_id::text);
    amount:=p.quantity*p.unit_cost;
    ac:=public.erp_phase2_item_accounts(p_company_id,'product',product_id,o.currency_code);
    if amount>0 then lines:=lines||jsonb_build_array(
      jsonb_build_object('accountId',o.maintenance_expense_account_id,'debit',amount,'credit',0,'description','كلفة صيانة - '||p.product_name,'itemId',product_id),
      jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج مخزون للصيانة - '||p.product_name,'itemId',product_id)); end if;
  end loop;
  if jsonb_array_length(lines)=0 then return null; end if;
  eid:=public.erp_phase2_insert_journal(p_company_id,'maintenance_stock_issue',p_order_id::text,
    public.erp_next_document_number(p_company_id,'maintenance_journal','MJE',o.maintenance_date),
    'قيد مواد أمر الصيانة '||o.order_number,o.currency_code,lines);
  return eid;
end $$;

create or replace function public.erp_advance_cloud_maintenance_workflow(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype; v_now timestamptz:=now(); product_id text; warehouse_id text;
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o from public.erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;
  if o.workflow_stage='order_draft' then
    update public.erp_maintenance_orders set workflow_stage='order_approved',status='approved',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='order_approved' then
    update public.erp_maintenance_orders set workflow_stage='stock_issue_draft',stock_issue_number='PENDING',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='stock_issue_draft' then
    for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted and line_type<>'service' loop
      product_id:=coalesce(p.source_product_id,p.product_id::text);
      warehouse_id:=coalesce(p.source_warehouse_id,p.warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text);
      select * into s from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=warehouse_id and data->>'productId'=product_id for update;
      if not found or public.erp_try_numeric(s.data->>'quantity',0)<p.quantity then raise exception 'الرصيد غير كافٍ للمادة %',p.product_name; end if;
      update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',public.erp_try_numeric(data->>'quantity',0)-p.quantity,'updatedAt',v_now),updated_at=v_now where id=s.id;
      perform public.erp_inventory_insert_movement(p_company_id,product_id,warehouse_id,'maintenance_out',-p.quantity,p.unit_cost,'maintenance_order',o.id::text,'صرف صيانة '||o.order_number);
    end loop;
    perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
    perform public.erp_phase3_post_maintenance_issue(p_company_id,o.id);
    update public.erp_maintenance_orders set workflow_stage='stock_issue_approved',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='stock_issue_approved' then
    update public.erp_maintenance_orders set workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,
      status=case when pricing_type='paid' then status else 'completed' end,
      invoice_number=case when pricing_type='paid' then 'PENDING' else invoice_number end,updated_at=v_now where id=o.id;
  elsif o.workflow_stage='invoice_draft' then
    update public.erp_maintenance_orders set workflow_stage='invoice_approved',updated_at=v_now where id=o.id;
  else raise exception 'لا توجد مرحلة تالية متاحة'; end if;
end $$;

create or replace function public.erp_cancel_cloud_maintenance_order(p_company_id uuid,p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype; product_id text; warehouse_id text;
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o from public.erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;
  if o.workflow_stage='cancelled' then return; end if;
  if o.paid_amount>0 then raise exception 'يجب عكس دفعات الصيانة قبل إلغاء الأمر'; end if;
  if o.workflow_stage in ('stock_issue_approved','invoice_draft','invoice_approved','paid','completed') then
    for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted and line_type<>'service' loop
      product_id:=coalesce(p.source_product_id,p.product_id::text);
      warehouse_id:=coalesce(p.source_warehouse_id,p.warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text);
      select * into s from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=warehouse_id and data->>'productId'=product_id for update;
      if found then
        update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',public.erp_try_numeric(data->>'quantity',0)+p.quantity,'updatedAt',now()),updated_at=now() where id=s.id;
      else
        insert into public.erp_warehouse_stock(company_id,id,data,created_by,updated_by) values
        (p_company_id,gen_random_uuid()::text,jsonb_build_object('id',gen_random_uuid()::text,'warehouseId',warehouse_id,'productId',product_id,'quantity',p.quantity,'averageUnitCost',p.unit_cost,'createdAt',now(),'updatedAt',now()),auth.uid(),auth.uid());
      end if;
      perform public.erp_inventory_insert_movement(p_company_id,product_id,warehouse_id,'maintenance_return',p.quantity,p.unit_cost,'maintenance_cancel',o.id::text,'إلغاء صيانة '||o.order_number);
    end loop;
    perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
  end if;
  perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',o.id::text);
  update public.erp_maintenance_orders set workflow_stage='cancelled',status='cancelled',cancelled_at=now(),cancel_reason=nullif(btrim(p_reason),''),updated_at=now() where id=o.id;
end $$;

drop function if exists public.erp_get_cloud_maintenance_order_lines(uuid,uuid);
create function public.erp_get_cloud_maintenance_order_lines(p_company_id uuid,p_order_id uuid)
returns table(id uuid,"productId" text,"productName" text,"warehouseId" text,"warehouseName" text,quantity integer,"unitCost" numeric,"unitPrice" numeric,"lineType" text)
language sql security definer set search_path=public as $$
  select p.id,coalesce(p.source_product_id,p.product_id::text),p.product_name,
         coalesce(p.source_warehouse_id,p.warehouse_id::text),w.data->>'name',
         p.quantity,p.unit_cost,p.unit_price,p.line_type
    from public.erp_maintenance_parts p
    left join public.erp_warehouses w on w.company_id=p.company_id and w.id=coalesce(p.source_warehouse_id,p.warehouse_id::text) and not w.is_deleted
   where p.company_id=p_company_id and p.maintenance_order_id=p_order_id and not p.is_deleted
     and public.erp_active_company_context(p_company_id) is not null
   order by p.created_at,p.id;
$$;

drop function if exists public.erp_list_cloud_maintenance_orders(uuid);
create function public.erp_list_cloud_maintenance_orders(p_company_id uuid)
returns table(id uuid,"orderNumber" text,"carId" text,"carName" text,"customerId" uuid,"customerName" text,"warehouseId" text,"isSoldCar" integer,"pricingType" text,status text,"laborCost" numeric,"partsCost" numeric,"totalCost" numeric,"salePrice" numeric,profit numeric,"carCostAdded" numeric,"maintenanceDate" timestamptz,notes text,"currencyCode" text,"exchangeRate" numeric,"workflowStage" text,"paidAmount" numeric,"invoiceNumber" text,"stockIssueNumber" text,"cancelReason" text,"maintenanceExpenseAccountId" text)
language sql security definer set search_path=public as $$
  select o.id,o.order_number,coalesce(o.source_car_id,o.car_id::text),o.car_name,o.customer_id,o.customer_name,
         coalesce(o.source_warehouse_id,o.warehouse_id::text),case when o.is_sold_car then 1 else 0 end,
         o.pricing_type,o.status,o.labor_cost,o.parts_cost,o.total_cost,o.sale_price,o.profit,o.car_cost_added,
         o.maintenance_date,o.notes,o.currency_code,o.exchange_rate,o.workflow_stage,o.paid_amount,o.invoice_number,
         o.stock_issue_number,o.cancel_reason,o.maintenance_expense_account_id
    from public.erp_maintenance_orders o
   where o.company_id=p_company_id and not o.is_deleted and public.erp_active_company_context(p_company_id) is not null
   order by o.maintenance_date desc,o.order_number desc;
$$;

grant execute on function public.erp_get_cloud_maintenance_order_lines(uuid,uuid) to authenticated;
grant execute on function public.erp_list_cloud_maintenance_orders(uuid) to authenticated;
grant execute on function public.erp_phase3_refresh_maintenance_products(uuid,uuid) to authenticated;
grant execute on function public.erp_phase3_post_maintenance_issue(uuid,uuid) to authenticated;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) to authenticated;
grant execute on function public.erp_cancel_cloud_maintenance_order(uuid,uuid,text) to authenticated;

-- Dedicated customizable customer-service/opportunity report sections.
create or replace function public.erp_cloud_customer_service_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns setof jsonb language plpgsql security definer set search_path=public as $$
declare v_slug text;
begin
  perform public.erp_active_company_context(p_company_id);
  select coalesce(nullif(c.slug,''),p_company_id::text)
    into v_slug
    from public.companies c
   where c.id=p_company_id;
  v_slug:=coalesce(v_slug,p_company_id::text);

  if p_module in ('customer_service','opportunities') then
    return query
    with opportunities as (
      select r.record_id,r.payload,r.updated_at,r.created_by
        from public.erp_records r
       where r.company_id=v_slug and r.entity_type='opportunities' and r.deleted_at is null
         and (p_start_date is null or coalesce(public.erp_try_timestamptz(r.payload->>'createdAt',r.updated_at),r.updated_at)::date>=p_start_date)
         and (p_end_date is null or coalesce(public.erp_try_timestamptz(r.payload->>'createdAt',r.updated_at),r.updated_at)::date<=p_end_date)
    ), details as (
      select jsonb_build_array(
        coalesce(payload->>'opportunityNumber',record_id),
        coalesce(payload->>'title',''),
        coalesce(payload->>'customerName',''),
        coalesce(payload->>'customerPhone',''),
        coalesce(payload->>'source',''),
        coalesce(payload->>'status','pending'),
        coalesce(payload->>'assignedUserName',''),
        coalesce(payload->>'createdByUserName',''),
        coalesce(payload->>'expectedValue','0'),
        coalesce(payload->>'carName',''),
        coalesce(payload->>'invoiceNumber',payload->>'salesOrderNumber',''),
        coalesce(payload->>'followUpDate',''),
        coalesce(payload->>'closedAt',''),
        coalesce(payload->>'createdAt',updated_at::text),
        coalesce(payload->>'notes','')
      ) row_data from opportunities
    ), status_summary as (
      select lower(coalesce(payload->>'status','pending')) status,
             count(*) count_value,
             sum(public.erp_try_numeric(payload->>'expectedValue',0)) value_total
        from opportunities group by lower(coalesce(payload->>'status','pending'))
    ), owner_summary as (
      select coalesce(nullif(payload->>'assignedUserName',''),'غير محدد') owner_name,
             count(*) count_value,
             sum(public.erp_try_numeric(payload->>'expectedValue',0)) value_total
        from opportunities group by coalesce(nullif(payload->>'assignedUserName',''),'غير محدد')
    )
    select jsonb_build_object(
      'key','opportunities_details','title','Opportunities / الفرص التجارية',
      'columns',jsonb_build_array('opportunityNumber','title','customer','phone','source','status','assignedUser','createdBy','expectedValue','vehicle','salesOrderNumber','followUpDate','closedAt','createdAt','notes'),
      'rows',coalesce((select jsonb_agg(row_data) from details),'[]'::jsonb)
    )
    union all
    select jsonb_build_object(
      'key','opportunities_status','title','Opportunity Status / حالات الفرص',
      'columns',jsonb_build_array('status','count','expectedValue'),
      'rows',coalesce((select jsonb_agg(jsonb_build_array(status,count_value,value_total)) from status_summary),'[]'::jsonb)
    )
    union all
    select jsonb_build_object(
      'key','customer_service_owners','title','Customer Service Owners / مسؤولو خدمة العملاء',
      'columns',jsonb_build_array('assignedUser','count','expectedValue'),
      'rows',coalesce((select jsonb_agg(jsonb_build_array(owner_name,count_value,value_total)) from owner_summary),'[]'::jsonb)
    );
    return;
  end if;
  raise exception 'وحدة تقرير خدمة العملاء غير مدعومة';
end $$;

revoke all on function public.erp_cloud_customer_service_report(uuid,text,date,date) from public,anon;
grant execute on function public.erp_cloud_customer_service_report(uuid,text,date,date) to authenticated;

-- Professional numbering for products, vehicles, transfers, and journal entries.
create or replace function public.erp_stage3_assign_record_number()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_effective timestamptz:=coalesce(public.erp_try_timestamptz(new.data->>'createdAt',new.created_at),now()); v_value text;
begin
  if tg_table_name='erp_inventory' then
    v_value:=coalesce(nullif(new.data->>'code',''),nullif(new.data->>'productNumber',''));
    if v_value is null or v_value !~ '^PRD-[0-9]{4}-[0-9]{6}$' then
      v_value:=public.erp_next_document_number(new.company_id,'product','PRD',v_effective);
      new.data:=new.data||jsonb_build_object('code',v_value,'productNumber',v_value,'product_number',v_value);
    end if;
  elsif tg_table_name='erp_cars' then
    v_value:=coalesce(nullif(new.data->>'carNumber',''),nullif(new.data->>'car_number',''));
    if v_value is null or v_value !~ '^CAR-[0-9]{4}-[0-9]{6}$' then
      v_value:=public.erp_next_document_number(new.company_id,'vehicle','CAR',v_effective);
      new.data:=new.data||jsonb_build_object('carNumber',v_value,'car_number',v_value);
    end if;
  elsif tg_table_name in ('erp_warehouse_transfers','erp_car_warehouse_transfers') then
    v_value:=coalesce(nullif(new.data->>'transferNumber',''),nullif(new.data->>'transfer_number',''));
    if v_value is null or v_value !~ '^WTR-[0-9]{4}-[0-9]{6}$' then
      v_value:=public.erp_next_document_number(new.company_id,'warehouse_transfer','WTR',v_effective);
      new.data:=new.data||jsonb_build_object('transferNumber',v_value,'transfer_number',v_value);
    end if;
  elsif tg_table_name='erp_journal_entries' then
    v_value:=coalesce(nullif(new.data->>'entryNumber',''),nullif(new.data->>'entry_number',''));
    if v_value is null or v_value !~ '^JRN-[0-9]{4}-[0-9]{6}$' then
      v_value:=public.erp_next_document_number(new.company_id,'journal_entry','JRN',coalesce(public.erp_try_timestamptz(new.data->>'entryDate',new.created_at),v_effective));
      new.data:=new.data||jsonb_build_object('entryNumber',v_value,'entry_number',v_value);
    end if;
  end if;
  return new;
end $$;


-- PL/pgSQL does not support dynamic CREATE TRIGGER inside the block above;
-- keep explicit idempotent trigger declarations.
drop trigger if exists erp_stage3_inventory_number on public.erp_inventory;
create trigger erp_stage3_inventory_number before insert or update of data on public.erp_inventory
for each row execute function public.erp_stage3_assign_record_number();
drop trigger if exists erp_stage3_car_number on public.erp_cars;
create trigger erp_stage3_car_number before insert or update of data on public.erp_cars
for each row execute function public.erp_stage3_assign_record_number();
drop trigger if exists erp_stage3_warehouse_transfer_number on public.erp_warehouse_transfers;
create trigger erp_stage3_warehouse_transfer_number before insert or update of data on public.erp_warehouse_transfers
for each row execute function public.erp_stage3_assign_record_number();
drop trigger if exists erp_stage3_car_transfer_number on public.erp_car_warehouse_transfers;
create trigger erp_stage3_car_transfer_number before insert or update of data on public.erp_car_warehouse_transfers
for each row execute function public.erp_stage3_assign_record_number();
drop trigger if exists erp_stage3_journal_number on public.erp_journal_entries;
create trigger erp_stage3_journal_number before insert or update of data on public.erp_journal_entries
for each row execute function public.erp_stage3_assign_record_number();

-- Payroll runs retain professional numbering where the legacy payroll table
-- is still installed, without reactivating the retired HR user interface.
create or replace function public.erp_stage3_assign_payroll_number()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.payroll_number is null
     or new.payroll_number !~ '^PAY-[0-9]{4}-[0-9]{6}$' then
    new.payroll_number:=public.erp_next_document_number(
      new.company_id,'payroll','PAY',coalesce(new.created_at,now())
    );
  end if;
  return new;
end $$;

do $$
begin
  if to_regclass('public.erp_hr_payroll_runs') is not null then
    execute 'drop trigger if exists erp_stage3_payroll_number on public.erp_hr_payroll_runs';
    execute 'create trigger erp_stage3_payroll_number before insert or update of payroll_number on public.erp_hr_payroll_runs for each row execute function public.erp_stage3_assign_payroll_number()';
  end if;
end $$;

revoke all on function public.erp_stage3_assign_payroll_number() from public,anon,authenticated;

revoke all on function public.erp_stage3_assign_record_number() from public,anon,authenticated;
revoke all on function public.erp_stage3_stable_uuid(text) from public,anon;
grant execute on function public.erp_stage3_stable_uuid(text) to authenticated;

commit;
