begin;

-- R45 PURCHASE ORDER RPC FUNCTIONAL CLOSURE

create or replace function public.erp_v764_order_item_currency_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  order_currency text;
  item_currency text;
begin
  if tg_table_name = 'erp_sales_order_items_cloud' then
    select upper(currency)
      into order_currency
    from public.erp_sales_orders_cloud
    where company_id = new.company_id
      and id = new.order_id
      and not is_deleted;

  elsif tg_table_name = 'erp_purchase_order_items_cloud' then
    select upper(currency)
      into order_currency
    from public.erp_purchase_orders_cloud
    where company_id = new.company_id
      and id = new.order_id
      and not is_deleted;

  else
    raise exception 'unsupported_commercial_item_table:%', tg_table_name;
  end if;

  item_currency :=
    public.erp_v764_definition_currency(
      new.company_id,
      new.item_type,
      new.item_id
    );

  if order_currency is null
     or item_currency <> order_currency then
    raise exception
      'order_item_currency_mismatch:%:%:%',
      new.item_id,
      item_currency,
      order_currency;
  end if;

  if tg_table_name = 'erp_purchase_order_items_cloud' then
    perform public.erp_phase2_item_accounts(
      new.company_id,
      new.item_type,
      new.item_id,
      order_currency
    );
  else
    perform public.erp_v764_definition_accounts(
      new.company_id,
      new.item_type,
      new.item_id
    );
  end if;

  return new;
end;
$$;

notify pgrst, 'reload schema';

commit;