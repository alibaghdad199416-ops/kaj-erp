begin;

-- Product editing keeps the stable product id, preserves server-maintained
-- stock totals, updates warehouse cache fields, and refreshes only draft order
-- descriptions. Approved/historical documents remain immutable snapshots.
create or replace function public.erp_update_inventory_product(
  p_company_id uuid,
  p_product_id text,
  p_product jsonb,
  p_images jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current public.erp_inventory%rowtype;
  v_image text;
  v_index integer := 0;
  v_name text;
  v_code text;
  v_minimum numeric;
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;

  select * into v_current
  from public.erp_inventory
  where company_id=p_company_id and id=p_product_id and not is_deleted
  for update;
  if not found then raise exception 'product_not_found'; end if;

  v_name:=btrim(coalesce(p_product->>'name',''));
  v_code:=btrim(coalesce(p_product->>'code',''));
  v_minimum:=greatest(public.erp_try_numeric(
    coalesce(p_product->>'minQuantity',p_product->>'minimumQuantity'),0
  ),0);

  if v_name='' then raise exception 'product_name_required'; end if;
  if v_code<>'' and exists (
    select 1
    from public.erp_inventory
    where company_id=p_company_id
      and id<>p_product_id
      and not is_deleted
      and lower(btrim(data->>'code'))=lower(v_code)
  ) then
    raise exception 'product_code_already_exists' using errcode='23505';
  end if;

  update public.erp_inventory
  set data = coalesce(v_current.data,'{}'::jsonb)
      || (coalesce(p_product,'{}'::jsonb)
          - 'quantity'
          - 'expectedIncoming'
          - 'expectedOutgoing'
          - 'createdAt'
          - 'created_at')
      || jsonb_build_object(
        'id',p_product_id,
        'name',v_name,
        'code',v_code,
        'quantity',public.erp_try_numeric(v_current.data->>'quantity',0),
        'expectedIncoming',public.erp_try_numeric(v_current.data->>'expectedIncoming',0),
        'expectedOutgoing',public.erp_try_numeric(v_current.data->>'expectedOutgoing',0),
        'createdAt',coalesce(v_current.data->>'createdAt',v_current.created_at::text),
        'updatedAt',now(),
        'updated_at',now()
      ),
      is_deleted=false,
      deleted_at=null,
      updated_at=now(),
      updated_by=auth.uid()
  where company_id=p_company_id and id=p_product_id;

  -- Synchronize denormalized warehouse fields used by low-stock widgets and
  -- stock reports without modifying quantities or historical average cost.
  update public.erp_warehouse_stock
  set data=coalesce(data,'{}'::jsonb)||jsonb_build_object(
        'productName',v_name,
        'productCode',v_code,
        'minimumQuantity',v_minimum,
        'updatedAt',now()
      ),
      updated_at=now(),
      updated_by=auth.uid()
  where company_id=p_company_id
    and not is_deleted
    and data->>'productId'=p_product_id;

  -- Draft documents are editable working copies and should follow the renamed
  -- product. Approved documents preserve their original printed description.
  update public.erp_sales_order_items_cloud item
  set description=v_name,
      updated_at=now(),
      updated_by=auth.uid()
  where item.company_id=p_company_id
    and item.item_type='product'
    and item.item_id=p_product_id
    and not item.is_deleted
    and exists (
      select 1 from public.erp_sales_orders_cloud o
      where o.company_id=p_company_id
        and o.id=item.order_id
        and not o.is_deleted
        and o.status='draft'
    );

  update public.erp_purchase_order_items_cloud item
  set description=v_name,
      updated_at=now(),
      updated_by=auth.uid()
  where item.company_id=p_company_id
    and item.item_type='product'
    and item.item_id=p_product_id
    and not item.is_deleted
    and exists (
      select 1 from public.erp_purchase_orders_cloud o
      where o.company_id=p_company_id
        and o.id=item.order_id
        and not o.is_deleted
        and o.status='draft'
    );

  update public.erp_product_images
  set is_deleted=true,
      deleted_at=now(),
      updated_at=now(),
      updated_by=auth.uid()
  where company_id=p_company_id
    and data->>'productId'=p_product_id
    and not is_deleted;

  if jsonb_typeof(coalesce(p_images,'[]'::jsonb))='array' then
    for v_image in select jsonb_array_elements_text(coalesce(p_images,'[]'::jsonb)) loop
      insert into public.erp_product_images(
        company_id,id,data,created_by,updated_by
      ) values (
        p_company_id,
        gen_random_uuid()::text,
        jsonb_build_object(
          'productId',p_product_id,
          'imageBase64',v_image,
          'sortOrder',v_index,
          'createdAt',now(),
          'updatedAt',now()
        ),
        auth.uid(),auth.uid()
      );
      v_index:=v_index+1;
    end loop;
  end if;

  -- The stock table is authoritative for quantity and cost projections.
  perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
end;
$$;

revoke all on function public.erp_update_inventory_product(uuid,text,jsonb,jsonb)
  from public,anon;
grant execute on function public.erp_update_inventory_product(uuid,text,jsonb,jsonb)
  to authenticated,service_role;

commit;
