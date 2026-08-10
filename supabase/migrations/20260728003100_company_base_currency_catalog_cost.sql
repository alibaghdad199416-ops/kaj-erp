-- Enforce catalog acquisition cost in the company's primary currency.
-- Sales prices remain in the currency selected on the approved sales invoice.
-- Cross-currency equivalence is intentionally handled only by payment settlement.
create or replace function public.erp_sync_catalog_price_from_workflow_invoice(
  p_company_id uuid, p_order_id uuid, p_module text
) returns void language plpgsql security definer set search_path=public as $$
declare
  r record;
  v_currency text;
  v_base_currency text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  select upper(coalesce(
    (select payload->>'code' from public.erp_records
      where company_id=p_company_id::text and entity_type='currencies'
        and deleted_at is null and coalesce((payload->>'isBase')::boolean,false)
      limit 1),
    (select payload->>'default_currency' from public.erp_records
      where company_id=p_company_id::text and entity_type='app_settings'
        and record_id='company' and deleted_at is null limit 1),
    'USD')) into v_base_currency;

  if p_module='sales' then
    select upper(currency) into v_currency
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;

    for r in select item_type,item_id,unit_price
      from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
    loop
      if r.item_type='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'salePrice',r.unit_price,'sale_price',r.unit_price,
          'saleCurrency',v_currency,'salePriceSource','sales_invoice','updatedAt',now()
        ),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'salePrice',r.unit_price,'sale_price',r.unit_price,
          'saleCurrency',v_currency,'salePriceSource','sales_invoice','updatedAt',now()
        ),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
    end loop;
  elsif p_module='purchases' then
    select upper(currency) into v_currency
    from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;

    if v_currency is distinct from v_base_currency then
      raise exception 'purchase_invoice_must_use_company_base_currency:%',v_base_currency;
    end if;

    for r in select item_type,item_id,unit_cost
      from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
    loop
      if r.item_type='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'purchasePrice',r.unit_cost,'purchase_price',r.unit_cost,'costPrice',r.unit_cost,
          'costCurrency',v_base_currency,'purchasePriceSource','purchase_invoice','updatedAt',now()
        ),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'purchasePrice',r.unit_cost,'purchase_price',r.unit_cost,
          'unitCost',r.unit_cost,'unit_cost',r.unit_cost,
          'costCurrency',v_base_currency,'purchasePriceSource','purchase_invoice','updatedAt',now()
        ),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
    end loop;
  else
    raise exception 'invalid workflow module';
  end if;
end;
$$;
