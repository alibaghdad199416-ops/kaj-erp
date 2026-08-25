-- Quality Line ERP 18.8.8 stage 4 runtime correction.
begin;

alter table public.erp_maintenance_parts
  alter column warehouse_id drop not null;

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

drop function if exists public.erp_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz);
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

drop function if exists public.erp_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz);
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

create or replace function public.erp_stage4_normalize_order_links_for_delete(
  p_company_id uuid,p_order_id uuid,p_module text
) returns void language plpgsql security definer set search_path=public as $$
declare d record;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'نوع أمر غير صالح للحذف';
  end if;
  for d in
    select id from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=p_order_id and module=p_module
       and document_type='invoice' and not is_deleted and status<>'cancelled'
     order by created_at desc,id desc offset 1
  loop
    perform public.erp_reverse_cloud_workflow_invoice_payments(
      p_company_id,d.id,'تهيئة الحذف المترابط'
    );
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_workflow_invoice(
        p_company_id,d.id,'تهيئة الحذف المترابط'
      );
    else
      perform public.erp_cancel_cloud_purchase_workflow_invoice(
        p_company_id,d.id,'تهيئة الحذف المترابط'
      );
    end if;
  end loop;
  for d in
    select id from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=p_order_id and module=p_module
       and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
       and not is_deleted and status<>'cancelled'
     order by created_at desc,id desc offset 1
  loop
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_delivery(p_company_id,d.id);
    else
      perform public.erp_cancel_cloud_purchase_receipt(p_company_id,d.id);
    end if;
  end loop;
end;
$$;


create or replace function public.erp_delete_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb;v_number text;v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.delete']);
  select order_number into v_number from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;
  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_purchase_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر الشراء وعكس الاستلام والفاتورة والدفعات والقيود',true);
  perform public.erp_stage4_normalize_order_links_for_delete(p_company_id,p_order_id,'purchases');
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'purchases','حذف أمر الشراء وعكس ارتباطاته');
  v_snapshot:=jsonb_set(v_snapshot,'{effectiveAt}',to_jsonb((select effective_at from public.erp_purchase_orders_cloud where id=p_order_id)),true);
  if jsonb_typeof(v_snapshot->'logistics')='object' then
    v_snapshot:=jsonb_set(v_snapshot,'{logistics,allocations}',coalesce((
      select payload->'allocations' from public.erp_commercial_workflow_documents
      where company_id=p_company_id and id=(v_snapshot#>>'{logistics,id}')::uuid
    ),'[]'::jsonb),true);
  end if;
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted',
    'حذف مترابط مع عكس إشعار الاستلام والفاتورة والدفعات والقيود ووجبات FIFO');
  update public.erp_commercial_workflow_documents set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and parent_id=p_order_id and module='purchases' and not is_deleted;
  update public.erp_purchase_order_items_cloud set is_deleted=true
    where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_purchase_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','purchases','commercialSnapshot',v_snapshot
  ) where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb;v_number text;v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.delete']);
  select order_number into v_number from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;
  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_sales_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر البيع وعكس التجهيز والفاتورة والدفعات والقيود',true);
  perform public.erp_stage4_normalize_order_links_for_delete(p_company_id,p_order_id,'sales');
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','حذف أمر البيع وعكس ارتباطاته');
  v_snapshot:=jsonb_set(v_snapshot,'{effectiveAt}',to_jsonb((select effective_at from public.erp_sales_orders_cloud where id=p_order_id)),true);
  if jsonb_typeof(v_snapshot->'logistics')='object' then
    v_snapshot:=jsonb_set(v_snapshot,'{logistics,allocations}',coalesce((
      select payload->'allocations' from public.erp_commercial_workflow_documents
      where company_id=p_company_id and id=(v_snapshot#>>'{logistics,id}')::uuid
    ),'[]'::jsonb),true);
  end if;
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted',
    'حذف مترابط مع عكس إذن التجهيز والفاتورة والدفعات والقيود واستهلاك FIFO');
  update public.erp_commercial_workflow_documents set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted;
  update public.erp_sales_order_items_cloud set is_deleted=true
    where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_sales_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','sales','commercialSnapshot',v_snapshot
  ) where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_inventory_product_delete_impact(
  p_company_id uuid,p_product_id text
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'stockQuantity',coalesce((select sum(public.erp_try_numeric(data->>'quantity',0))
      from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id),0),
    'salesOrderLinks',(select count(*) from public.erp_sales_order_items_cloud i join public.erp_sales_orders_cloud o on o.id=i.order_id
      where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted),
    'purchaseOrderLinks',(select count(*) from public.erp_purchase_order_items_cloud i join public.erp_purchase_orders_cloud o on o.id=i.order_id
      where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted),
    'transferLinks',(select count(*) from public.erp_warehouse_transfer_items
      where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id),
    'activeFifoQuantity',coalesce((select sum(remaining_quantity) from public.erp_inventory_cost_layers
      where company_id=p_company_id and item_type='product' and item_id=p_product_id and status in ('active','consumed')),0),
    'activeFifoConsumptions',(select count(*) from public.erp_inventory_fifo_consumptions
      where company_id=p_company_id and item_type='product' and item_id=p_product_id and status='active')
  ) where public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_delete_inventory_product(
  p_company_id uuid,p_product_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_batch uuid:=gen_random_uuid();v_stock numeric;v_sales bigint;v_purchases bigint;v_transfers bigint;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['inventory.delete']);
  perform 1 from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted for update;
  if not found then raise exception 'المنتج غير موجود'; end if;
  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0) into v_stock
    from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  if v_stock<>0 then raise exception 'لا يمكن حذف المادة قبل تصفير رصيدها في جميع المخازن؛ الرصيد الحالي %',v_stock; end if;
  select count(*) into v_sales from public.erp_sales_order_items_cloud i join public.erp_sales_orders_cloud o on o.id=i.order_id
    where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted;
  select count(*) into v_purchases from public.erp_purchase_order_items_cloud i join public.erp_purchase_orders_cloud o on o.id=i.order_id
    where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted;
  select count(*) into v_transfers from public.erp_warehouse_transfer_items
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  if v_sales+v_purchases+v_transfers>0 then
    raise exception 'يجب حذف أو إلغاء الارتباطات أولاً: مبيعات=%، مشتريات=%، نقل مخزني=%',v_sales,v_purchases,v_transfers;
  end if;
  if exists(select 1 from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and item_type='product' and item_id=p_product_id and status='active') then
    raise exception 'لا يمكن حذف المادة قبل إلغاء مستندات البيع التي استهلكت وجباتها';
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_inventory',true);
  perform set_config('qualityline.deletion_root_id',p_product_id,true);
  perform set_config('qualityline.deletion_reason','حذف مادة مخزنية بعد التحقق من الأرصدة والارتباطات',true);

  delete from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and item_type='product' and item_id=p_product_id;
  delete from public.erp_inventory_cost_layers
    where company_id=p_company_id and item_type='product' and item_id=p_product_id;
  update public.erp_inventory_movements set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_product_images set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_warehouse_stock set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_inventory_product_sales set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_inventory set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=p_product_id and not is_deleted;
end;
$$;

-- Attach recycle capture to tables created by this migration.
do $$ declare t text;begin
  foreach t in array array['erp_inventory_cost_layers','erp_inventory_fifo_consumptions','erp_operational_periods'] loop
    execute format('drop trigger if exists erp_capture_hard_delete on public.%I',t);
    execute format('create trigger erp_capture_hard_delete before delete on public.%I for each row execute function public.erp_capture_deleted_record()',t);
    execute format('drop trigger if exists erp_capture_soft_delete on public.%I',t);
    if t='erp_operational_periods' then
      execute format('create trigger erp_capture_soft_delete after update on public.%I for each row execute function public.erp_capture_soft_deleted_record()',t);
    end if;
  end loop;
end $$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb;v_number text;v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.delete']);
  select order_number into v_number from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;
  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_sales_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر البيع وعكس التجهيز والفاتورة والدفعات والقيود',true);
  perform public.erp_stage4_normalize_order_links_for_delete(p_company_id,p_order_id,'sales');
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','حذف أمر البيع وعكس ارتباطاته');
  v_snapshot:=jsonb_set(v_snapshot,'{effectiveAt}',to_jsonb((select effective_at from public.erp_sales_orders_cloud where id=p_order_id)),true);
  if jsonb_typeof(v_snapshot->'logistics')='object' then
    v_snapshot:=jsonb_set(v_snapshot,'{logistics,allocations}',coalesce((
      select payload->'allocations' from public.erp_commercial_workflow_documents
      where company_id=p_company_id and id=(v_snapshot#>>'{logistics,id}')::uuid
    ),'[]'::jsonb),true);
  end if;
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted',
    'حذف مترابط مع عكس إذن التجهيز والفاتورة والدفعات والقيود واستهلاك FIFO');
  update public.erp_commercial_workflow_documents set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted;
  update public.erp_sales_order_items_cloud set is_deleted=true
    where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_sales_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','sales','commercialSnapshot',v_snapshot
  ) where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_inventory_product_delete_impact(
  p_company_id uuid,p_product_id text
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'stockQuantity',coalesce((select sum(public.erp_try_numeric(data->>'quantity',0))
      from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id),0),
    'salesOrderLinks',(select count(*) from public.erp_sales_order_items_cloud i join public.erp_sales_orders_cloud o on o.id=i.order_id
      where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted),
    'purchaseOrderLinks',(select count(*) from public.erp_purchase_order_items_cloud i join public.erp_purchase_orders_cloud o on o.id=i.order_id
      where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted),
    'transferLinks',(select count(*) from public.erp_warehouse_transfer_items
      where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id),
    'activeFifoQuantity',coalesce((select sum(remaining_quantity) from public.erp_inventory_cost_layers
      where company_id=p_company_id and item_type='product' and item_id=p_product_id and status in ('active','consumed')),0),
    'activeFifoConsumptions',(select count(*) from public.erp_inventory_fifo_consumptions
      where company_id=p_company_id and item_type='product' and item_id=p_product_id and status='active')
  ) where public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_delete_inventory_product(
  p_company_id uuid,p_product_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_batch uuid:=gen_random_uuid();v_stock numeric;v_sales bigint;v_purchases bigint;v_transfers bigint;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['inventory.delete']);
  perform 1 from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted for update;
  if not found then raise exception 'المنتج غير موجود'; end if;
  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0) into v_stock
    from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  if v_stock<>0 then raise exception 'لا يمكن حذف المادة قبل تصفير رصيدها في جميع المخازن؛ الرصيد الحالي %',v_stock; end if;
  select count(*) into v_sales from public.erp_sales_order_items_cloud i join public.erp_sales_orders_cloud o on o.id=i.order_id
    where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted;
  select count(*) into v_purchases from public.erp_purchase_order_items_cloud i join public.erp_purchase_orders_cloud o on o.id=i.order_id
    where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted;
  select count(*) into v_transfers from public.erp_warehouse_transfer_items
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  if v_sales+v_purchases+v_transfers>0 then
    raise exception 'يجب حذف أو إلغاء الارتباطات أولاً: مبيعات=%، مشتريات=%، نقل مخزني=%',v_sales,v_purchases,v_transfers;
  end if;
  if exists(select 1 from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and item_type='product' and item_id=p_product_id and status='active') then
    raise exception 'لا يمكن حذف المادة قبل إلغاء مستندات البيع التي استهلكت وجباتها';
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_inventory',true);
  perform set_config('qualityline.deletion_root_id',p_product_id,true);
  perform set_config('qualityline.deletion_reason','حذف مادة مخزنية بعد التحقق من الأرصدة والارتباطات',true);

  delete from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and item_type='product' and item_id=p_product_id;
  delete from public.erp_inventory_cost_layers
    where company_id=p_company_id and item_type='product' and item_id=p_product_id;
  update public.erp_inventory_movements set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_product_images set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_warehouse_stock set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_inventory_product_sales set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_inventory set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=p_product_id and not is_deleted;
end;
$$;

-- Attach recycle capture to tables created by this migration.
do $$ declare t text;begin
  foreach t in array array['erp_inventory_cost_layers','erp_inventory_fifo_consumptions','erp_operational_periods'] loop
    execute format('drop trigger if exists erp_capture_hard_delete on public.%I',t);
    execute format('create trigger erp_capture_hard_delete before delete on public.%I for each row execute function public.erp_capture_deleted_record()',t);
    execute format('drop trigger if exists erp_capture_soft_delete on public.%I',t);
    if t='erp_operational_periods' then
      execute format('create trigger erp_capture_soft_delete after update on public.%I for each row execute function public.erp_capture_soft_deleted_record()',t);
    end if;
  end loop;
end $$;

create or replace function public.erp_delete_cloud_manual_journal(
  p_company_id uuid,p_entry_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_ref text;v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  select lower(coalesce(nullif(data->>'referenceType',''),'manual')) into v_ref
    from public.erp_journal_entries
   where company_id=p_company_id and id=p_entry_id and not is_deleted for update;
  if not found then return; end if;
  if v_ref not in ('manual','manual_journal') then
    raise exception 'هذا القيد مولد من مستند آخر؛ احذف المستند المصدر لعكس القيد تلقائياً';
  end if;
  update public.erp_journal_entries set is_deleted=true,deleted_at=v_now,
    updated_at=v_now,updated_by=auth.uid()
   where company_id=p_company_id and id=p_entry_id and not is_deleted;
  update public.erp_journal_lines set is_deleted=true,deleted_at=v_now,
    updated_at=v_now,updated_by=auth.uid()
   where company_id=p_company_id and data->>'entryId'=p_entry_id and not is_deleted;
end;
$$;

create or replace function public.erp_delete_cloud_accounting_entry(
  p_company_id uuid,p_entry_id text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_entry public.erp_journal_entries%rowtype;
  v_ref text;
  v_reference_id text;
  v_order_id text;
  v_reference_uuid uuid;
  v_order_uuid uuid;
  v_doc record;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  select * into v_entry from public.erp_journal_entries
   where company_id=p_company_id and id=p_entry_id and not is_deleted for update;
  if not found then return; end if;

  v_ref:=lower(coalesce(nullif(v_entry.data->>'referenceType',''),nullif(v_entry.data->>'reference_type',''),'manual'));
  v_reference_id:=coalesce(
    nullif(v_entry.data->>'referenceId',''),
    nullif(v_entry.data->>'reference_id',''),
    nullif(v_entry.data->>'maintenanceOrderId','')
  );
  v_order_id:=coalesce(
    nullif(v_entry.data->>'orderId',''),
    nullif(v_entry.data->>'order_id','')
  );

  if v_ref in ('manual','manual_journal') then
    perform public.erp_delete_cloud_manual_journal(p_company_id,p_entry_id);
    return;
  end if;

  begin v_reference_uuid:=v_reference_id::uuid; exception when invalid_text_representation then v_reference_uuid:=null; end;
  begin v_order_uuid:=v_order_id::uuid; exception when invalid_text_representation then v_order_uuid:=null; end;

  -- Maintenance journals are reversed through the maintenance source so stock,
  -- payments, and every related journal remain consistent.
  if v_reference_uuid is not null
     and (v_ref like 'maintenance%' or exists(
       select 1 from public.erp_maintenance_orders
        where company_id=p_company_id and id=v_reference_uuid and not is_deleted
     )) then
    perform public.erp_delete_cloud_maintenance_order(
      p_company_id,v_reference_uuid,'حذف من القيد المحاسبي المرتبط'
    );
    return;
  end if;

  -- Workflow entries normally point to an invoice/receipt/delivery document.
  if v_reference_uuid is not null then
    select module,parent_id into v_doc
      from public.erp_commercial_workflow_documents
     where company_id=p_company_id and id=v_reference_uuid and not is_deleted
     limit 1;
    if found and v_doc.module='sales' then
      perform public.erp_delete_cloud_sales_order(p_company_id,v_doc.parent_id);
      return;
    elsif found and v_doc.module='purchases' then
      perform public.erp_delete_cloud_purchase_order(p_company_id,v_doc.parent_id);
      return;
    end if;
  end if;

  -- Some journal producers store the order id separately from the reference id.
  if v_order_uuid is not null and exists(
    select 1 from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=v_order_uuid and not is_deleted
  ) then
    perform public.erp_delete_cloud_sales_order(p_company_id,v_order_uuid);
    return;
  end if;
  if v_order_uuid is not null and exists(
    select 1 from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=v_order_uuid and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase_order(p_company_id,v_order_uuid);
    return;
  end if;
  if v_reference_uuid is not null and exists(
    select 1 from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=v_reference_uuid and not is_deleted
  ) then
    perform public.erp_delete_cloud_sales_order(p_company_id,v_reference_uuid);
    return;
  end if;
  if v_reference_uuid is not null and exists(
    select 1 from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=v_reference_uuid and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase_order(p_company_id,v_reference_uuid);
    return;
  end if;

  -- Legacy invoices use text identifiers and remain deletable through their
  -- own cascade-compatible functions.
  if v_reference_id is not null and exists(
    select 1 from public.erp_sales
     where company_id=p_company_id and id=v_reference_id and not is_deleted
  ) then
    perform public.erp_delete_cloud_sale(p_company_id,v_reference_id);
    return;
  end if;
  if v_reference_id is not null and exists(
    select 1 from public.erp_purchases
     where company_id=p_company_id and id=v_reference_id and not is_deleted
  ) then
    perform public.erp_delete_cloud_purchase(p_company_id,v_reference_id);
    return;
  end if;

  raise exception 'لا يمكن حذف القيد المولد منفرداً؛ احذف المستند المصدر أو امنح صلاحية حذف المستند المرتبط';
end;
$$;

create or replace function public.erp_delete_cloud_sale(
  p_company_id uuid,p_sale_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_sale public.erp_sales%rowtype; v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.delete']);
  select * into v_sale from public.erp_sales where company_id=p_company_id and id=p_sale_id and not is_deleted for update;
  if not found then return; end if;
  update public.erp_installments set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'saleId'=p_sale_id;
  update public.erp_sales set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=p_sale_id;
  if not exists(select 1 from public.erp_sales where company_id=p_company_id and not is_deleted and data->>'carId'=v_sale.data->>'carId') then
    update public.erp_cars set data=data||jsonb_build_object('status','متوفرة','updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and id=v_sale.data->>'carId' and not is_deleted;
  end if;
end $$;

create or replace function public.erp_delete_cloud_purchase(
  p_company_id uuid,p_purchase_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_item record; v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.delete']);
  perform 1 from public.erp_purchases where company_id=p_company_id and id=p_purchase_id and not is_deleted for update;
  if not found then return; end if;
  for v_item in select data->>'carId' car_id from public.erp_purchase_items where company_id=p_company_id and not is_deleted and data->>'purchaseId'=p_purchase_id loop
    if exists(select 1 from public.erp_sales where company_id=p_company_id and not is_deleted and data->>'carId'=v_item.car_id) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات تم بيعها لاحقاً';
    end if;
    if exists(
      select 1
      from public.erp_records r
      where r.company_id=p_company_id::text
        and r.entity_type='reservations'
        and r.deleted_at is null
        and r.payload->>'carId'=v_item.car_id
        and r.payload->>'status'='active'
    ) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات قيد البيع حالياً';
    end if;
  end loop;
  for v_item in select data->>'carId' car_id from public.erp_purchase_items where company_id=p_company_id and not is_deleted and data->>'purchaseId'=p_purchase_id loop
    update public.erp_cars set data=data||jsonb_build_object('status','معرفة','warehouseId',null,'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and id=v_item.car_id and not is_deleted;
  end loop;
  update public.erp_purchase_items set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'purchaseId'=p_purchase_id;
  update public.erp_purchases set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=p_purchase_id;
end $$;

revoke all on function public.erp_stage4_normalize_order_links_for_delete(uuid,uuid,text) from public,anon;
revoke all on function public.erp_delete_cloud_accounting_entry(uuid,text) from public,anon;
grant execute on function public.erp_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_accounting_entry(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_manual_journal(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sale(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_purchase(uuid,text) to authenticated,service_role;
commit;
