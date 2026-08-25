-- Quality Line ERP R9 complete closure.
-- Close the remaining field-permission bypasses in normalized accounting,
-- fixed assets, commercial workflow readers, and financial write RPCs.
begin;

create or replace function public.erp_r9_result_field_for_key(
  p_resource text,
  p_key text
) returns text
language sql immutable as $$
  select case trim(coalesce(p_resource,''))
    when 'sales' then case trim(coalesce(p_key,''))
      when 'orderNumber' then 'orderNumber'
      when 'customerId' then 'customerId' when 'customerName' then 'customerName'
      when 'carId' then 'carId' when 'opportunityId' then 'opportunityId'
      when 'currency' then 'currencyCode' when 'currencyCode' then 'currencyCode'
      when 'exchangeRate' then 'exchangeRate'
      when 'effectiveAt' then 'operationalDate' when 'saleDate' then 'operationalDate'
      when 'subtotal' then 'subtotal' when 'discount' then 'discount' when 'total' then 'total'
      when 'notes' then 'notes' when 'status' then 'status'
      when 'deliveryId' then 'delivery' when 'deliveryStatus' then 'delivery'
      when 'receiptId' then 'delivery' when 'receiptStatus' then 'delivery'
      when 'invoiceId' then 'invoice' when 'invoiceStatus' then 'invoice'
      when 'invoiceNumber' then 'invoice' when 'invoiceRemaining' then 'payments'
      when 'paidAmount' then 'payments' when 'remainingAmount' then 'payments'
      when 'createdAt' then 'createdAt' when 'updatedAt' then 'updatedAt'
      else null end
    when 'purchases' then case trim(coalesce(p_key,''))
      when 'orderNumber' then 'orderNumber'
      when 'supplierId' then 'supplierId' when 'supplierName' then 'supplierName'
      when 'opportunityId' then 'opportunityId'
      when 'currency' then 'currencyCode' when 'currencyCode' then 'currencyCode'
      when 'exchangeRate' then 'exchangeRate'
      when 'effectiveAt' then 'operationalDate' when 'purchaseDate' then 'operationalDate'
      when 'subtotal' then 'subtotal' when 'discount' then 'discount' when 'total' then 'total'
      when 'notes' then 'notes' when 'status' then 'status'
      when 'receiptId' then 'receipt' when 'receiptNumber' then 'receipt' when 'receiptStatus' then 'receipt'
      when 'deliveryId' then 'receipt' when 'deliveryStatus' then 'receipt'
      when 'invoiceId' then 'invoice' when 'invoiceNumber' then 'invoice' when 'invoiceStatus' then 'invoice'
      when 'invoiceRemaining' then 'payments' when 'paidAmount' then 'payments' when 'remainingAmount' then 'payments'
      when 'createdAt' then 'createdAt' when 'updatedAt' then 'updatedAt'
      else null end
    when 'maintenance' then case trim(coalesce(p_key,''))
      when 'orderNumber' then 'orderNumber'
      when 'carId' then 'carId' when 'carName' then 'carName' when 'displayName' then 'carName'
      when 'customerId' then 'customerId' when 'customerName' then 'customerName'
      when 'warehouseId' then 'warehouseId' when 'warehouseName' then 'itemWarehouse'
      when 'currencyCode' then 'currencyCode' when 'exchangeRate' then 'exchangeRate'
      when 'maintenanceDate' then 'operationalDate'
      when 'pricingType' then 'pricingType' when 'laborCost' then 'laborCost'
      when 'partsCost' then 'partsCost' when 'totalCost' then 'totalCost'
      when 'salePrice' then 'salePrice' when 'profit' then 'profit' when 'carCostAdded' then 'carCostAdded'
      when 'notes' then 'notes' when 'status' then 'status' when 'workflowStage' then 'workflowStage'
      when 'paidAmount' then 'payments'
      when 'invoiceNumber' then 'invoiceNumber'
      when 'stockIssueNumber' then 'stockIssueNumber'
      when 'cancelReason' then 'cancelReason'
      when 'maintenanceExpenseAccountId' then 'maintenanceExpenseAccountId'
      when 'isSoldCar' then 'isSoldCar'
      when 'productId' then 'items' when 'productName' then 'items'
      when 'quantity' then 'itemQuantity'
      when 'unitCost' then 'itemPrice' when 'unitPrice' then 'itemPrice'
      when 'lineType' then 'items'
      when 'saleSequence' then 'status'
      else null end
    when 'accounting' then case trim(coalesce(p_key,''))
      when 'code' then 'accountCode' when 'accountCode' then 'accountCode'
      when 'name' then 'accountName' when 'accountName' then 'accountName'
      when 'type' then 'accountType' when 'accountType' then 'accountType'
      when 'parentId' then 'parentAccount'
      when 'currency' then 'currency'
      when 'openingBalance' then 'openingBalance'
      when 'isActive' then 'isActive'
      when 'entryNumber' then 'entryNumber' when 'entryDate' then 'entryDate'
      when 'entryDescription' then 'description' when 'lineDescription' then 'description' when 'description' then 'description'
      when 'accountId' then 'journalLines'
      when 'debit' then 'debit' when 'credit' then 'credit'
      when 'referenceType' then 'reference' when 'referenceId' then 'reference'
      when 'totalDebit' then 'debit' when 'totalCredit' then 'credit'
      when 'balance' then 'balances' when 'opening' then 'balances' when 'closing' then 'balances'
      when 'createdAt' then 'entryDate' when 'updatedAt' then 'entryDate'
      else null end
    when 'fixed_assets' then case trim(coalesce(p_key,''))
      when 'asset_code' then 'assetCode' when 'assetCode' then 'assetCode'
      when 'name' then 'name'
      when 'acquisition_date' then 'operationalDate' when 'acquisitionDate' then 'operationalDate'
      when 'acquisition_cost' then 'acquisitionCost' when 'acquisitionCost' then 'acquisitionCost'
      when 'salvage_value' then 'salvageValue' when 'salvageValue' then 'salvageValue'
      when 'useful_life_months' then 'usefulLifeMonths' when 'usefulLifeMonths' then 'usefulLifeMonths'
      when 'currency' then 'currency'
      when 'depreciation_method' then 'depreciationMethod' when 'depreciationMethod' then 'depreciationMethod'
      when 'declining_rate' then 'decliningRate' when 'decliningRate' then 'decliningRate'
      when 'asset_account_id' then 'assetAccount' when 'assetAccountId' then 'assetAccount'
      when 'accumulated_depreciation_account_id' then 'accumulatedDepreciationAccount' when 'accumulatedDepreciationAccountId' then 'accumulatedDepreciationAccount'
      when 'depreciation_expense_account_id' then 'depreciationExpenseAccount' when 'depreciationExpenseAccountId' then 'depreciationExpenseAccount'
      when 'accumulated_depreciation' then 'accumulatedDepreciation'
      when 'current_book_value' then 'bookValue'
      when 'last_depreciation_date' then 'depreciationPostingDate'
      when 'is_active' then 'isActive' when 'isActive' then 'isActive'
      when 'status' then 'status' when 'notes' then 'notes'
      else null end
    when 'cashbox' then case trim(coalesce(p_key,''))
      when 'cash_account_id' then 'cashAccount' when 'cashAccountId' then 'cashAccount'
      when 'cash_account_name' then 'name'
      when 'currency' then 'currency'
      when 'balance' then 'balance' when 'subledger_balance' then 'balance'
      when 'ledger_balance' then 'ledgerBalance'
      when 'difference' then 'reconciliationDifference'
      when 'openingBalance' then 'openingBalance'
      when 'receipts' then 'amount' when 'payments' then 'amount'
      else public.erp_r9_logical_field_for_json_key('cashbox',p_key) end
    when 'expenses' then case trim(coalesce(p_key,''))
      when 'total' then 'amount'
      else public.erp_r9_logical_field_for_json_key('expenses',p_key) end
    else public.erp_r9_logical_field_for_json_key(p_resource,p_key)
  end
$$;

create or replace function public.erp_r9_filter_result_json(
  p_company_id uuid,
  p_resource text,
  p_payload jsonb,
  p_base_permission text default null
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
begin
  if p_base_permission is not null and btrim(p_base_permission)<>''
     and not public.erp_cloud_user_has_permission(p_company_id,p_base_permission) then
    raise exception 'permission_denied:%',p_base_permission using errcode='42501';
  end if;
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,btrim(p_resource)||'.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_field:=public.erp_r9_result_field_for_key(p_resource,v_item.key);
    if v_item.key in ('id','_cloudVersion','_cloudUpdatedAt','documentType','documentTitle')
       or (v_field is not null and public.erp_cloud_user_can_view_field(p_company_id,p_resource,v_field,null)) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_require_field_edit(
  p_company_id uuid,p_resource text,p_field text,p_base_permission text default null
) returns void language plpgsql stable security definer set search_path=public as $$
begin
  if p_base_permission is not null and btrim(p_base_permission)<>''
     and not public.erp_cloud_user_has_permission(p_company_id,p_base_permission) then
    raise exception 'permission_denied:%',p_base_permission using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_edit_field(p_company_id,p_resource,p_field,null) then
    raise exception 'field_permission_denied:%.%',p_resource,p_field using errcode='42501';
  end if;
end;
$$;

-- ------------------------- normalized accounting reads ----------------------
create or replace function public.erp_r9_list_cloud_ledger_accounts(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
    p_company_id,'accounting',
    jsonb_build_object(
      'id',a.account_id,'code',a.code,'name',a.name,'type',a.account_type,
      'parentId',a.parent_account_id,'currency',a.currency,
      'openingBalance',a.opening_balance,'isActive',a.is_active,
      'createdAt',a.synced_at,'updatedAt',a.source_updated_at
    ),'accounting.view')
  from public.erp_accounts a
  where a.organization_id=p_company_id and a.is_active
    and public.is_active_company_member(p_company_id)
  order by a.code;
$$;

create or replace function public.erp_r9_list_journal_lines(p_company_id uuid,p_entry_id text)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'accounting',jl.data,'accounting.view')
  from public.erp_journal_lines jl
  where jl.company_id=p_company_id and not jl.is_deleted and jl.data->>'entryId'=p_entry_id
  order by jl.created_at;
$$;

create or replace function public.erp_r9_cloud_account_statement(
  p_company_id uuid,p_account_id text,p_from_date timestamptz,p_to_date timestamptz
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'accounting',to_jsonb(x),'accounting.view')
  from public.erp_cloud_account_statement(p_company_id,p_account_id,p_from_date,p_to_date) x;
$$;

-- ----------------------------- fixed assets --------------------------------
create or replace function public.erp_r9_list_fixed_assets(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
    p_company_id,'fixed_assets',
    jsonb_build_object(
      'id',fa.id,'asset_code',fa.asset_code,'name',fa.name,
      'acquisition_date',fa.acquisition_date,'acquisition_cost',fa.acquisition_cost,
      'salvage_value',fa.salvage_value,'useful_life_months',fa.useful_life_months,
      'current_book_value',fa.current_book_value,'status',fa.status,
      'depreciation_method',fa.depreciation_method,'declining_rate',fa.declining_rate,
      'currency',fa.currency,'asset_account_id',fa.asset_account_id,
      'accumulated_depreciation_account_id',fa.accumulated_depreciation_account_id,
      'depreciation_expense_account_id',fa.depreciation_expense_account_id,
      'accumulated_depreciation',fa.accumulated_depreciation,
      'last_depreciation_date',fa.last_depreciation_date,'is_active',fa.is_active,
      'notes',fa.notes
    ),'accounting.view')
  from public.erp_fixed_assets fa
  where fa.company_id=p_company_id and not fa.is_deleted
  order by fa.asset_code;
$$;

create or replace function public.erp_r9_guard_fixed_asset_payload(
  p_company_id uuid,p_asset jsonb
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_id uuid:=nullif(p_asset->>'id','')::uuid;
  a public.erp_fixed_assets%rowtype;
  r jsonb:=coalesce(p_asset,'{}'::jsonb);
  pair text[];
  item text;
  k text;
  f text;
  oldv jsonb;
  v_exists boolean:=false;
begin
  select * into a from public.erp_fixed_assets where company_id=p_company_id and id=v_id and not is_deleted;
  v_exists:=found;
  if v_exists then
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
      raise exception 'permission_denied:accounting.update' using errcode='42501';
    end if;
  else
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then
      raise exception 'permission_denied:accounting.create' using errcode='42501';
    end if;
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'fixed_assets.fields.restrict') then return r; end if;
  pair:=array[
    'assetCode=assetCode','name=name','acquisitionDate=operationalDate','acquisitionCost=acquisitionCost',
    'salvageValue=salvageValue','usefulLifeMonths=usefulLifeMonths','depreciationMethod=depreciationMethod',
    'decliningRate=decliningRate','currency=currency','assetAccountId=assetAccount',
    'accumulatedDepreciationAccountId=accumulatedDepreciationAccount',
    'depreciationExpenseAccountId=depreciationExpenseAccount','isActive=isActive','notes=notes'
  ];
  foreach item in array pair loop
    k:=split_part(item,'=',1); f:=split_part(item,'=',2);
    if public.erp_cloud_user_can_edit_field(p_company_id,'fixed_assets',f,null) then continue; end if;
    if v_exists then
      oldv:=case k
        when 'assetCode' then to_jsonb(a.asset_code) when 'name' then to_jsonb(a.name)
        when 'acquisitionDate' then to_jsonb(a.acquisition_date) when 'acquisitionCost' then to_jsonb(a.acquisition_cost)
        when 'salvageValue' then to_jsonb(a.salvage_value) when 'usefulLifeMonths' then to_jsonb(a.useful_life_months)
        when 'depreciationMethod' then to_jsonb(a.depreciation_method) when 'decliningRate' then to_jsonb(a.declining_rate)
        when 'currency' then to_jsonb(a.currency) when 'assetAccountId' then to_jsonb(a.asset_account_id)
        when 'accumulatedDepreciationAccountId' then to_jsonb(a.accumulated_depreciation_account_id)
        when 'depreciationExpenseAccountId' then to_jsonb(a.depreciation_expense_account_id)
        when 'isActive' then to_jsonb(a.is_active) when 'notes' then to_jsonb(a.notes) else 'null'::jsonb end;
      r:=jsonb_set(r,array[k],coalesce(oldv,'null'::jsonb),true);
    else
      r:=r-k;
    end if;
  end loop;
  return r;
end;
$$;

create or replace function public.erp_r9_save_fixed_asset(p_company_id uuid,p_asset jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_guarded jsonb;
begin
  v_guarded:=public.erp_r9_guard_fixed_asset_payload(p_company_id,p_asset);
  return public.erp_save_fixed_asset(p_company_id,v_guarded);
end;
$$;

-- ----------------------------- cash/expenses -------------------------------
create or replace function public.erp_r9_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_guarded jsonb; v_id text:=coalesce(p_account->>'id','');
begin
  select data into v_old from public.erp_cash_accounts where company_id=p_company_id and id=v_id and not is_deleted;
  if v_old is null then perform public.erp_r9_require_field_edit(p_company_id,'cashbox','name','accounting.create');
  else
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then raise exception 'permission_denied:accounting.update' using errcode='42501'; end if;
  end if;
  v_guarded:=public.erp_r9_guard_writable_json(p_company_id,'cashbox',coalesce(v_old,'{}'::jsonb),p_account);
  perform public.erp_save_cloud_cash_account(p_company_id,v_guarded);
end;
$$;

create or replace function public.erp_r9_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_guarded jsonb; v_id text:=coalesce(p_transaction->>'id','');
begin
  select data into v_old from public.erp_cash_transactions where company_id=p_company_id and id=v_id and not is_deleted;
  if p_replace then
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then raise exception 'permission_denied:accounting.update' using errcode='42501'; end if;
  else
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then raise exception 'permission_denied:accounting.create' using errcode='42501'; end if;
  end if;
  v_guarded:=public.erp_r9_guard_writable_json(p_company_id,'cashbox',coalesce(v_old,'{}'::jsonb),p_transaction);
  perform public.erp_post_cloud_cash_transaction(p_company_id,v_guarded,p_replace);
end;
$$;

create or replace function public.erp_r9_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','transferFrom','accounting.update');
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','transferTo',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','amount',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','exchangeRate',null);
  perform public.erp_r9_require_field_edit(p_company_id,'cashbox','operationalDate',null);
  if p_notes is not null then perform public.erp_r9_require_field_edit(p_company_id,'cashbox','notes',null); end if;
  perform public.erp_v2300_transfer_cloud_cash(
    p_company_id,p_from_cash_account_id,p_to_cash_account_id,p_source_amount,
    p_target_amount,p_exchange_rate,p_transfer_date,p_notes
  );
end;
$$;

create or replace function public.erp_r9_post_cloud_expense(p_company_id uuid,p_expense jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_guarded jsonb; v_id text:=coalesce(p_expense->>'id','');
begin
  select data into v_old from public.erp_expenses where company_id=p_company_id and id=v_id and not is_deleted;
  if not public.erp_cloud_user_has_permission(p_company_id,case when v_old is null then 'accounting.create' else 'accounting.update' end) then
    raise exception 'permission_denied:accounting_write' using errcode='42501';
  end if;
  v_guarded:=public.erp_r9_guard_writable_json(p_company_id,'expenses',coalesce(v_old,'{}'::jsonb),p_expense);
  return public.erp_post_cloud_expense(p_company_id,v_guarded);
end;
$$;

create or replace function public.erp_r9_cloud_expense_total(p_company_id uuid)
returns numeric language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then raise exception 'permission_denied:accounting.view' using errcode='42501'; end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'expenses','amount',null) then return 0; end if;
  return public.erp_cloud_expense_total(p_company_id);
end;
$$;

create or replace function public.erp_r9_cloud_cash_account_balances(p_company_id uuid)
returns table(cash_account_id text,balance numeric)
language sql stable security definer set search_path=public as $$
  select x.cash_account_id,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','balance','accounting.view') then x.balance else null end
  from public.erp_cloud_cash_account_balances(p_company_id) x;
$$;

create or replace function public.erp_r9_cloud_cash_ledger_reconciliation(p_company_id uuid)
returns table(cash_account_id text,cash_account_name text,currency text,subledger_balance numeric,ledger_balance numeric,difference numeric)
language sql stable security definer set search_path=public as $$
  select x.cash_account_id,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','name','accounting.view') then x.cash_account_name else null end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','currency','accounting.view') then x.currency else null end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','balance','accounting.view') then x.subledger_balance else null end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','ledgerBalance','accounting.view') then x.ledger_balance else null end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','reconciliationDifference','accounting.view') then x.difference else null end
  from public.erp_cloud_cash_ledger_reconciliation(p_company_id) x
  where public.erp_cloud_user_can_view_field(p_company_id,'cashbox','reconciliation','accounting.view');
$$;

create or replace function public.erp_r9_cloud_cash_currency_summary(p_company_id uuid,p_currency text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v jsonb:=public.erp_cloud_cash_currency_summary(p_company_id,p_currency); r jsonb:='{}'::jsonb;
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then raise exception 'permission_denied:accounting.view' using errcode='42501'; end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'cashbox','openingBalance',null) then r:=r||jsonb_build_object('openingBalance',v->'openingBalance'); end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'cashbox','amount',null) then r:=r||jsonb_build_object('receipts',v->'receipts','payments',v->'payments'); end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'cashbox','balance',null) then r:=r||jsonb_build_object('balance',v->'balance'); end if;
  return r;
end;
$$;

-- ----------------------------- ledger writes -------------------------------
create or replace function public.erp_r9_guard_ledger_account_payload(
  p_company_id uuid,p_account jsonb
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  a public.erp_accounts%rowtype;
  r jsonb:=coalesce(p_account,'{}'::jsonb);
  v_id text:=coalesce(p_account->>'id','');
  item text; k text; f text; oldv jsonb; v_exists boolean:=false;
begin
  select * into a from public.erp_accounts where organization_id=p_company_id and account_id=v_id;
  v_exists:=found;
  if v_exists then
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then raise exception 'permission_denied:accounting.update' using errcode='42501'; end if;
  else
    if not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then raise exception 'permission_denied:accounting.create' using errcode='42501'; end if;
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.fields.restrict') then return r; end if;
  foreach item in array array['code=accountCode','name=accountName','type=accountType','parentId=parentAccount','currency=currency','openingBalance=openingBalance','isActive=isActive'] loop
    k:=split_part(item,'=',1); f:=split_part(item,'=',2);
    if public.erp_cloud_user_can_edit_field(p_company_id,'accounting',f,null) then continue; end if;
    if v_exists then
      oldv:=case k when 'code' then to_jsonb(a.code) when 'name' then to_jsonb(a.name)
        when 'type' then to_jsonb(a.account_type) when 'parentId' then to_jsonb(a.parent_account_id)
        when 'currency' then to_jsonb(a.currency) when 'openingBalance' then to_jsonb(a.opening_balance)
        when 'isActive' then to_jsonb(a.is_active) else 'null'::jsonb end;
      r:=jsonb_set(r,array[k],coalesce(oldv,'null'::jsonb),true);
    else r:=r-k; end if;
  end loop;
  return r;
end;
$$;

create or replace function public.erp_r9_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_save_cloud_ledger_account(
    p_company_id,public.erp_r9_guard_ledger_account_payload(p_company_id,p_account),p_require_existing
  );
end;
$$;

create or replace function public.erp_r9_guard_manual_journal_lines(
  p_company_id uuid,p_entry_id text,p_lines jsonb
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  out_lines jsonb:='[]'::jsonb; incoming jsonb; old_line jsonb; line_id text;
  can_lines boolean; can_debit boolean; can_credit boolean;
begin
  can_lines:=public.erp_cloud_user_can_edit_field(p_company_id,'accounting','journalLines',null);
  can_debit:=public.erp_cloud_user_can_edit_field(p_company_id,'accounting','debit',null);
  can_credit:=public.erp_cloud_user_can_edit_field(p_company_id,'accounting','credit',null);
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.fields.restrict') then return coalesce(p_lines,'[]'::jsonb); end if;
  if not can_lines then
    select coalesce(jsonb_agg(data order by created_at),'[]'::jsonb) into out_lines
    from public.erp_journal_lines where company_id=p_company_id and not is_deleted and data->>'entryId'=p_entry_id;
    if out_lines='[]'::jsonb and jsonb_array_length(coalesce(p_lines,'[]'::jsonb))>0 then
      raise exception 'field_permission_denied:accounting.journalLines' using errcode='42501';
    end if;
    return out_lines;
  end if;
  for incoming in select value from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
    line_id:=coalesce(incoming->>'id',''); old_line:=null;
    select data into old_line from public.erp_journal_lines
      where company_id=p_company_id and not is_deleted and data->>'entryId'=p_entry_id
        and data->>'id'=line_id limit 1;
    if not can_debit then incoming:=jsonb_set(incoming,'{debit}',coalesce(old_line->'debit','0'::jsonb),true); end if;
    if not can_credit then incoming:=jsonb_set(incoming,'{credit}',coalesce(old_line->'credit','0'::jsonb),true); end if;
    out_lines:=out_lines||jsonb_build_array(incoming);
  end loop;
  return out_lines;
end;
$$;

create or replace function public.erp_r9_post_cloud_manual_journal(p_company_id uuid,p_entry jsonb,p_lines jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_entry jsonb; v_lines jsonb;
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then raise exception 'permission_denied:accounting.create' using errcode='42501'; end if;
  v_entry:=public.erp_r9_guard_writable_json(p_company_id,'accounting','{}'::jsonb,p_entry);
  v_lines:=public.erp_r9_guard_manual_journal_lines(p_company_id,coalesce(v_entry->>'id',''),p_lines);
  perform public.erp_post_cloud_manual_journal(p_company_id,v_entry,v_lines);
end;
$$;

create or replace function public.erp_r9_update_cloud_manual_journal(p_company_id uuid,p_entry jsonb,p_lines jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_entry jsonb; v_lines jsonb; v_id text:=coalesce(p_entry->>'id','');
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then raise exception 'permission_denied:accounting.update' using errcode='42501'; end if;
  select data into v_old from public.erp_journal_entries where company_id=p_company_id and id=v_id and not is_deleted;
  v_entry:=public.erp_r9_guard_writable_json(p_company_id,'accounting',coalesce(v_old,'{}'::jsonb),p_entry);
  v_lines:=public.erp_r9_guard_manual_journal_lines(p_company_id,v_id,p_lines);
  perform public.erp_update_cloud_manual_journal(p_company_id,v_entry,v_lines);
end;
$$;

-- -------------------------- commercial read wrappers -----------------------
create or replace function public.erp_r9_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'sales',x,'sales.view')
  from public.erp_list_cloud_sales_workflow_orders(p_company_id) x;
$$;
create or replace function public.erp_r9_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'purchases',x,'purchases.view')
  from public.erp_list_cloud_purchase_workflow_orders(p_company_id) x;
$$;
create or replace function public.erp_r9_find_sales_order_by_opportunity(p_company_id uuid,p_opportunity_id text)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'sales',jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'status',o.status,'opportunityId',o.opportunity_id,
    'customerId',o.customer_id,'updatedAt',o.updated_at),'sales.view')
  from public.erp_sales_orders_cloud o
  where o.company_id=p_company_id and o.opportunity_id=p_opportunity_id and not o.is_deleted
    and public.is_active_company_member(p_company_id)
  order by o.updated_at desc limit 2;
$$;
create or replace function public.erp_r9_find_purchase_order_by_opportunity(p_company_id uuid,p_opportunity_id text)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'purchases',jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'status',o.status,'opportunityId',o.opportunity_id,
    'supplierId',o.supplier_id,'updatedAt',o.updated_at),'purchases.view')
  from public.erp_purchase_orders_cloud o
  where o.company_id=p_company_id and o.opportunity_id=p_opportunity_id and not o.is_deleted
    and public.is_active_company_member(p_company_id)
  order by o.updated_at desc limit 2;
$$;

create or replace function public.erp_r9_list_cloud_maintenance_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',to_jsonb(x),'maintenance.view')
  from public.erp_list_cloud_maintenance_orders(p_company_id) x;
$$;
create or replace function public.erp_r9_get_cloud_maintenance_order_lines(p_company_id uuid,p_order_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',to_jsonb(x),'maintenance.view')
  from public.erp_get_cloud_maintenance_order_lines(p_company_id,p_order_id) x;
$$;
create or replace function public.erp_r9_list_cloud_maintenance_eligible_cars(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',to_jsonb(x),'maintenance.view')
  from public.erp_list_cloud_maintenance_eligible_cars(p_company_id) x;
$$;

-- Depreciation is an accounting post and a protected field edit.
create or replace function public.erp_r9_post_fixed_asset_depreciation_at(
  p_company_id uuid,p_asset_id uuid,p_effective_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.post') then
    raise exception 'permission_denied:accounting.post' using errcode='42501';
  end if;
  perform public.erp_r9_require_field_edit(p_company_id,'fixed_assets','depreciationPostingDate',null);
  return public.erp_post_fixed_asset_depreciation_at(p_company_id,p_asset_id,p_effective_at);
end;
$$;

-- Attach the JSON write guard to every master table consumed by the app, not
-- only the first-generation inventory tables.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images','erp_car_warehouse_transfers',
    'erp_warehouse_transfers','erp_warehouse_transfer_items','erp_warehouse_stock',
    'erp_inventory_movements','erp_cash_accounts','erp_cash_transactions','erp_expenses',
    'erp_journal_entries','erp_installments','erp_sales'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop trigger if exists aa_r9_field_write_guard on public.%I',v_table);
      execute format('create trigger aa_r9_field_write_guard before insert or update of data on public.%I for each row execute function public.erp_r9_master_field_write_guard()',v_table);
    end if;
  end loop;
end $$;

-- RLS policies are permissive (OR). Remove every old direct SELECT policy on
-- protected tables and replace it with one restriction-aware policy. RPCs are
-- SECURITY DEFINER and remain authoritative readers. Unrestricted legacy roles
-- retain direct/realtime reads; restricted roles must use the masked RPCs.
do $$
declare v_table text; v_resource text; p record;
begin
  for v_table,v_resource in values
    ('erp_cars','cars'),('erp_car_images','cars'),('erp_customers','customers'),('erp_suppliers','suppliers'),
    ('erp_warehouses','warehouses'),('erp_inventory','inventory'),('erp_inventory_groups','inventory'),
    ('erp_product_images','inventory'),('erp_car_warehouse_transfers','inventory'),('erp_warehouse_transfers','inventory'),
    ('erp_warehouse_transfer_items','inventory'),('erp_warehouse_stock','inventory'),('erp_inventory_movements','inventory'),
    ('erp_cash_accounts','cashbox'),('erp_cash_transactions','cashbox'),('erp_expenses','expenses'),
    ('erp_journal_entries','accounting'),('erp_journal_lines','accounting'),('erp_installments','sales'),('erp_sales','sales'),
    ('erp_fixed_assets','fixed_assets'),('erp_sales_orders_cloud','sales'),('erp_sales_order_items_cloud','sales'),
    ('erp_purchase_orders_cloud','purchases'),('erp_purchase_order_items_cloud','purchases'),
    ('erp_maintenance_orders','maintenance'),('erp_maintenance_parts','maintenance'),('erp_maintenance_payments','maintenance')
  loop
    if to_regclass('public.'||v_table) is null then continue; end if;
    for p in select policyname from pg_policies where schemaname='public' and tablename=v_table and cmd='SELECT' loop
      execute format('drop policy if exists %I on public.%I',p.policyname,v_table);
    end loop;
    if v_table='erp_fixed_assets' then execute 'drop policy if exists erp_fixed_assets_company_access on public.erp_fixed_assets'; end if;
    execute format(
      'create policy %I on public.%I for select to authenticated using ('||
      'public.is_active_company_member(company_id) and not public.erp_cloud_user_has_permission(company_id,%L))',
      left(v_table||'_r9_restricted_select',63),v_table,v_resource||'.fields.restrict'
    );
  end loop;
end $$;

-- Force user-facing writes/reads through guarded wrappers. Internal SQL calls
-- continue to work because they execute as function owners/service role.
revoke execute on function public.erp_save_cloud_ledger_account(uuid,jsonb,boolean) from authenticated;
revoke execute on function public.erp_post_cloud_manual_journal(uuid,jsonb,jsonb) from authenticated;
revoke execute on function public.erp_update_cloud_manual_journal(uuid,jsonb,jsonb) from authenticated;
revoke execute on function public.erp_save_cloud_cash_account(uuid,jsonb) from authenticated;
revoke execute on function public.erp_post_cloud_cash_transaction(uuid,jsonb,boolean) from authenticated;
revoke execute on function public.erp_post_cloud_expense(uuid,jsonb) from authenticated;
revoke execute on function public.erp_save_fixed_asset(uuid,jsonb) from authenticated;
revoke execute on function public.erp_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) from authenticated;
revoke execute on function public.erp_list_cloud_ledger_accounts(uuid) from authenticated;
revoke execute on function public.erp_cloud_cash_account_balances(uuid) from authenticated;
revoke execute on function public.erp_cloud_cash_currency_summary(uuid,text) from authenticated;
revoke execute on function public.erp_cloud_cash_ledger_reconciliation(uuid) from authenticated;
revoke execute on function public.erp_cloud_account_statement(uuid,text,timestamptz,timestamptz) from authenticated;

revoke all on function public.erp_r9_result_field_for_key(text,text) from public,anon;
revoke all on function public.erp_r9_filter_result_json(uuid,text,jsonb,text) from public,anon;
revoke all on function public.erp_r9_require_field_edit(uuid,text,text,text) from public,anon;
revoke all on function public.erp_r9_guard_fixed_asset_payload(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_r9_guard_ledger_account_payload(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_r9_guard_manual_journal_lines(uuid,text,jsonb) from public,anon,authenticated;

grant execute on function public.erp_r9_list_cloud_ledger_accounts(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_list_journal_lines(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_account_statement(uuid,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r9_list_fixed_assets(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_save_fixed_asset(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r9_save_cloud_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r9_post_cloud_cash_transaction(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.erp_r9_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_r9_post_cloud_expense(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_expense_total(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_cash_account_balances(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_cash_ledger_reconciliation(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_cash_currency_summary(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.erp_r9_post_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r9_update_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_sales_workflow_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_purchase_workflow_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_find_sales_order_by_opportunity(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_find_purchase_order_by_opportunity(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_maintenance_orders(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_get_cloud_maintenance_order_lines(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_maintenance_eligible_cars(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
