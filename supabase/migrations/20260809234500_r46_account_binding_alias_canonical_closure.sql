begin;

-- R46 INVOICE POSTING BOUNDARY + ACCOUNT ALIAS CANONICAL CLOSURE
-- Accounting validation/posting belongs to invoice approval, not order approval.
-- Logistics approval remains quantity/state only (R736). Maintenance stock issue
-- posting remains disabled; maintenance accounting is owned by invoice approval.

-- Commercial order lines validate business currency only. Do not resolve or
-- mutate accounting bindings while creating/approving an order.
create or replace function public.erp_v764_order_item_currency_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare order_currency text; item_currency text;
begin
  if tg_table_name='erp_sales_order_items_cloud' then
    select upper(currency) into order_currency from public.erp_sales_orders_cloud
     where company_id=new.company_id and id=new.order_id and not is_deleted;
  elsif tg_table_name='erp_purchase_order_items_cloud' then
    select upper(currency) into order_currency from public.erp_purchase_orders_cloud
     where company_id=new.company_id and id=new.order_id and not is_deleted;
  else
    raise exception 'unsupported_commercial_item_table:%',tg_table_name;
  end if;
  item_currency:=public.erp_v764_definition_currency(new.company_id,new.item_type,new.item_id);
  if order_currency is null or item_currency<>order_currency then
    raise exception 'order_item_currency_mismatch:%:%:%',new.item_id,item_currency,order_currency;
  end if;
  return new;
end $$;

-- Resolve historical aliases only when accounting is actually requested by the
-- invoice-owned posting engines. Prefer explicit salesCostExpense aliases.
create or replace function public.erp_phase2_item_accounts(
  p_company_id uuid,p_item_type text,p_item_id text,p_currency text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_data jsonb; v_defaults jsonb; v_asset_id text; v_expense_id text;
  v_currency text:=upper(coalesce(nullif(btrim(p_currency),''),'USD'));
  v_patch jsonb; v_asset_exact boolean; v_expense_exact boolean;
begin
  if lower(btrim(p_item_type))='car' then
    select c.data into v_data from public.erp_cars c
     where c.company_id=p_company_id and c.id=p_item_id and not c.is_deleted;
  else
    select i.data into v_data from public.erp_inventory i
     where i.company_id=p_company_id and i.id=p_item_id and not i.is_deleted;
  end if;
  if v_data is null then raise exception 'inventory_item_not_found:%',p_item_id; end if;
  if lower(coalesce(v_data->>'itemType',v_data->>'item_type','stock'))='service' then
    raise exception 'service_item_has_no_inventory_posting:%',p_item_id;
  end if;

  v_defaults:=public.erp_v735_ensure_operational_accounts(p_company_id);
  v_asset_id:=nullif(coalesce(v_data->>'inventoryAssetAccountId',v_data->>'inventory_asset_account_id'),'');
  v_expense_id:=nullif(coalesce(
    v_data->>'salesCostExpenseAccountId',v_data->>'sales_cost_expense_account_id',
    v_data->>'costOfSalesAccountId',v_data->>'costOfSaleAccountId',
    v_data->>'cost_of_sales_account_id',v_data->>'cost_of_sale_account_id'),'');

  if not public.erp_v735_account_usable(p_company_id,v_asset_id,'asset',v_currency) then
    v_asset_id:=v_defaults->>'inventoryAssetAccountId';
  end if;
  if not public.erp_v735_account_usable(p_company_id,v_expense_id,'expense',v_currency) then
    v_expense_id:=v_defaults->>'costExpenseAccountId';
  end if;
  perform public.erp_phase2_account_guard(p_company_id,v_asset_id,'asset',v_currency);
  perform public.erp_phase2_account_guard(p_company_id,v_expense_id,'expense',v_currency);

  -- The master-data trigger requires exact currency. Canonicalize aliases only
  -- when both resolved accounts satisfy that stricter contract; MULTI fallbacks
  -- remain posting fallbacks and are never written over explicit master data.
  select exists(select 1 from public.erp_accounts a where a.organization_id=p_company_id
    and a.account_id=v_asset_id and a.is_active and lower(a.account_type)='asset'
    and upper(coalesce(a.currency,''))=v_currency) into v_asset_exact;
  select exists(select 1 from public.erp_accounts a where a.organization_id=p_company_id
    and a.account_id=v_expense_id and a.is_active and lower(a.account_type)='expense'
    and upper(coalesce(a.currency,''))=v_currency) into v_expense_exact;

  if v_asset_exact and v_expense_exact then
    v_patch:=jsonb_build_object(
      'inventoryAssetAccountId',v_asset_id,'inventory_asset_account_id',v_asset_id,
      'salesCostExpenseAccountId',v_expense_id,'sales_cost_expense_account_id',v_expense_id,
      'costOfSalesAccountId',v_expense_id,'costOfSaleAccountId',v_expense_id,
      'cost_of_sales_account_id',v_expense_id,'cost_of_sale_account_id',v_expense_id,
      'accountBindingsRepairedAt',now());
    if lower(btrim(p_item_type))='car' then
      update public.erp_cars set data=data||v_patch,updated_at=now(),updated_by=auth.uid()
       where company_id=p_company_id and id=p_item_id and not is_deleted
         and (coalesce(data->>'inventoryAssetAccountId','')<>v_asset_id
           or coalesce(data->>'salesCostExpenseAccountId','')<>v_expense_id
           or coalesce(data->>'costOfSalesAccountId','')<>v_expense_id);
    else
      update public.erp_inventory set data=data||v_patch,updated_at=now(),updated_by=auth.uid()
       where company_id=p_company_id and id=p_item_id and not is_deleted
         and (coalesce(data->>'inventoryAssetAccountId','')<>v_asset_id
           or coalesce(data->>'salesCostExpenseAccountId','')<>v_expense_id
           or coalesce(data->>'costOfSalesAccountId','')<>v_expense_id);
    end if;
  end if;
  return jsonb_build_object('assetAccountId',v_asset_id,'costExpenseAccountId',v_expense_id);
end $$;

notify pgrst,'reload schema';
commit;
