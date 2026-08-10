begin;

-- Repair products imported by older builds where the product master still
-- carries a positive quantity but no active per-warehouse stock row exists.
-- The quantity is assigned to the product's valid warehouse when present,
-- otherwise to the first active warehouse of the company. Existing stock rows
-- are never overwritten; only products with no active stock rows are repaired.
do $$
declare
  r record;
  v_warehouse_id text;
  v_stock_id text;
  v_quantity numeric;
  v_unit_cost numeric;
begin
  for r in
    select i.company_id,i.id,i.data
    from public.erp_inventory i
    where not i.is_deleted
      and public.erp_try_boolean(i.data->>'isActive',true)
      and public.erp_try_numeric(i.data->>'quantity',0)>0
      and not exists (
        select 1
        from public.erp_warehouse_stock ws
        where ws.company_id=i.company_id
          and not ws.is_deleted
          and ws.data->>'productId'=i.id
      )
  loop
    select w.id into v_warehouse_id
    from public.erp_warehouses w
    where w.company_id=r.company_id
      and not w.is_deleted
      and public.erp_try_boolean(w.data->>'isActive',true)
      and w.id=coalesce(r.data->>'warehouseId',r.data->>'warehouse_id')
    limit 1;

    if v_warehouse_id is null then
      select w.id into v_warehouse_id
      from public.erp_warehouses w
      where w.company_id=r.company_id
        and not w.is_deleted
        and public.erp_try_boolean(w.data->>'isActive',true)
      order by
        case when lower(btrim(coalesce(w.data->>'code','')))='main' then 0 else 1 end,
        w.created_at,
        w.id
      limit 1;
    end if;

    if v_warehouse_id is null then
      continue;
    end if;

    v_quantity:=public.erp_try_numeric(r.data->>'quantity',0);
    v_unit_cost:=coalesce(
      public.erp_try_numeric(r.data->>'unitCost',null),
      public.erp_try_numeric(r.data->>'costPrice',0)
    );
    v_stock_id:=v_warehouse_id||'::'||r.id;

    update public.erp_warehouse_stock
    set is_deleted=false,
        deleted_at=null,
        data=coalesce(data,'{}'::jsonb)||jsonb_build_object(
          'warehouseId',v_warehouse_id,
          'productId',r.id,
          'quantity',v_quantity,
          'reservedQuantity',0,
          'expectedIncoming',public.erp_try_numeric(r.data->>'expectedIncoming',0),
          'expectedOutgoing',public.erp_try_numeric(r.data->>'expectedOutgoing',0),
          'averageUnitCost',v_unit_cost,
          'updatedAt',now(),
          'repairedFromProductMaster',true
        ),
        updated_at=now()
    where company_id=r.company_id and id=v_stock_id;

    if not found then
      insert into public.erp_warehouse_stock(
        company_id,id,data,created_at,updated_at,created_by,updated_by
      ) values (
        r.company_id,
        v_stock_id,
        jsonb_build_object(
          'warehouseId',v_warehouse_id,
          'productId',r.id,
          'quantity',v_quantity,
          'reservedQuantity',0,
          'expectedIncoming',public.erp_try_numeric(r.data->>'expectedIncoming',0),
          'expectedOutgoing',public.erp_try_numeric(r.data->>'expectedOutgoing',0),
          'averageUnitCost',v_unit_cost,
          'updatedAt',now(),
          'repairedFromProductMaster',true
        ),
        now(),now(),null,null
      );
    end if;
  end loop;
end $$;

-- Return only truly available stock and expose all product properties to the
-- shared visual card used by sales and purchases.
create or replace function public.erp_cloud_sales_order_catalog(p_company_id uuid)
returns setof jsonb
language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'itemType','car',
    'id',c.id,
    'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
    'availableQuantity',1,
    'basePrice',public.erp_try_numeric(c.data->>'salePrice',0),
    'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
    'details',c.data||jsonb_build_object(
      'id',c.id,
      'itemType','car',
      'availableQuantity',1,
      'salePrice',public.erp_try_numeric(c.data->>'salePrice',0)
    )
  )
  from public.erp_cars c
  where c.company_id=p_company_id
    and not c.is_deleted
    and lower(btrim(coalesce(c.data->>'status',''))) in ('available','متوفرة','متوفر','متاحة')
    and nullif(btrim(coalesce(c.data->>'warehouseId',c.data->>'warehouse_id','')),'') is not null
    and public.erp_is_company_member(p_company_id)

  union all

  select jsonb_build_object(
    'itemType','product',
    'id',i.id,
    'description',coalesce(i.data->>'name',i.data->>'code',''),
    'availableQuantity',s.available_quantity,
    'basePrice',public.erp_try_numeric(i.data->>'salePrice',0),
    'imagePath',coalesce(i.data->>'imagePath',i.data->>'imageBase64',i.data->>'image'),
    'details',i.data||jsonb_build_object(
      'id',i.id,
      'itemType','product',
      'availableQuantity',s.available_quantity,
      'quantity',s.total_quantity,
      'reservedQuantity',s.reserved_quantity,
      'unitCost',coalesce(
        public.erp_try_numeric(i.data->>'unitCost',null),
        s.average_unit_cost,
        0
      ),
      'salePrice',public.erp_try_numeric(i.data->>'salePrice',0),
      'warehouseBalances',s.warehouse_balances
    )
  )
  from public.erp_inventory i
  join lateral (
    select
      coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0) as total_quantity,
      coalesce(sum(public.erp_try_numeric(ws.data->>'reservedQuantity',0)),0) as reserved_quantity,
      coalesce(sum(greatest(
        public.erp_try_numeric(ws.data->>'quantity',0)-
        public.erp_try_numeric(ws.data->>'reservedQuantity',0),0
      )),0) as available_quantity,
      case
        when coalesce(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0)>0 then
          sum(
            public.erp_try_numeric(ws.data->>'quantity',0)*
            public.erp_try_numeric(ws.data->>'averageUnitCost',0)
          )/nullif(sum(public.erp_try_numeric(ws.data->>'quantity',0)),0)
        else 0
      end as average_unit_cost,
      coalesce(jsonb_agg(jsonb_build_object(
        'warehouseId',ws.data->>'warehouseId',
        'quantity',public.erp_try_numeric(ws.data->>'quantity',0),
        'reservedQuantity',public.erp_try_numeric(ws.data->>'reservedQuantity',0),
        'availableQuantity',greatest(
          public.erp_try_numeric(ws.data->>'quantity',0)-
          public.erp_try_numeric(ws.data->>'reservedQuantity',0),0
        )
      ) order by ws.data->>'warehouseId'),'[]'::jsonb) as warehouse_balances
    from public.erp_warehouse_stock ws
    where ws.company_id=i.company_id
      and not ws.is_deleted
      and ws.data->>'productId'=i.id
  ) s on s.available_quantity>0
  where i.company_id=p_company_id
    and not i.is_deleted
    and public.erp_try_boolean(i.data->>'isActive',true)
    and public.erp_is_company_member(p_company_id);
$$;

-- Approval uses available (quantity - reserved) stock, matching the catalog
-- and the multi-warehouse allocation validator.
create or replace function public.erp_approve_cloud_sales_order(
  p_company_id uuid,
  p_order_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_order public.erp_sales_orders_cloud%rowtype;
  r record;
  v_status text;
  v_wh text;
  v_owner text;
  v_available numeric;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  select * into v_order
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'أمر البيع غير موجود'; end if;
  if v_order.status='approved' then return; end if;
  if v_order.status<>'draft' then raise exception 'حالة أمر البيع لا تسمح بالتصديق'; end if;

  for r in
    select * from public.erp_sales_order_items_cloud
    where company_id=p_company_id and order_id=p_order_id and not is_deleted
    for update
  loop
    if r.item_type='car' then
      select lower(btrim(coalesce(data->>'status',''))),
             nullif(btrim(coalesce(data->>'warehouseId',data->>'warehouse_id','')),''),
             nullif(btrim(coalesce(data->>'salesOrderId','')),'')
      into v_status,v_wh,v_owner
      from public.erp_cars
      where company_id=p_company_id and id=r.item_id and not is_deleted
      for update;

      if not found
         or v_status not in ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع')
         or v_wh is null then
        raise exception 'السيارة % غير متاحة في مخزن للبيع',r.description;
      end if;
      if v_owner is not null and v_owner<>p_order_id::text then
        raise exception 'السيارة % مرتبطة بأمر بيع آخر',r.description;
      end if;

      update public.erp_cars
      set data=data||jsonb_build_object(
            'status','قيد البيع',
            'salesOrderId',p_order_id::text,
            'updatedAt',now()
          ),
          updated_at=now(),
          updated_by=auth.uid()
      where company_id=p_company_id and id=r.item_id;
    else
      select coalesce(sum(greatest(
        public.erp_try_numeric(data->>'quantity',0)-
        public.erp_try_numeric(data->>'reservedQuantity',0),0
      )),0)
      into v_available
      from public.erp_warehouse_stock
      where company_id=p_company_id
        and not is_deleted
        and data->>'productId'=r.item_id;

      if v_available<r.quantity then
        raise exception 'الرصيد المتاح للمنتج % غير كافٍ (المتاح: %)',r.description,v_available;
      end if;
    end if;
  end loop;

  update public.erp_sales_orders_cloud
  set status='approved',updated_at=now()
  where id=p_order_id and company_id=p_company_id;

  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,null,v_order.order_number,
    'approve_order','draft','approved',null
  );
end;
$$;

grant execute on function public.erp_cloud_sales_order_catalog(uuid) to authenticated;
grant execute on function public.erp_approve_cloud_sales_order(uuid,uuid) to authenticated;

commit;
