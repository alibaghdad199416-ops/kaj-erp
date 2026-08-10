-- Final consolidation of invoice-driven valuation and document-currency accounting.
-- Catalog cost/price is taken from the approved commercial invoice's order lines.
-- Exchange-rate conversion remains exclusively inside payment settlement functions.
create or replace function public.erp_sync_catalog_price_from_workflow_invoice(
  p_company_id uuid, p_order_id uuid, p_module text
) returns void language plpgsql security definer set search_path=public as $$
declare
  r record;
  v_currency text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  if p_module='sales' then
    select upper(currency) into v_currency
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;

    for r in
      select item_type,item_id,unit_price
      from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
    loop
      if r.item_type='car' then
        update public.erp_cars
        set data=data||jsonb_build_object(
          'salePrice',r.unit_price,
          'sale_price',r.unit_price,
          'currency',v_currency,
          'salePriceSource','sales_invoice',
          'updatedAt',now()
        ), updated_at=now(), updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory
        set data=data||jsonb_build_object(
          'salePrice',r.unit_price,
          'sale_price',r.unit_price,
          'currency',v_currency,
          'salePriceSource','sales_invoice',
          'updatedAt',now()
        ), updated_at=now(), updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
    end loop;

  elsif p_module='purchases' then
    select upper(currency) into v_currency
    from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;

    for r in
      select item_type,item_id,unit_cost
      from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
    loop
      if r.item_type='car' then
        update public.erp_cars
        set data=data||jsonb_build_object(
          'purchasePrice',r.unit_cost,
          'purchase_price',r.unit_cost,
          'costPrice',r.unit_cost,
          'currency',v_currency,
          'purchasePriceSource','purchase_invoice',
          'updatedAt',now()
        ), updated_at=now(), updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory
        set data=data||jsonb_build_object(
          'purchasePrice',r.unit_cost,
          'purchase_price',r.unit_cost,
          'unitCost',r.unit_cost,
          'unit_cost',r.unit_cost,
          'currency',v_currency,
          'purchasePriceSource','purchase_invoice',
          'updatedAt',now()
        ), updated_at=now(), updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
    end loop;
  else
    raise exception 'invalid workflow module';
  end if;
end;
$$;

create or replace function public.erp_catalog_price_invoice_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.document_type='invoice'
     and new.status='approved'
     and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform public.erp_sync_catalog_price_from_workflow_invoice(
      new.company_id,new.parent_id,new.module
    );
  end if;
  return new;
end;
$$;

drop trigger if exists erp_catalog_price_invoice_trigger
  on public.erp_commercial_workflow_documents;
create trigger erp_catalog_price_invoice_trigger
after insert or update of status
on public.erp_commercial_workflow_documents
for each row execute function public.erp_catalog_price_invoice_trigger();

revoke all on function public.erp_sync_catalog_price_from_workflow_invoice(uuid,uuid,text)
  from public,anon;
grant execute on function public.erp_sync_catalog_price_from_workflow_invoice(uuid,uuid,text)
  to authenticated;
