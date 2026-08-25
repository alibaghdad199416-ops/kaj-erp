-- Quality Line ERP V23.0.2 / R7 root-cause closure.
-- 1) Sales orders may sell stock defined in a different cost currency.
--    Revenue/customer posting stays in invoice currency; inventory/COGS stays
--    in each item's definition currency.
-- 2) Services participate in sales revenue without fake inventory/COGS lines.
-- 3) Purchase and maintenance remain definition/order-currency guarded.
-- 4) Cashbox balances are derived from both sides of posted cash movements.
-- Runtime connection/authentication configuration is intentionally untouched.
begin;

-- Sales is intentionally NOT guarded by definition currency. Purchase keeps
-- the v764 trigger and therefore still requires item currency = order currency.
drop trigger if exists trg_v764_sales_item_currency on public.erp_sales_order_items_cloud;

-- One authoritative account resolver for commercial invoice posting.
-- p_invoice_currency controls the revenue account only. Asset and COGS always
-- follow the stock definition currency.
create or replace function public.erp_v736_item_accounting(
  p_company_id uuid,p_item_type text,p_item_id text,p_invoice_currency text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_data jsonb;
  v_cost_currency text;
  v_invoice_currency text:=upper(nullif(btrim(coalesce(p_invoice_currency,'')),''));
  v_item_kind text;
  v_asset text;
  v_expense text;
  v_revenue text;
begin
  v_data:=public.erp_v764_definition_data(p_company_id,p_item_type,p_item_id);
  v_cost_currency:=public.erp_v764_definition_currency(p_company_id,p_item_type,p_item_id);
  v_item_kind:=lower(coalesce(v_data->>'itemType',v_data->>'item_type',
    case when lower(btrim(coalesce(p_item_type,'')))='service' then 'service' else 'stock' end));

  if v_item_kind<>'service' then
    v_asset:=nullif(coalesce(v_data->>'inventoryAssetAccountId',v_data->>'inventory_asset_account_id'),'');
    v_expense:=nullif(coalesce(
      v_data->>'salesCostExpenseAccountId',v_data->>'sales_cost_expense_account_id',
      v_data->>'costOfSalesAccountId',v_data->>'cost_of_sales_account_id',
      v_data->>'costOfSaleAccountId',v_data->>'cost_of_sale_account_id'),'');
    perform public.erp_phase2_account_guard(p_company_id,v_asset,'asset',v_cost_currency);
    perform public.erp_phase2_account_guard(p_company_id,v_expense,'expense',v_cost_currency);
  end if;

  if v_invoice_currency is not null then
    if v_invoice_currency not in ('USD','IQD') then
      raise exception 'invalid_invoice_currency:%',v_invoice_currency;
    end if;
    v_revenue:=case when v_invoice_currency='USD' then
      nullif(coalesce(v_data->>'salesRevenueUsdAccountId',v_data->>'sales_revenue_usd_account_id',
        v_data->>'salesRevenueAccountId',v_data->>'sales_revenue_account_id'),'')
    else
      nullif(coalesce(v_data->>'salesRevenueIqdAccountId',v_data->>'sales_revenue_iqd_account_id',
        v_data->>'salesRevenueAccountId',v_data->>'sales_revenue_account_id'),'') end;
    perform public.erp_phase2_account_guard(p_company_id,v_revenue,'revenue',v_invoice_currency);
  end if;

  return jsonb_build_object(
    'costCurrency',v_cost_currency,
    'assetAccountId',v_asset,
    'costExpenseAccountId',v_expense,
    'revenueAccountId',v_revenue,
    'itemKind',v_item_kind,
    'data',v_data
  );
end;
$$;

-- Invoice preflight mirrors the exact posting policy instead of comparing all
-- sales item definitions to the invoice currency.
create or replace function public.erp_v767_invoice_policy_preflight(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  partner_id text; c text; partner_account text; r record; ac jsonb;
  item_currency text; item_kind text; cost_currency text;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module:%',p_module; end if;
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  c:=upper(coalesce(d.payload->>'currency',''));
  if c not in ('USD','IQD') then raise exception 'workflow_invoice_currency_invalid:%',c; end if;

  if p_module='sales' then
    select customer_id into partner_id from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=d.parent_id and not is_deleted;
    if partner_id is null then raise exception 'sales_customer_missing'; end if;
    perform public.erp_v767_assert_partner_ledgers(p_company_id,partner_id,'customer');
    partner_account:=public.erp_workflow_partner_account(p_company_id,'customer',partner_id,c);
    perform public.erp_phase2_account_guard(p_company_id,partner_account,'asset',c);

    for r in select item_type,item_id,description from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted loop
      ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,c);
      item_kind:=lower(coalesce(ac->>'itemKind','stock'));
      perform public.erp_phase2_account_guard(p_company_id,ac->>'revenueAccountId','revenue',c);
      if item_kind<>'service' then
        cost_currency:=upper(ac->>'costCurrency');
        perform public.erp_phase2_account_guard(p_company_id,ac->>'assetAccountId','asset',cost_currency);
        perform public.erp_phase2_account_guard(p_company_id,ac->>'costExpenseAccountId','expense',cost_currency);
      end if;
    end loop;
  else
    select supplier_id into partner_id from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=d.parent_id and not is_deleted;
    if partner_id is null then raise exception 'purchase_supplier_missing'; end if;
    perform public.erp_v767_assert_partner_ledgers(p_company_id,partner_id,'supplier');
    partner_account:=public.erp_workflow_partner_account(p_company_id,'supplier',partner_id,c);
    perform public.erp_phase2_account_guard(p_company_id,partner_account,'liability',c);

    for r in select item_type,item_id,description from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted loop
      item_currency:=public.erp_v764_definition_currency(p_company_id,r.item_type,r.item_id);
      if item_currency<>c then raise exception 'purchase_item_currency_mismatch:%:%:%',r.item_id,item_currency,c; end if;
      ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,null);
      item_kind:=lower(coalesce(ac->>'itemKind','stock'));
      if item_kind='service' then raise exception 'purchase_service_not_inventory_item:%',r.item_id; end if;
      cost_currency:=upper(ac->>'costCurrency');
      perform public.erp_phase2_account_guard(p_company_id,ac->>'assetAccountId','asset',cost_currency);
      perform public.erp_phase2_account_guard(p_company_id,ac->>'costExpenseAccountId','expense',cost_currency);
    end loop;
  end if;

  return jsonb_build_object('ok',true,'invoiceId',p_invoice_id,'orderId',d.parent_id,
    'module',p_module,'currency',c,'partnerAccountId',partner_account,
    'salesCrossDefinitionCurrencyAllowed',p_module='sales');
end;
$$;

-- Authoritative cash subledger balance. Explicitly classify both modern and
-- legacy movement aliases so transfer OUT can never be ignored while transfer
-- IN is counted.
create or replace function public.erp_cloud_cash_account_balances(p_company_id uuid)
returns table(cash_account_id text,balance numeric)
language sql security definer set search_path=public as $$
  select ca.id,
    public.erp_try_numeric(coalesce(ca.data->>'openingBalance',ca.data->>'opening_balance'),0)
    +coalesce(sum(case
      when lower(coalesce(ct.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
        then abs(public.erp_try_numeric(ct.data->>'amount',0))
      when lower(coalesce(ct.data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
        then -abs(public.erp_try_numeric(ct.data->>'amount',0))
      else 0 end),0) balance
  from public.erp_cash_accounts ca
  left join public.erp_cash_transactions ct
    on ct.company_id=ca.company_id and not ct.is_deleted
   and coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id')=ca.id
  where ca.company_id=p_company_id and not ca.is_deleted
    and public.is_active_company_member(p_company_id)
  group by ca.id,ca.data;
$$;

create or replace function public.erp_cloud_cash_currency_summary(p_company_id uuid,p_currency text)
returns jsonb language sql security definer set search_path=public as $$
  with accounts as (
    select coalesce(sum(public.erp_try_numeric(coalesce(data->>'openingBalance',data->>'opening_balance'),0)),0) opening_balance
    from public.erp_cash_accounts
    where company_id=p_company_id and not is_deleted
      and upper(coalesce(data->>'currency',''))=upper(p_currency)
      and public.is_active_company_member(p_company_id)
  ), movements as (
    select
      coalesce(sum(case when lower(coalesce(data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
        then abs(public.erp_try_numeric(data->>'amount',0)) else 0 end),0) receipts,
      coalesce(sum(case when lower(coalesce(data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
        then abs(public.erp_try_numeric(data->>'amount',0)) else 0 end),0) payments
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and upper(coalesce(data->>'currency',''))=upper(p_currency)
      and public.is_active_company_member(p_company_id)
  )
  select jsonb_build_object('openingBalance',a.opening_balance,'receipts',m.receipts,
    'payments',m.payments,'balance',a.opening_balance+m.receipts-m.payments)
  from accounts a cross join movements m;
$$;

create or replace function public.erp_cloud_cash_ledger_reconciliation(p_company_id uuid)
returns table(cash_account_id text,cash_account_name text,currency text,
  subledger_balance numeric,ledger_balance numeric,difference numeric)
language sql security definer set search_path=public as $$
  with cash as (
    select ca.id,ca.data->>'name' name,upper(coalesce(ca.data->>'currency','')) currency,
      coalesce(ca.data->>'accountId',ca.data->>'account_id') ledger_account_id,
      public.erp_try_numeric(coalesce(ca.data->>'openingBalance',ca.data->>'opening_balance'),0)
      +coalesce(sum(case
        when lower(coalesce(ct.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
          then abs(public.erp_try_numeric(ct.data->>'amount',0))
        when lower(coalesce(ct.data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
          then -abs(public.erp_try_numeric(ct.data->>'amount',0))
        else 0 end),0) subledger_balance
    from public.erp_cash_accounts ca
    left join public.erp_cash_transactions ct on ct.company_id=ca.company_id and not ct.is_deleted
      and coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id')=ca.id
    where ca.company_id=p_company_id and not ca.is_deleted and public.is_active_company_member(p_company_id)
    group by ca.id,ca.data
  ), ledger as (
    select a.account_id,coalesce(a.opening_balance,0)
      +coalesce(sum(case when je.id is not null then
        public.erp_try_numeric(jl.data->>'debit',0)-public.erp_try_numeric(jl.data->>'credit',0)
        else 0 end),0) ledger_balance
    from public.erp_accounts a
    left join public.erp_journal_lines jl on jl.company_id=a.organization_id
      and jl.data->>'accountId'=a.account_id and not jl.is_deleted
    left join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      and not je.is_deleted and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
        in ('posted','approved','confirmed')
    where a.organization_id=p_company_id and a.is_active and public.is_active_company_member(p_company_id)
    group by a.account_id,a.opening_balance
  )
  select c.id,c.name,c.currency,c.subledger_balance,coalesce(l.ledger_balance,0),
    c.subledger_balance-coalesce(l.ledger_balance,0)
  from cash c left join ledger l on l.account_id=c.ledger_account_id
  order by c.currency,c.name;
$$;

revoke all on function public.erp_v736_item_accounting(uuid,text,text,text) from public,anon;
revoke all on function public.erp_v767_invoice_policy_preflight(uuid,uuid,text) from public,anon;
revoke all on function public.erp_cloud_cash_account_balances(uuid) from public,anon;
revoke all on function public.erp_cloud_cash_currency_summary(uuid,text) from public,anon;
revoke all on function public.erp_cloud_cash_ledger_reconciliation(uuid) from public,anon;
grant execute on function public.erp_v736_item_accounting(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_v767_invoice_policy_preflight(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_cloud_cash_account_balances(uuid) to authenticated,service_role;
grant execute on function public.erp_cloud_cash_currency_summary(uuid,text) to authenticated,service_role;
grant execute on function public.erp_cloud_cash_ledger_reconciliation(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
