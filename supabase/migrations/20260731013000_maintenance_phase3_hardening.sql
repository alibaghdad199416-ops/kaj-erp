-- Phase 3 hardening: authoritative sold-vehicle selector, stronger validation,
-- inventory refresh after maintenance issue/return, and safer payment checks.

create or replace function public.erp_list_cloud_maintenance_eligible_cars(p_company_id uuid)
returns table(
  "carId" uuid,
  "displayName" text,
  "customerId" uuid,
  "customerName" text,
  "saleSequence" integer
)
language sql security definer set search_path=public as $$
  with latest_sale as (
    select distinct on (s.data->>'carId')
      s.data->>'carId' car_id,
      s.data->>'customerId' customer_id,
      public.erp_try_numeric(s.data->>'saleSequence',0)::integer sale_sequence
    from public.erp_sales s
    where s.company_id=p_company_id and not s.is_deleted
      and nullif(s.data->>'carId','') is not null
      and nullif(s.data->>'customerId','') is not null
    order by s.data->>'carId',
      public.erp_try_numeric(s.data->>'saleSequence',0) desc,
      coalesce(s.data->>'saleDate',s.created_at::text) desc
  )
  select c.id::uuid,
    concat_ws(' • ',
      concat_ws(' ',c.data->>'brand',c.data->>'model',c.data->>'year'),
      nullif(c.data->>'chassis',''),
      nullif(c.data->>'plateNumber',''),
      nullif(c.data->>'carNumber','')),
    ls.customer_id::uuid,
    coalesce(cu.data->>'name',concat_ws(' ',cu.data->>'firstName',cu.data->>'lastName'),ls.customer_id),
    ls.sale_sequence
  from latest_sale ls
  join public.erp_cars c on c.company_id=p_company_id and c.id=ls.car_id and not c.is_deleted
  left join public.erp_customers cu on cu.company_id=p_company_id and cu.id=ls.customer_id and not cu.is_deleted
  where public.erp_active_company_context(p_company_id) is not null
  order by 2;
$$;

grant execute on function public.erp_list_cloud_maintenance_eligible_cars(uuid) to authenticated;

create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,p_order_id uuid,p_currency text,p_lines jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare x jsonb; v_product text; v_warehouse text; v_qty numeric; v_name text;
 v_cost numeric; v_price numeric; v_available numeric; v_type text; v_stock public.erp_warehouse_stock%rowtype;
 v_cost_total numeric:=0; v_price_total numeric:=0; v_seen text[]:=array[]::text[];
begin
 if upper(coalesce(p_currency,'')) not in ('USD','IQD') then raise exception 'عملة أمر الصيانة غير مدعومة'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'أضف بند صيانة واحداً على الأقل'; end if;
 update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 for x in select value from jsonb_array_elements(p_lines) loop
   v_product:=nullif(x->>'product_id',''); v_warehouse:=nullif(x->>'warehouse_id','');
   v_qty:=public.erp_try_numeric(x->>'quantity',0); v_price:=public.erp_try_numeric(x->>'unit_price',0);
   if v_product is null or v_qty<=0 or trunc(v_qty)<>v_qty or v_price<0 then raise exception 'بيانات بند الصيانة غير صحيحة'; end if;
   if v_product=any(v_seen) then raise exception 'لا يمكن تكرار المادة أو الخدمة في أمر الصيانة'; end if;
   v_seen:=array_append(v_seen,v_product);
   select coalesce(data->>'name',data->>'nameAr'),lower(coalesce(data->>'itemType',data->>'item_type','stock')),
          public.erp_try_numeric(data->>'unitCost',data->>'purchasePrice')
     into v_name,v_type,v_cost from public.erp_inventory
    where company_id=p_company_id and id=v_product and not is_deleted
      and coalesce((data->>'isActive')::boolean,true);
   if not found then raise exception 'بند الصيانة غير موجود أو غير فعال'; end if;
   if v_type='service' then
     v_warehouse:=null; v_cost:=0;
   else
     if v_warehouse is null then raise exception 'يجب اختيار مخزن لكل مادة مخزنية'; end if;
     if not exists(select 1 from public.erp_warehouses where company_id=p_company_id and id=v_warehouse and not is_deleted) then
       raise exception 'مخزن السحب غير موجود';
     end if;
     select * into v_stock from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted
       and data->>'warehouseId'=v_warehouse and data->>'productId'=v_product for update;
     v_available:=case when found then public.erp_try_numeric(v_stock.data->>'quantity',0) else 0 end;
     if v_available<v_qty then raise exception 'الرصيد غير كافٍ للمادة %',coalesce(v_name,v_product); end if;
     if found and public.erp_try_numeric(v_stock.data->>'averageUnitCost',0)>0 then
       v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
     end if;
     perform public.erp_phase2_item_accounts(p_company_id,'product',v_product,upper(p_currency));
   end if;
   insert into public.erp_maintenance_parts(company_id,maintenance_order_id,product_id,product_name,warehouse_id,quantity,unit_cost,total_cost,line_type,unit_price,line_total_price)
   values(p_company_id,p_order_id,v_product::uuid,coalesce(v_name,v_product),v_warehouse::uuid,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,v_type,v_price,v_price*v_qty);
   v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty; v_price_total:=v_price_total+v_price*v_qty;
 end loop;
 return jsonb_build_object('costTotal',v_cost_total,'priceTotal',v_price_total);
end $$;

-- Refresh product summaries after stock issue and cancellation. Existing functions
-- remain transactional; these wrappers replace only the missing refresh behavior.
create or replace function public.erp_phase3_refresh_maintenance_products(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare p record;
begin
 for p in select distinct product_id from public.erp_maintenance_parts
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service'
 loop
   perform public.erp_inventory_refresh_product(p_company_id,p.product_id::text);
 end loop;
end $$;

grant execute on function public.erp_phase3_refresh_maintenance_products(uuid,uuid) to authenticated;
