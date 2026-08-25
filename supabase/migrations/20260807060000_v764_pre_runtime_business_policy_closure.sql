-- V7.6.4 pre-runtime policy closure.
-- Enforces native definition currency, partner dual-currency ledgers, canonical
-- revenue bindings and dual-currency scrap expense configuration.

create or replace function public.erp_v764_definition_data(
  p_company_id uuid, p_item_type text, p_item_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
  if lower(btrim(coalesce(p_item_type,'')))='car' then
    select data into v from public.erp_cars where company_id=p_company_id and id=p_item_id and not is_deleted;
  else
    select data into v from public.erp_inventory where company_id=p_company_id and id=p_item_id and not is_deleted;
  end if;
  if v is null then raise exception 'definition_not_found:%:%',p_item_type,p_item_id; end if;
  return v;
end; $$;

create or replace function public.erp_v764_definition_currency(
  p_company_id uuid, p_item_type text, p_item_id text
) returns text
language plpgsql security definer set search_path=public as $$
declare d jsonb; c text;
begin
  d:=public.erp_v764_definition_data(p_company_id,p_item_type,p_item_id);
  c:=upper(coalesce(nullif(d->>'definitionCurrency',''),nullif(d->>'definition_currency',''),
      nullif(d->>'costCurrency',''),nullif(d->>'cost_currency',''),nullif(d->>'currency','')));
  if c not in ('USD','IQD') then raise exception 'definition_currency_required:%:%',p_item_type,p_item_id; end if;
  return c;
end; $$;

create or replace function public.erp_v764_definition_accounts(
  p_company_id uuid, p_item_type text, p_item_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare d jsonb; c text; asset_id text; cost_id text; revenue_id text;
begin
  d:=public.erp_v764_definition_data(p_company_id,p_item_type,p_item_id);
  c:=public.erp_v764_definition_currency(p_company_id,p_item_type,p_item_id);
  asset_id:=nullif(coalesce(d->>'inventoryAssetAccountId',d->>'inventory_asset_account_id'),'');
  cost_id:=nullif(coalesce(d->>'salesCostExpenseAccountId',d->>'sales_cost_expense_account_id',
    d->>'costOfSalesAccountId',d->>'cost_of_sales_account_id'),'');
  revenue_id:=nullif(coalesce(d->>'salesRevenueAccountId',d->>'sales_revenue_account_id',
    case when c='USD' then coalesce(d->>'salesRevenueUsdAccountId',d->>'sales_revenue_usd_account_id')
         else coalesce(d->>'salesRevenueIqdAccountId',d->>'sales_revenue_iqd_account_id') end),'');
  if lower(coalesce(d->>'itemType',d->>'item_type','stock'))<>'service' then
    perform public.erp_phase2_account_guard(p_company_id,asset_id,'asset',c);
    perform public.erp_phase2_account_guard(p_company_id,cost_id,'expense',c);
  end if;
  perform public.erp_phase2_account_guard(p_company_id,revenue_id,'revenue',c);
  return jsonb_build_object('currency',c,'assetAccountId',asset_id,
    'costExpenseAccountId',cost_id,'revenueAccountId',revenue_id);
end; $$;

create or replace function public.erp_v764_assert_partner_dual_ledgers(
  p_company_id uuid, p_partner_id text, p_partner_type text
) returns void
language plpgsql security definer set search_path=public as $$
declare d jsonb; usd_id text; iqd_id text; expected_type text;
begin
  if lower(p_partner_type)='customer' then
    select data into d from public.erp_customers where company_id=p_company_id and id=p_partner_id and not is_deleted;
    usd_id:=nullif(coalesce(d->>'receivableUsdAccountId',d->>'receivable_usd_account_id'),'');
    iqd_id:=nullif(coalesce(d->>'receivableIqdAccountId',d->>'receivable_iqd_account_id'),'');
    expected_type:='asset';
  else
    select data into d from public.erp_suppliers where company_id=p_company_id and id=p_partner_id and not is_deleted;
    usd_id:=nullif(coalesce(d->>'payableUsdAccountId',d->>'payable_usd_account_id'),'');
    iqd_id:=nullif(coalesce(d->>'payableIqdAccountId',d->>'payable_iqd_account_id'),'');
    expected_type:='liability';
  end if;
  if d is null then raise exception 'partner_not_found:%',p_partner_id; end if;
  perform public.erp_phase2_account_guard(p_company_id,usd_id,expected_type,'USD');
  perform public.erp_phase2_account_guard(p_company_id,iqd_id,expected_type,'IQD');
end; $$;

create or replace function public.erp_v764_order_item_currency_guard() returns trigger
language plpgsql security definer set search_path=public as $$
declare order_currency text; item_currency text;
begin
  if tg_table_name='erp_sales_order_items_cloud' then
    select upper(currency) into order_currency from public.erp_sales_orders_cloud
      where company_id=new.company_id and id=new.order_id and not is_deleted;
  else
    select upper(currency) into order_currency from public.erp_purchase_orders_cloud
      where company_id=new.company_id and id=new.order_id and not is_deleted;
  end if;
  item_currency:=public.erp_v764_definition_currency(new.company_id,new.item_type,new.item_id);
  if order_currency is null or item_currency<>order_currency then
    raise exception 'order_item_currency_mismatch:%:%:%',new.item_id,item_currency,order_currency;
  end if;
  perform public.erp_v764_definition_accounts(new.company_id,new.item_type,new.item_id);
  return new;
end; $$;

drop trigger if exists trg_v764_sales_item_currency on public.erp_sales_order_items_cloud;
create trigger trg_v764_sales_item_currency before insert or update of item_id,item_type,order_id
on public.erp_sales_order_items_cloud for each row execute function public.erp_v764_order_item_currency_guard();

drop trigger if exists trg_v764_purchase_item_currency on public.erp_purchase_order_items_cloud;
create trigger trg_v764_purchase_item_currency before insert or update of item_id,item_type,order_id
on public.erp_purchase_order_items_cloud for each row execute function public.erp_v764_order_item_currency_guard();

create or replace function public.erp_v764_scrap_expense_account(
  p_company_id uuid,p_warehouse_id text,p_currency text
) returns text
language plpgsql security definer set search_path=public as $$
declare d jsonb; a text; c text:=upper(p_currency);
begin
  select data into d from public.erp_warehouses where company_id=p_company_id and id=p_warehouse_id and not is_deleted;
  if d is null then raise exception 'scrap_warehouse_not_found:%',p_warehouse_id; end if;
  a:=case when c='USD' then nullif(coalesce(d->>'scrapExpenseUsdAccountId',d->>'scrap_expense_usd_account_id'),'')
          when c='IQD' then nullif(coalesce(d->>'scrapExpenseIqdAccountId',d->>'scrap_expense_iqd_account_id'),'') end;
  perform public.erp_phase2_account_guard(p_company_id,a,'expense',c);
  return a;
end; $$;

create or replace function public.erp_v764_accounting_policy_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'companyId',p_company_id,
    'definitionsMissingCurrency',(select count(*) from public.erp_inventory i where i.company_id=p_company_id and not i.is_deleted and upper(coalesce(i.data->>'definitionCurrency',i.data->>'costCurrency',i.data->>'currency','')) not in ('USD','IQD'))
      +(select count(*) from public.erp_cars c where c.company_id=p_company_id and not c.is_deleted and upper(coalesce(c.data->>'definitionCurrency',c.data->>'costCurrency',c.data->>'currency','')) not in ('USD','IQD')),
    'scrapWarehousesMissingDualExpense',(select count(*) from public.erp_warehouses w where w.company_id=p_company_id and not w.is_deleted and lower(coalesce(w.data->>'warehouseType',w.data->>'type','')) in ('scrap','damage') and (coalesce(w.data->>'scrapExpenseUsdAccountId','')='' or coalesce(w.data->>'scrapExpenseIqdAccountId','')='')),
    'checkedAt',timezone('utc',now())
  ); $$;

grant execute on function public.erp_v764_definition_currency(uuid,text,text) to authenticated;
grant execute on function public.erp_v764_definition_accounts(uuid,text,text) to authenticated;
grant execute on function public.erp_v764_assert_partner_dual_ledgers(uuid,text,text) to authenticated;
grant execute on function public.erp_v764_scrap_expense_account(uuid,text,text) to authenticated;
grant execute on function public.erp_v764_accounting_policy_audit(uuid) to authenticated;
notify pgrst,'reload schema';
