begin;

create or replace function public.erp_cloud_purchase_order_catalog(p_company_id uuid)
returns setof jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'itemType','car',
    'id',c.id,
    'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
    'baseCost',coalesce(
      public.erp_try_numeric(c.data->>'purchasePrice',null),
      public.erp_try_numeric(c.data->>'costPrice',null),
      public.erp_try_numeric(c.data->>'unitCost',0)
    ),
    'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
    'details',
      c.data || jsonb_build_object(
        'id',c.id,
        'plateNumber',coalesce(c.data->>'plateNumber',c.data->>'plate'),
        'chassis',coalesce(c.data->>'chassis',c.data->>'chassisNumber',c.data->>'vin'),
        'purchasePrice',coalesce(c.data->>'purchasePrice',c.data->>'costPrice'),
        'salePrice',c.data->>'salePrice'
      )
  )
  from public.erp_cars c
  where c.company_id=p_company_id
    and not c.is_deleted
    and public.erp_is_company_member(p_company_id)
    and lower(btrim(coalesce(c.data->>'status','known'))) in (
      'known','identified','defined','registered','purchase_pending','pending_purchase',
      'available','new','draft',
      'معرفة','معرّفة','مُعرفة','قيد الشراء','قيد شراء','متوفرة','متوفر','متاحة','جديدة','مسودة'
    )
  union all
  select jsonb_build_object(
    'itemType','product',
    'id',i.id,
    'description',coalesce(i.data->>'name',i.data->>'code',''),
    'baseCost',coalesce(
      public.erp_try_numeric(i.data->>'unitCost',null),
      public.erp_try_numeric(i.data->>'costPrice',null),
      public.erp_try_numeric(i.data->>'purchasePrice',0)
    ),
    'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),
    'details',
      i.data || jsonb_build_object(
        'id',i.id,
        'code',coalesce(i.data->>'code',i.data->>'sku',i.id),
        'unitCost',coalesce(i.data->>'unitCost',i.data->>'costPrice',i.data->>'purchasePrice'),
        'salePrice',coalesce(i.data->>'salePrice',i.data->>'unitPrice')
      )
  )
  from public.erp_inventory i
  where i.company_id=p_company_id
    and not i.is_deleted
    and public.erp_try_boolean(i.data->>'isActive',true)
    and public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_cloud_contextual_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_sections jsonb:='[]'::jsonb;
  d1 date:=coalesce(p_start_date,date '1900-01-01');
  d2 date:=coalesce(p_end_date,date '2999-12-31');
  m text:=lower(btrim(coalesce(p_module,'overview')));
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;

  if m in ('overview','sales') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','sales_orders','title','Sales orders / أوامر البيع',
      'columns',jsonb_build_array('orderNumber','customer','status','currency','exchangeRate','subtotal','discount','total','notes','createdAt','updatedAt','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,coalesce(c.data->>'name',''),o.status,o.currency,o.exchange_rate,o.subtotal,o.discount,o.total,o.notes,o.created_at,o.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),to_jsonb(o)::text) order by o.created_at desc),'[]'::jsonb)
              from public.erp_sales_orders_cloud o
              left join public.erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
              left join auth.users cu on cu.id=o.created_by
              left join auth.users uu on uu.id=o.updated_by
              where o.company_id=p_company_id and not o.is_deleted and o.created_at::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','sales_items','title','Sales order items / بنود أوامر البيع',
      'columns',jsonb_build_array('orderNumber','itemType','itemId','description','quantity','unitPrice','lineTotal','itemDetails','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,x.item_type,x.item_id,x.description,x.quantity,x.unit_price,x.line_total,coalesce(c.data,i.data,'{}'::jsonb)::text,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),to_jsonb(x)::text) order by o.created_at desc,x.id),'[]'::jsonb)
              from public.erp_sales_order_items_cloud x
              join public.erp_sales_orders_cloud o on o.company_id=x.company_id and o.id=x.order_id and not o.is_deleted
              left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id
              left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id
              left join auth.users cu on cu.id=x.created_by
              left join auth.users uu on uu.id=x.updated_by
              where x.company_id=p_company_id and not x.is_deleted and o.created_at::date between d1 and d2)));
  end if;

  if m in ('overview','purchases') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','purchase_orders','title','Purchase orders / أوامر الشراء',
      'columns',jsonb_build_array('orderNumber','supplier','status','currency','exchangeRate','subtotal','discount','total','notes','createdAt','updatedAt','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,coalesce(s.data->>'name',''),o.status,o.currency,o.exchange_rate,o.subtotal,o.discount,o.total,o.notes,o.created_at,o.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),to_jsonb(o)::text) order by o.created_at desc),'[]'::jsonb)
              from public.erp_purchase_orders_cloud o
              left join public.erp_suppliers s on s.company_id=o.company_id and s.id=o.supplier_id and not s.is_deleted
              left join auth.users cu on cu.id=o.created_by
              left join auth.users uu on uu.id=o.updated_by
              where o.company_id=p_company_id and not o.is_deleted and o.created_at::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','purchase_items','title','Purchase order items / بنود أوامر الشراء',
      'columns',jsonb_build_array('orderNumber','itemType','itemId','description','quantity','unitCost','lineTotal','itemDetails','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,x.item_type,x.item_id,x.description,x.quantity,x.unit_cost,x.line_total,coalesce(c.data,i.data,'{}'::jsonb)::text,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),to_jsonb(x)::text) order by o.created_at desc,x.id),'[]'::jsonb)
              from public.erp_purchase_order_items_cloud x
              join public.erp_purchase_orders_cloud o on o.company_id=x.company_id and o.id=x.order_id and not o.is_deleted
              left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id
              left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id
              left join auth.users cu on cu.id=x.created_by
              left join auth.users uu on uu.id=x.updated_by
              where x.company_id=p_company_id and not x.is_deleted and o.created_at::date between d1 and d2)));
  end if;

  if m in ('overview','sales','purchases','finance','operations') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','workflow_documents','title','Workflow documents / مستندات الدورة التجارية',
      'columns',jsonb_build_array('module','documentType','documentNumber','parentId','warehouse','status','total','paid','remaining','createdAt','updatedAt','createdBy','updatedBy','payload'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(d.module,d.document_type,d.document_number,d.parent_id,coalesce(w.data->>'name',d.warehouse_id,''),d.status,public.erp_try_numeric(d.payload->>'totalAmount',0),public.erp_try_numeric(d.payload->>'paidAmount',0),public.erp_try_numeric(d.payload->>'remainingAmount',0),d.created_at,d.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),d.payload::text) order by d.created_at desc),'[]'::jsonb)
              from public.erp_commercial_workflow_documents d
              left join public.erp_warehouses w on w.company_id=d.company_id and w.id=d.warehouse_id
              left join auth.users cu on cu.id=d.created_by
              left join auth.users uu on uu.id=d.updated_by
              where d.company_id=p_company_id and not d.is_deleted and d.created_at::date between d1 and d2
                and (m in ('overview','finance','operations') or d.module=m))));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','workflow_payments','title','Invoice payments / دفعات الفواتير',
      'columns',jsonb_build_array('module','invoiceNumber','paymentId','cashAccount','paymentCurrency','cashAmount','invoiceCurrency','invoiceAmount','exchangeRate','exchangeDifference','paymentDate','notes','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(d.module,d.document_number,p.value->>'paymentId',coalesce(c.data->>'name',''),p.value->>'paymentCurrency',p.value->>'cashAmount',p.value->>'invoiceCurrency',coalesce(p.value->>'invoiceAmount',p.value->>'amount'),p.value->>'exchangeRate',p.value->>'exchangeDifference',p.value->>'paymentDate',p.value->>'notes',coalesce(p.value->>'createdByUserName',cu.email,'system'),coalesce(p.value->>'updatedByUserName',p.value->>'createdByUserName',uu.email,cu.email,'system'),p.value::text) order by public.erp_try_timestamptz(p.value->>'paymentDate',d.created_at) desc),'[]'::jsonb)
              from public.erp_commercial_workflow_documents d
              cross join lateral jsonb_array_elements(coalesce(d.payload->'payments','[]'::jsonb)) p(value)
              left join public.erp_cash_accounts c on c.company_id=d.company_id and c.id=p.value->>'cashAccountId'
              left join auth.users cu on cu.id=d.created_by
              left join auth.users uu on uu.id=d.updated_by
              where d.company_id=p_company_id and not d.is_deleted and d.document_type='invoice'
                and d.created_at::date between d1 and d2 and (m in ('overview','finance','operations') or d.module=m))));
  end if;

  if m in ('overview','inventory') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','warehouse_stock','title','Warehouse stock / أرصدة المخازن',
      'columns',jsonb_build_array('productCode','productName','warehouse','quantity','reservedQuantity','availableQuantity','expectedIncoming','expectedOutgoing','averageUnitCost','stockValue','updatedAt','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(i.data->>'code',i.data->>'name',w.data->>'name',public.erp_try_numeric(s.data->>'quantity',0),public.erp_try_numeric(s.data->>'reservedQuantity',0),public.erp_try_numeric(s.data->>'quantity',0)-public.erp_try_numeric(s.data->>'reservedQuantity',0),public.erp_try_numeric(s.data->>'expectedIncoming',0),public.erp_try_numeric(s.data->>'expectedOutgoing',0),public.erp_try_numeric(s.data->>'averageUnitCost',0),public.erp_try_numeric(s.data->>'quantity',0)*public.erp_try_numeric(s.data->>'averageUnitCost',0),s.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),s.data::text) order by i.data->>'name',w.data->>'name'),'[]'::jsonb)
              from public.erp_warehouse_stock s
              left join public.erp_inventory i on i.company_id=s.company_id and i.id=s.data->>'productId'
              left join public.erp_warehouses w on w.company_id=s.company_id and w.id=s.data->>'warehouseId'
              left join auth.users cu on cu.id=s.created_by
              left join auth.users uu on uu.id=s.updated_by
              where s.company_id=p_company_id and not s.is_deleted)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','inventory_movements','title','Inventory movements / الحركات المخزنية',
      'columns',jsonb_build_array('movementNumber','product','warehouse','movementType','quantity','unitCost','referenceType','referenceId','movementDate','notes','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(x.data->>'movementNumber',coalesce(i.data->>'name',x.data->>'productId'),coalesce(w.data->>'name',x.data->>'warehouseId'),x.data->>'movementType',x.data->>'quantity',x.data->>'unitCost',x.data->>'referenceType',x.data->>'referenceId',x.data->>'movementDate',x.data->>'notes',coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),x.data::text) order by public.erp_try_timestamptz(x.data->>'movementDate',x.created_at) desc),'[]'::jsonb)
              from public.erp_inventory_movements x
              left join public.erp_inventory i on i.company_id=x.company_id and i.id=x.data->>'productId'
              left join public.erp_warehouses w on w.company_id=x.company_id and w.id=x.data->>'warehouseId'
              left join auth.users cu on cu.id=x.created_by
              left join auth.users uu on uu.id=x.updated_by
              where x.company_id=p_company_id and not x.is_deleted and coalesce(public.erp_try_timestamptz(x.data->>'movementDate',x.created_at),x.created_at)::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','warehouse_transfers','title','Product warehouse transfers / نقل المنتجات',
      'columns',jsonb_build_array('transferNumber','fromWarehouse','toWarehouse','product','quantity','unitCost','status','transferDate','notes','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(t.data->>'transferNumber',fw.data->>'name',tw.data->>'name',coalesce(i.data->>'name',ti.data->>'productId'),ti.data->>'quantity',ti.data->>'unitCost',t.data->>'status',t.data->>'transferDate',t.data->>'notes',coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),(t.data||jsonb_build_object('item',ti.data))::text) order by public.erp_try_timestamptz(t.data->>'transferDate',t.created_at) desc),'[]'::jsonb)
              from public.erp_warehouse_transfers t
              join public.erp_warehouse_transfer_items ti on ti.company_id=t.company_id and ti.data->>'transferId'=t.id and not ti.is_deleted
              left join public.erp_inventory i on i.company_id=t.company_id and i.id=ti.data->>'productId'
              left join public.erp_warehouses fw on fw.company_id=t.company_id and fw.id=t.data->>'fromWarehouseId'
              left join public.erp_warehouses tw on tw.company_id=t.company_id and tw.id=t.data->>'toWarehouseId'
              left join auth.users cu on cu.id=t.created_by
              left join auth.users uu on uu.id=t.updated_by
              where t.company_id=p_company_id and not t.is_deleted and coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at)::date between d1 and d2)));
  end if;

  if m in ('overview','cars') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','cars','title','Vehicles / السيارات',
      'columns',jsonb_build_array('brand','model','year','chassis','plateNumber','color','status','warehouse','purchasePrice','maintenanceCost','salePrice','createdAt','updatedAt','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year',coalesce(c.data->>'chassis',c.data->>'vin'),c.data->>'plateNumber',c.data->>'color',c.data->>'status',coalesce(w.data->>'name',''),c.data->>'purchasePrice',c.data->>'maintenanceCost',c.data->>'salePrice',c.created_at,c.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),c.data::text) order by c.created_at desc),'[]'::jsonb)
              from public.erp_cars c
              left join public.erp_warehouses w on w.company_id=c.company_id and w.id=coalesce(c.data->>'warehouseId',c.data->>'warehouse_id')
              left join auth.users cu on cu.id=c.created_by
              left join auth.users uu on uu.id=c.updated_by
              where c.company_id=p_company_id and not c.is_deleted)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','car_transfers','title','Vehicle warehouse transfers / نقل السيارات',
      'columns',jsonb_build_array('transferNumber','vehicle','chassis','fromWarehouse','toWarehouse','status','transferDate','createdBy','updatedBy','notes','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(t.data->>'transferNumber',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),coalesce(c.data->>'chassis',c.data->>'vin'),fw.data->>'name',tw.data->>'name',t.data->>'status',t.data->>'transferDate',coalesce(t.data->>'createdByUserName',cu.email,'system'),coalesce(t.data->>'updatedByUserName',uu.email,cu.email,'system'),t.data->>'notes',t.data::text) order by public.erp_try_timestamptz(t.data->>'transferDate',t.created_at) desc),'[]'::jsonb)
              from public.erp_car_warehouse_transfers t
              left join public.erp_cars c on c.company_id=t.company_id and c.id=t.data->>'carId'
              left join public.erp_warehouses fw on fw.company_id=t.company_id and fw.id=t.data->>'fromWarehouseId'
              left join public.erp_warehouses tw on tw.company_id=t.company_id and tw.id=t.data->>'toWarehouseId'
              left join auth.users cu on cu.id=t.created_by
              left join auth.users uu on uu.id=t.updated_by
              where t.company_id=p_company_id and not t.is_deleted and coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at)::date between d1 and d2)));
  end if;

  if m in ('overview','finance') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','cash_transactions','title','Cash transactions / حركات الصندوق',
      'columns',jsonb_build_array('voucherNumber','type','category','cashAccount','amount','currency','exchangeRate','amountUsd','amountIqd','transactionDate','party','notes','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(x.data->>'voucherNumber',x.data->>'type',x.data->>'category',coalesce(c.data->>'name',x.data->>'cashAccountId'),x.data->>'amount',x.data->>'currency',x.data->>'exchangeRate',x.data->>'amountUsd',x.data->>'amountIqd',x.data->>'transactionDate',concat_ws(': ',x.data->>'partyType',x.data->>'partyId'),x.data->>'notes',coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),x.data::text) order by public.erp_try_timestamptz(x.data->>'transactionDate',x.created_at) desc),'[]'::jsonb)
              from public.erp_cash_transactions x
              left join public.erp_cash_accounts c on c.company_id=x.company_id and c.id=x.data->>'cashAccountId'
              left join auth.users cu on cu.id=x.created_by
              left join auth.users uu on uu.id=x.updated_by
              where x.company_id=p_company_id and not x.is_deleted and coalesce(public.erp_try_timestamptz(x.data->>'transactionDate',x.created_at),x.created_at)::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','journal_entries','title','Journal entries / القيود المحاسبية',
      'columns',jsonb_build_array('entryNumber','entryDate','description','currency','totalDebit','totalCredit','status','referenceType','referenceId','orderId','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(j.data->>'entryNumber',j.data->>'entryDate',j.data->>'description',j.data->>'currency',j.data->>'totalDebit',j.data->>'totalCredit',j.data->>'status',j.data->>'referenceType',j.data->>'referenceId',j.data->>'orderId',coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),j.data::text) order by public.erp_try_timestamptz(j.data->>'entryDate',j.created_at) desc),'[]'::jsonb)
              from public.erp_journal_entries j
              left join auth.users cu on cu.id=j.created_by
              left join auth.users uu on uu.id=j.updated_by
              where j.company_id=p_company_id and not j.is_deleted and coalesce(public.erp_try_timestamptz(j.data->>'entryDate',j.created_at),j.created_at)::date between d1 and d2)));
  end if;

  if m in ('overview','partners') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','customers','title','Customers / العملاء','columns',jsonb_build_array('id','name','phone','email','address','taxNumber','createdAt','updatedAt','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(c.id,c.data->>'name',c.data->>'phone',c.data->>'email',c.data->>'address',c.data->>'taxNumber',c.created_at,c.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),c.data::text) order by c.data->>'name'),'[]'::jsonb)
              from public.erp_customers c
              left join auth.users cu on cu.id=c.created_by
              left join auth.users uu on uu.id=c.updated_by
              where c.company_id=p_company_id and not c.is_deleted)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','suppliers','title','Suppliers / الموردون','columns',jsonb_build_array('id','name','phone','email','address','taxNumber','createdAt','updatedAt','createdBy','updatedBy','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(s.id,s.data->>'name',s.data->>'phone',s.data->>'email',s.data->>'address',s.data->>'taxNumber',s.created_at,s.updated_at,coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),s.data::text) order by s.data->>'name'),'[]'::jsonb)
              from public.erp_suppliers s
              left join auth.users cu on cu.id=s.created_by
              left join auth.users uu on uu.id=s.updated_by
              where s.company_id=p_company_id and not s.is_deleted)));
  end if;

  if m in ('overview','operations') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','commercial_audit','title','Commercial audit trail / سجل تدقيق العمليات',
      'columns',jsonb_build_array('module','documentNumber','action','fromStatus','toStatus','reason','performedBy','performedAt','parentId','documentId','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(a.module,a.document_number,a.action,a.from_status,a.to_status,a.reason,coalesce(u.email,'system'),a.performed_at,a.parent_id,a.document_id,to_jsonb(a)::text) order by a.performed_at desc),'[]'::jsonb)
              from public.erp_commercial_workflow_audit a left join auth.users u on u.id=a.performed_by
              where a.company_id=p_company_id and a.performed_at::date between d1 and d2)));
  end if;

  return v_sections;
end;
$$;

grant execute on function public.erp_cloud_purchase_order_catalog(uuid) to authenticated;
grant execute on function public.erp_cloud_contextual_report(uuid,text,date,date) to authenticated;

commit;
