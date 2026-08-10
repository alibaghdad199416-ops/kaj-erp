-- Phase 25: cloud-only read models for commercial workflow pages.
-- Normalized master-data tables store business fields inside data JSONB.

create or replace function public.erp_list_cloud_active_warehouses(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'id',w.id,
   'name',coalesce(w.data->>'name',''),
   'code',coalesce(w.data->>'code','')
 )
 from erp_warehouses w
 where w.company_id=p_company_id
   and not w.is_deleted
   and coalesce(nullif(w.data->>'isActive','')::boolean,true)
   and public.erp_is_company_member(p_company_id)
 order by coalesce(w.data->>'name','');
$$;

create or replace function public.erp_list_cloud_active_cash_accounts(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'id',c.id,
   'name',coalesce(c.data->>'name',''),
   'currency',coalesce(c.data->>'currency','USD')
 )
 from erp_cash_accounts c
 where c.company_id=p_company_id
   and not c.is_deleted
   and coalesce(nullif(c.data->>'isActive','')::boolean,true)
   and public.erp_is_company_member(p_company_id)
 order by coalesce(c.data->>'name','');
$$;

create or replace function public.erp_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'id',o.id::text,'orderNumber',o.order_number,'customerId',o.customer_id,
  'customerName',coalesce(c.data->>'name',''),
  'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,
  'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
  'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
  'deliveryId',d.id::text,'deliveryStatus',d.status,
  'invoiceId',i.id::text,'invoiceStatus',i.status,
  'invoiceRemaining',coalesce(nullif(i.payload->>'remainingAmount','')::numeric,0)
 )
 from erp_sales_orders_cloud o
 left join erp_customers c
   on c.id=o.customer_id and c.company_id=o.company_id and not c.is_deleted
 left join lateral (
   select x.* from erp_commercial_workflow_documents x
   where x.company_id=o.company_id and x.module='sales'
     and x.document_type='delivery' and x.parent_id=o.id and not x.is_deleted
   order by x.created_at desc limit 1
 ) d on true
 left join lateral (
   select x.* from erp_commercial_workflow_documents x
   where x.company_id=o.company_id and x.module='sales'
     and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted
   order by x.created_at desc limit 1
 ) i on true
 where o.company_id=p_company_id and not o.is_deleted
   and public.erp_is_company_member(p_company_id)
 order by o.created_at desc;
$$;

create or replace function public.erp_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'id',o.id::text,'orderNumber',o.order_number,'supplierId',o.supplier_id,
  'supplierName',coalesce(s.data->>'name',''),
  'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,
  'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
  'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
  'receiptId',r.id::text,'receiptStatus',r.status,
  'invoiceId',i.id::text,'invoiceStatus',i.status,
  'invoiceRemaining',coalesce(nullif(i.payload->>'remainingAmount','')::numeric,0)
 )
 from erp_purchase_orders_cloud o
 left join erp_suppliers s
   on s.id=o.supplier_id and s.company_id=o.company_id and not s.is_deleted
 left join lateral (
   select x.* from erp_commercial_workflow_documents x
   where x.company_id=o.company_id and x.module='purchases'
     and x.document_type='receipt' and x.parent_id=o.id and not x.is_deleted
   order by x.created_at desc limit 1
 ) r on true
 left join lateral (
   select x.* from erp_commercial_workflow_documents x
   where x.company_id=o.company_id and x.module='purchases'
     and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted
   order by x.created_at desc limit 1
 ) i on true
 where o.company_id=p_company_id and not o.is_deleted
   and public.erp_is_company_member(p_company_id)
 order by o.created_at desc;
$$;

create or replace function public.erp_cloud_sales_order_catalog(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'itemType','car','id',c.id,
   'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
   'availableQuantity',1,
   'basePrice',coalesce(nullif(c.data->>'salePrice','')::numeric,0),
   'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
   'details',c.data||jsonb_build_object('id',c.id)
 )
 from erp_cars c
 where c.company_id=p_company_id and not c.is_deleted
   and lower(coalesce(c.data->>'status','')) in ('available','متوفرة','متوفر')
   and nullif(c.data->>'warehouseId','') is not null
   and public.erp_is_company_member(p_company_id)
 union all
 select jsonb_build_object(
   'itemType','product','id',i.id,
   'description',coalesce(i.data->>'name',i.data->>'code',''),
   'availableQuantity',coalesce(sum(coalesce(nullif(ws.data->>'quantity','')::numeric,0)),0),
   'basePrice',coalesce(nullif(i.data->>'salePrice','')::numeric,0),
   'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),
   'details',i.data||jsonb_build_object(
      'id',i.id,
      'النوع','منتج','الكود',i.data->>'code',
      'الكمية المتاحة',coalesce(sum(coalesce(nullif(ws.data->>'quantity','')::numeric,0)),0),
      'الكلفة',coalesce(nullif(i.data->>'unitCost','')::numeric,0),
      'سعر البيع',coalesce(nullif(i.data->>'salePrice','')::numeric,0)
   )
 )
 from erp_inventory i
 left join erp_warehouse_stock ws
   on ws.company_id=i.company_id and ws.data->>'productId'=i.id and not ws.is_deleted
 where i.company_id=p_company_id and not i.is_deleted
   and public.erp_is_company_member(p_company_id)
 group by i.company_id,i.id,i.data
 having coalesce(sum(coalesce(nullif(ws.data->>'quantity','')::numeric,0)),0)>0;
$$;

create or replace function public.erp_cloud_purchase_order_catalog(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
   'itemType','car','id',c.id,
   'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
   'baseCost',coalesce(nullif(c.data->>'purchasePrice','')::numeric,nullif(c.data->>'costPrice','')::numeric,0),
   'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
   'details',c.data||jsonb_build_object('id',c.id)
 )
 from erp_cars c
 where c.company_id=p_company_id and not c.is_deleted
   and lower(coalesce(c.data->>'status','')) in ('known','identified','purchase_pending','معرفة','قيد الشراء')
   and public.erp_is_company_member(p_company_id)
 union all
 select jsonb_build_object(
   'itemType','product','id',i.id,
   'description',coalesce(i.data->>'name',i.data->>'code',''),
   'baseCost',coalesce(nullif(i.data->>'unitCost','')::numeric,nullif(i.data->>'costPrice','')::numeric,0),
   'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),
   'details',i.data||jsonb_build_object('id',i.id)
 )
 from erp_inventory i
 where i.company_id=p_company_id and not i.is_deleted
   and public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_get_cloud_sales_order_draft(p_company_id uuid,p_order_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'order',jsonb_build_object('id',o.id::text,'customerId',o.customer_id,'currency',o.currency,'exchangeRate',o.exchange_rate,'discount',o.discount,'notes',o.notes),
  'items',coalesce((select jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,'description',x.description,'quantity',x.quantity,'unitPrice',x.unit_price) order by x.id) from erp_sales_order_items_cloud x where x.company_id=o.company_id and x.order_id=o.id and not x.is_deleted),'[]'::jsonb)
 )
 from erp_sales_orders_cloud o
 where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
   and public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_get_cloud_purchase_order_draft(p_company_id uuid,p_order_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'order',jsonb_build_object('id',o.id::text,'supplierId',o.supplier_id,'currency',o.currency,'exchangeRate',o.exchange_rate,'discount',o.discount,'notes',o.notes),
  'items',coalesce((select jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,'description',x.description,'quantity',x.quantity,'unitCost',x.unit_cost) order by x.id) from erp_purchase_order_items_cloud x where x.company_id=o.company_id and x.order_id=o.id and not x.is_deleted),'[]'::jsonb)
 )
 from erp_purchase_orders_cloud o
 where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
   and public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_get_cloud_commercial_order_details(p_company_id uuid,p_order_id uuid,p_purchase boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_order jsonb;
 v_items jsonb;
 v_docs jsonb;
 v_module text:=case when p_purchase then 'purchases' else 'sales' end;
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 if p_purchase then
  select jsonb_build_object('id',o.id::text,'orderNumber',o.order_number,'partnerName',coalesce(s.data->>'name',''),'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,'discount',o.discount,'total',o.total,'notes',o.notes,'createdAt',o.created_at::text)
    into v_order
  from erp_purchase_orders_cloud o
  left join erp_suppliers s on s.company_id=o.company_id and s.id=o.supplier_id and not s.is_deleted
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into v_items
  from erp_purchase_order_items_cloud x
  where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
 else
  select jsonb_build_object('id',o.id::text,'orderNumber',o.order_number,'partnerName',coalesce(c.data->>'name',''),'status',o.status,'currency',o.currency,'exchangeRate',o.exchange_rate,'subtotal',o.subtotal,'discount',o.discount,'total',o.total,'notes',o.notes,'createdAt',o.created_at::text)
    into v_order
  from erp_sales_orders_cloud o
  left join erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into v_items
  from erp_sales_order_items_cloud x
  where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
 end if;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.created_at desc),'[]'::jsonb)
   into v_docs
 from erp_commercial_workflow_documents d
 where d.company_id=p_company_id and d.module=v_module and d.parent_id=p_order_id and not d.is_deleted;
 return jsonb_build_object(
   'order',v_order,
   'items',v_items,
   'logistics',coalesce((select jsonb_agg(x) from jsonb_array_elements(v_docs) x where x->>'document_type' in ('delivery','receipt')),'[]'::jsonb),
   'invoices',coalesce((select jsonb_agg(x) from jsonb_array_elements(v_docs) x where x->>'document_type'='invoice'),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(payment) from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(coalesce(d->'payload'->'payments','[]'::jsonb)) payment),'[]'::jsonb),
   'movements','[]'::jsonb,
   'journalEntries','[]'::jsonb,
   'auditTrail','[]'::jsonb
 );
end $$;

create or replace function public.erp_cloud_governance_center_snapshot(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'alerts',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',a.id,'titleAr',coalesce(a.data->>'titleAr',a.data->>'title',''),
      'severity',coalesce(a.data->>'severity','info'),'createdAt',a.created_at::text
    ) order by a.created_at desc)
    from erp_bi_alerts a
    where a.company_id=p_company_id and not a.is_deleted
      and not coalesce(nullif(a.data->>'isAcknowledged','')::boolean,false)
  ),'[]'::jsonb),
  'sessions',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',s.id::text,'deviceName',s.user_id,'lastActivityAt',s.created_at::text,
      'isActive',s.status='active'
    ) order by s.created_at desc)
    from (select * from erp_security_sessions where company_id=p_company_id order by created_at desc limit 100) s
  ),'[]'::jsonb),
  'audit',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',l.id::text,'description',l.operation||' '||l.table_name,
      'createdAt',l.changed_at::text
    ) order by l.changed_at desc)
    from (select * from erp_master_audit_log where company_id=p_company_id order by changed_at desc limit 150) l
  ),'[]'::jsonb)
 ) where public.erp_is_company_member(p_company_id);
$$;
grant execute on function public.erp_list_cloud_active_warehouses(uuid) to authenticated;
grant execute on function public.erp_list_cloud_active_cash_accounts(uuid) to authenticated;
grant execute on function public.erp_list_cloud_sales_workflow_orders(uuid) to authenticated;
grant execute on function public.erp_list_cloud_purchase_workflow_orders(uuid) to authenticated;
grant execute on function public.erp_cloud_sales_order_catalog(uuid) to authenticated;
grant execute on function public.erp_cloud_purchase_order_catalog(uuid) to authenticated;
grant execute on function public.erp_get_cloud_sales_order_draft(uuid,uuid) to authenticated;
grant execute on function public.erp_get_cloud_purchase_order_draft(uuid,uuid) to authenticated;
grant execute on function public.erp_get_cloud_commercial_order_details(uuid,uuid,boolean) to authenticated;
grant execute on function public.erp_cloud_governance_center_snapshot(uuid) to authenticated;
