-- Phase 3: complete maintenance lifecycle.
-- Sold vehicles only, customer inherited from the latest sale, multi-warehouse
-- stock/service lines, configured maintenance expense, printable document data,
-- reversible soft deletion and accounting-aware workflow.

alter table public.erp_maintenance_orders alter column warehouse_id drop not null;

alter table public.erp_maintenance_orders
  add column if not exists maintenance_expense_account_id text,
  add column if not exists deleted_reason text,
  add column if not exists deleted_by uuid;

alter table public.erp_maintenance_parts
  add column if not exists line_type text not null default 'stock',
  add column if not exists unit_price numeric(18,2) not null default 0,
  add column if not exists line_total_price numeric(18,2) not null default 0;

create index if not exists idx_maintenance_parts_order_active
  on public.erp_maintenance_parts(company_id,maintenance_order_id)
  where not is_deleted;

create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,p_order_id uuid,p_currency text,p_lines jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare x jsonb; v_product text; v_warehouse text; v_qty numeric; v_name text;
 v_cost numeric; v_price numeric; v_available numeric; v_type text; v_stock public.erp_warehouse_stock%rowtype;
 v_cost_total numeric:=0; v_price_total numeric:=0;
begin
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'أضف بند صيانة واحداً على الأقل'; end if;
 update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 for x in select value from jsonb_array_elements(p_lines) loop
   v_product:=nullif(x->>'product_id',''); v_warehouse:=nullif(x->>'warehouse_id','');
   v_qty:=public.erp_try_numeric(x->>'quantity',0); v_price:=public.erp_try_numeric(x->>'unit_price',0);
   if v_product is null or v_qty<=0 or v_price<0 then raise exception 'بيانات بند الصيانة غير صحيحة'; end if;
   select coalesce(data->>'name',data->>'nameAr'),lower(coalesce(data->>'itemType',data->>'item_type','stock')),
          public.erp_try_numeric(data->>'unitCost',data->>'purchasePrice')
     into v_name,v_type,v_cost from public.erp_inventory
    where company_id=p_company_id and id=v_product and not is_deleted;
   if not found then raise exception 'بند الصيانة غير موجود'; end if;
   if v_type='service' then
     v_warehouse:=null; v_cost:=0;
   else
     if v_warehouse is null then raise exception 'يجب اختيار مخزن لكل مادة مخزنية'; end if;
     select * into v_stock from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted
       and data->>'warehouseId'=v_warehouse and data->>'productId'=v_product for update;
     v_available:=case when found then public.erp_try_numeric(v_stock.data->>'quantity',0) else 0 end;
     if v_available<v_qty then raise exception 'الرصيد غير كافٍ للمادة %',coalesce(v_name,v_product); end if;
     if found and public.erp_try_numeric(v_stock.data->>'averageUnitCost',0)>0 then
       v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
     end if;
     perform public.erp_phase2_item_accounts(p_company_id,'product',v_product,p_currency);
   end if;
   insert into public.erp_maintenance_parts(company_id,maintenance_order_id,product_id,product_name,warehouse_id,quantity,unit_cost,total_cost,line_type,unit_price,line_total_price)
   values(p_company_id,p_order_id,v_product::uuid,coalesce(v_name,v_product),v_warehouse::uuid,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,v_type,v_price,v_price*v_qty);
   v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty; v_price_total:=v_price_total+v_price*v_qty;
 end loop;
 return jsonb_build_object('costTotal',v_cost_total,'priceTotal',v_price_total);
end $$;

create or replace function public.erp_create_cloud_maintenance_order(
 p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,p_labor_cost numeric,p_sale_price numeric,
 p_currency_code text,p_exchange_rate numeric,p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_car public.erp_cars%rowtype; v_totals jsonb; v_customer text; v_customer_name text; v_price numeric;
begin
 perform public.erp_active_company_context(p_company_id);
 if p_exchange_rate<=0 or p_labor_cost<0 or p_sale_price<0 then raise exception 'بيانات الصيانة غير صحيحة'; end if;
 select * into v_car from public.erp_cars where id=p_car_id and company_id=p_company_id and not is_deleted for update;
 if not found then raise exception 'السيارة غير موجودة'; end if;
 select data->>'customerId' into v_customer from public.erp_sales where company_id=p_company_id and not is_deleted
  and data->>'carId'=p_car_id order by public.erp_try_numeric(data->>'saleSequence',0) desc,data->>'saleDate' desc limit 1;
 if nullif(v_customer,'') is null then raise exception 'يمكن إنشاء الصيانة للسيارات المباعة فقط'; end if;
 select coalesce(data->>'name',concat_ws(' ',data->>'firstName',data->>'lastName')) into v_customer_name
  from public.erp_customers where company_id=p_company_id and id=v_customer and not is_deleted;
 perform public.erp_phase2_account_guard(p_company_id,p_maintenance_expense_account_id,'expense',p_currency_code);
 v_price:=case when p_pricing_type='paid' then p_sale_price else 0 end;
 insert into public.erp_maintenance_orders(company_id,order_number,car_id,car_name,customer_id,customer_name,warehouse_id,is_sold_car,
 pricing_type,labor_cost,sale_price,maintenance_date,notes,currency_code,exchange_rate,maintenance_expense_account_id)
 values(p_company_id,'MO-'||extract(epoch from clock_timestamp())::bigint,p_car_id::uuid,
 concat_ws(' ',v_car.data->>'brand',v_car.data->>'model',v_car.data->>'year'),v_customer::uuid,v_customer_name,
 coalesce(nullif(p_warehouse_id,''),nullif((select value->>'warehouse_id' from jsonb_array_elements(p_parts) value where value->>'warehouse_id' is not null limit 1),''))::uuid,
 true,case when p_pricing_type in('paid','free') then p_pricing_type else 'paid' end,p_labor_cost,v_price,now(),p_notes,upper(p_currency_code),p_exchange_rate,p_maintenance_expense_account_id)
 returning id into v_id;
 v_totals:=public.erp_phase3_prepare_maintenance_lines(p_company_id,v_id,upper(p_currency_code),p_parts);
 update public.erp_maintenance_orders set parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),
 total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
 sale_price=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end,
 profit=case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost)-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) else -(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost) end,
 amount_usd=case when upper(p_currency_code)='USD' then case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end else 0 end,
 amount_iqd=case when upper(p_currency_code)='IQD' then case when pricing_type='paid' then greatest(v_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end else 0 end where id=v_id;
 return v_id;
end $$;

create or replace function public.erp_update_cloud_maintenance_draft(
 p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_pricing_type text,p_labor_cost numeric,p_sale_price numeric,
 p_currency_code text,p_exchange_rate numeric,p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null
) returns void language plpgsql security definer set search_path=public as $$
declare o record; v_totals jsonb; v_price numeric;
begin
 perform public.erp_active_company_context(p_company_id);
 select * into o from public.erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 if o.workflow_stage not in ('order_draft','order_approved') then raise exception 'لا يمكن تعديل الأمر بعد إنشاء التجهيز المخزني'; end if;
 perform public.erp_phase2_account_guard(p_company_id,p_maintenance_expense_account_id,'expense',p_currency_code);
 v_totals:=public.erp_phase3_prepare_maintenance_lines(p_company_id,p_order_id,upper(p_currency_code),p_parts);
 v_price:=case when p_pricing_type='paid' then greatest(p_sale_price,public.erp_try_numeric(v_totals->>'priceTotal',0)+p_labor_cost) else 0 end;
 update public.erp_maintenance_orders set warehouse_id=coalesce(nullif(p_warehouse_id,'')::uuid,warehouse_id),pricing_type=p_pricing_type,
 labor_cost=p_labor_cost,parts_cost=public.erp_try_numeric(v_totals->>'costTotal',0),total_cost=public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost,
 sale_price=v_price,profit=v_price-(public.erp_try_numeric(v_totals->>'costTotal',0)+p_labor_cost),currency_code=upper(p_currency_code),exchange_rate=p_exchange_rate,
 amount_usd=case when upper(p_currency_code)='USD' then v_price else 0 end,amount_iqd=case when upper(p_currency_code)='IQD' then v_price else 0 end,
 notes=p_notes,maintenance_expense_account_id=p_maintenance_expense_account_id,updated_at=now() where id=p_order_id;
end $$;

create or replace function public.erp_phase3_post_maintenance_issue(p_company_id uuid,p_order_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; ac jsonb; lines jsonb:='[]'; amount numeric; eid text;
begin
 select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 perform public.erp_phase2_account_guard(p_company_id,o.maintenance_expense_account_id,'expense',o.currency_code);
 for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service' loop
   amount:=p.quantity*p.unit_cost; ac:=public.erp_phase2_item_accounts(p_company_id,'product',p.product_id::text,o.currency_code);
   if amount>0 then lines:=lines||jsonb_build_array(
    jsonb_build_object('accountId',o.maintenance_expense_account_id,'debit',amount,'credit',0,'description','كلفة صيانة - '||p.product_name,'itemId',p.product_id),
    jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج مخزون للصيانة - '||p.product_name,'itemId',p.product_id)); end if;
 end loop;
 if jsonb_array_length(lines)=0 then return null; end if;
 eid:=public.erp_phase2_insert_journal(p_company_id,'maintenance_stock_issue',p_order_id::text,'MNT-'||replace(p_order_id::text,'-',''),'قيد مواد أمر الصيانة '||o.order_number,o.currency_code,lines);
 return eid;
end $$;

create or replace function public.erp_advance_cloud_maintenance_workflow(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype; v_now timestamptz:=now();
begin
 perform public.erp_active_company_context(p_company_id);
 select * into o from public.erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 if o.workflow_stage='order_draft' then
   update public.erp_maintenance_orders set workflow_stage='order_approved',status='approved',updated_at=v_now where id=o.id;
 elsif o.workflow_stage='order_approved' then
   update public.erp_maintenance_orders set workflow_stage='stock_issue_draft',stock_issue_number='MSI-'||extract(epoch from clock_timestamp())::bigint,updated_at=v_now where id=o.id;
 elsif o.workflow_stage='stock_issue_draft' then
   for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted and line_type<>'service' loop
     select * into s from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=p.warehouse_id::text and data->>'productId'=p.product_id::text for update;
     if not found or public.erp_try_numeric(s.data->>'quantity',0)<p.quantity then raise exception 'الرصيد غير كافٍ للمادة %',p.product_name; end if;
     update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',public.erp_try_numeric(data->>'quantity',0)-p.quantity,'updatedAt',v_now),updated_at=v_now where id=s.id;
     perform public.erp_inventory_insert_movement(p_company_id,p.product_id::text,p.warehouse_id::text,'maintenance_out',-p.quantity,p.unit_cost,'maintenance_order',o.id::text,'Maintenance issue '||o.order_number);
   end loop;
   perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
   perform public.erp_phase3_post_maintenance_issue(p_company_id,o.id);
   update public.erp_maintenance_orders set workflow_stage='stock_issue_approved',updated_at=v_now where id=o.id;
 elsif o.workflow_stage='stock_issue_approved' then
   update public.erp_maintenance_orders set workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,
    status=case when pricing_type='paid' then status else 'completed' end,
    invoice_number=case when pricing_type='paid' then 'MINV-'||extract(epoch from clock_timestamp())::bigint else invoice_number end,updated_at=v_now where id=o.id;
 elsif o.workflow_stage='invoice_draft' then
   update public.erp_maintenance_orders set workflow_stage='invoice_approved',updated_at=v_now where id=o.id;
 else raise exception 'لا توجد مرحلة تالية متاحة'; end if;
end $$;

create or replace function public.erp_delete_cloud_maintenance_order(p_company_id uuid,p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype;
begin
 perform public.erp_active_company_context(p_company_id);
 select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for update;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 if o.workflow_stage not in ('order_draft','order_approved','cancelled') then raise exception 'يجب إلغاء الأمر وعكس آثاره قبل الحذف'; end if;
 perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text);
 update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 update public.erp_maintenance_payments set is_deleted=true,deleted_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 update public.erp_maintenance_orders set is_deleted=true,deleted_at=now(),deleted_by=auth.uid(),deleted_reason=nullif(btrim(p_reason),''),updated_at=now() where id=p_order_id;
end $$;

create or replace function public.erp_get_cloud_maintenance_order_lines(p_company_id uuid,p_order_id uuid)
returns table(id uuid,"productId" uuid,"productName" text,"warehouseId" uuid,"warehouseName" text,quantity integer,"unitCost" numeric,"unitPrice" numeric,"lineType" text)
language sql security definer set search_path=public as $$
 select p.id,p.product_id,p.product_name,p.warehouse_id,w.data->>'name',p.quantity,p.unit_cost,p.unit_price,p.line_type
 from public.erp_maintenance_parts p left join public.erp_warehouses w on w.company_id=p.company_id and w.id=p.warehouse_id::text and not w.is_deleted
 where p.company_id=p_company_id and p.maintenance_order_id=p_order_id and not p.is_deleted and public.erp_active_company_context(p_company_id) is not null order by p.created_at,p.id;
$$;

drop function if exists public.erp_list_cloud_maintenance_orders(uuid);

create or replace function public.erp_list_cloud_maintenance_orders(p_company_id uuid)
returns table(id uuid,"orderNumber" text,"carId" uuid,"carName" text,"customerId" uuid,"customerName" text,"warehouseId" uuid,"isSoldCar" integer,"pricingType" text,status text,"laborCost" numeric,"partsCost" numeric,"totalCost" numeric,"salePrice" numeric,profit numeric,"carCostAdded" numeric,"maintenanceDate" timestamptz,notes text,"currencyCode" text,"exchangeRate" numeric,"workflowStage" text,"paidAmount" numeric,"invoiceNumber" text,"stockIssueNumber" text,"cancelReason" text,"maintenanceExpenseAccountId" text)
language sql security definer set search_path=public as $$
 select o.id,o.order_number,o.car_id,o.car_name,o.customer_id,o.customer_name,o.warehouse_id,case when o.is_sold_car then 1 else 0 end,o.pricing_type,o.status,o.labor_cost,o.parts_cost,o.total_cost,o.sale_price,o.profit,o.car_cost_added,o.maintenance_date,o.notes,o.currency_code,o.exchange_rate,o.workflow_stage,o.paid_amount,o.invoice_number,o.stock_issue_number,o.cancel_reason,o.maintenance_expense_account_id
 from public.erp_maintenance_orders o where o.company_id=p_company_id and not o.is_deleted and public.erp_active_company_context(p_company_id) is not null order by o.maintenance_date desc;
$$;

grant execute on function public.erp_list_cloud_maintenance_orders(uuid) to authenticated;
grant execute on function public.erp_get_cloud_maintenance_order_lines(uuid,uuid) to authenticated;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated;
grant execute on function public.erp_phase3_post_maintenance_issue(uuid,uuid) to authenticated;

create or replace function public.erp_cancel_cloud_maintenance_order(p_company_id uuid,p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype;
begin
 perform public.erp_active_company_context(p_company_id);
 select * into o from public.erp_maintenance_orders where id=p_order_id and company_id=p_company_id and not is_deleted for update;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 if o.workflow_stage='cancelled' then return; end if;
 if o.paid_amount>0 then raise exception 'يجب عكس دفعات الصيانة قبل إلغاء الأمر'; end if;
 if o.workflow_stage in ('stock_issue_approved','invoice_draft','invoice_approved','paid','completed') then
   for p in select * from public.erp_maintenance_parts where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted and line_type<>'service' loop
     select * into s from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=p.warehouse_id::text and data->>'productId'=p.product_id::text for update;
     if found then
       update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',public.erp_try_numeric(data->>'quantity',0)+p.quantity,'updatedAt',now()),updated_at=now() where id=s.id;
     else
       insert into public.erp_warehouse_stock(company_id,id,data,created_by,updated_by) values
       (p_company_id,gen_random_uuid()::text,jsonb_build_object('id',gen_random_uuid()::text,'warehouseId',p.warehouse_id::text,'productId',p.product_id::text,'quantity',p.quantity,'averageUnitCost',p.unit_cost,'createdAt',now(),'updatedAt',now()),auth.uid(),auth.uid());
     end if;
     perform public.erp_inventory_insert_movement(p_company_id,p.product_id::text,p.warehouse_id::text,'maintenance_return',p.quantity,p.unit_cost,'maintenance_cancel',o.id::text,'Maintenance cancellation '||o.order_number);
   end loop;
   perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
 end if;
 perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',o.id::text);
 update public.erp_maintenance_orders set workflow_stage='cancelled',status='cancelled',cancelled_at=now(),cancel_reason=nullif(btrim(p_reason),''),updated_at=now() where id=o.id;
end $$;
