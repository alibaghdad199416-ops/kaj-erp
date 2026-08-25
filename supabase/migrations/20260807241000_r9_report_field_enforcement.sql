-- Quality Line ERP R9: report/accounting read permissions must be enforced at
-- the database boundary, not only by hiding cards in Flutter.
begin;

create or replace function public.erp_r9_cloud_trial_balance(p_company_id uuid,p_currency text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v jsonb; r jsonb:='{}'::jsonb;
begin
  if not public.erp_cloud_user_can_view_field(p_company_id,'accounting','trialBalance','accounting.view') then
    raise exception 'field_permission_denied:accounting.trialBalance' using errcode='42501';
  end if;
  v:=public.erp_cloud_trial_balance(p_company_id,p_currency);
  if public.erp_cloud_user_can_view_field(p_company_id,'accounting','debit',null) then
    r:=r||jsonb_build_object('debit',v->'debit','movementDebit',v->'movementDebit');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'accounting','credit',null) then
    r:=r||jsonb_build_object('credit',v->'credit','movementCredit',v->'movementCredit');
  end if;
  if public.erp_cloud_user_can_view_field(p_company_id,'accounting','balances',null) then
    r:=r||jsonb_build_object('difference',v->'difference');
  end if;
  return r;
end;
$$;

create or replace function public.erp_r9_cloud_account_balance_before(
  p_company_id uuid,p_account_id text,p_before_date timestamptz
) returns numeric language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_can_view_field(p_company_id,'accounting','balances','accounting.view') then
    raise exception 'field_permission_denied:accounting.balances' using errcode='42501';
  end if;
  return public.erp_cloud_account_balance_before(p_company_id,p_account_id,p_before_date);
end;
$$;

create or replace function public.erp_r9_cloud_receivables_payables(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_can_view_field(p_company_id,'accounting','balances','accounting.view')
     or not public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables','reports.view') then
    raise exception 'field_permission_denied:reports.receivablesPayables' using errcode='42501';
  end if;
  return public.erp_cloud_receivables_payables(p_company_id);
end;
$$;

create or replace function public.erp_r9_cloud_partner_subledger_details_v2(
  p_company_id uuid,p_kind text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'accounting',to_jsonb(x),'accounting.view')
  from public.erp_cloud_partner_subledger_details_v2(p_company_id,p_kind) x
  where public.erp_cloud_user_can_view_field(p_company_id,'accounting','balances',null)
    and public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables','reports.view');
$$;

create or replace function public.erp_r9_cloud_partner_subledger_documents(
  p_company_id uuid,p_kind text,p_party_id text,p_currency text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'accounting',to_jsonb(x),'accounting.view')
  from public.erp_cloud_partner_subledger_documents(p_company_id,p_kind,p_party_id,p_currency) x
  where public.erp_cloud_user_can_view_field(p_company_id,'accounting','generalLedger',null)
    and public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables','reports.view');
$$;

create or replace function public.erp_r9_cloud_detailed_accounting_report(
  p_company_id uuid,p_report_type text,p_currency text default 'ALL',
  p_branch_id text default null,p_cost_center_id text default null,
  p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
declare v_field text;
begin
  v_field:=case lower(coalesce(p_report_type,''))
    when 'trialbalance' then 'trialBalance'
    when 'generalledger' then 'generalLedger'
    when 'journalledger' then 'generalLedger'
    else 'generalLedger' end;
  if not public.erp_cloud_user_can_view_field(p_company_id,'accounting',v_field,'accounting.view') then
    raise exception 'field_permission_denied:accounting.%',v_field using errcode='42501';
  end if;
  return query
    select public.erp_r9_filter_result_json(p_company_id,'accounting',x,null)
    from public.erp_cloud_detailed_accounting_report(
      p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
    ) x;
end;
$$;

create or replace function public.erp_r9_cloud_cash_flow_hierarchy(
  p_company_id uuid,p_currency text default 'ALL',p_branch_id text default null,
  p_cost_center_id text default null,p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_can_view_field(p_company_id,'accounting','cashFlow','accounting.view')
     or not public.erp_cloud_user_can_view_field(p_company_id,'reports','cashIn','reports.view')
     or not public.erp_cloud_user_can_view_field(p_company_id,'reports','cashOut','reports.view') then
    raise exception 'field_permission_denied:accounting.cashFlow' using errcode='42501';
  end if;
  return query select x from public.erp_cloud_cash_flow_hierarchy(
    p_company_id,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) x;
end;
$$;

create or replace function public.erp_r9_cloud_reports_summary(
  p_company_id uuid,p_start_date date default null,p_end_date date default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v jsonb; r jsonb:='{}'::jsonb; points jsonb:='[]'::jsonb;
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.view') then
    raise exception 'permission_denied:reports.view' using errcode='42501';
  end if;
  v:=public.erp_cloud_reports_summary(p_company_id,p_start_date,p_end_date);
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.fields.restrict') then return v; end if;

  if public.erp_cloud_user_can_view_field(p_company_id,'reports','summaryCards',null) then
    r:=r||jsonb_build_object(
      'totalCars',v->'totalCars','availableCars',v->'availableCars','reservedCars',v->'reservedCars','soldCars',v->'soldCars',
      'totalCustomers',v->'totalCustomers','totalSuppliers',v->'totalSuppliers','totalInventoryItems',v->'totalInventoryItems',
      'activeReservations',v->'activeReservations','overdueInstallments',v->'overdueInstallments'
    );
    if public.erp_cloud_user_can_view_field(p_company_id,'sales','total','sales.view') then
      r:=r||jsonb_build_object('totalSales',v->'totalSales');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'sales','payments','sales.view') then
      r:=r||jsonb_build_object('totalPaidSales',v->'totalPaidSales');
      if public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables',null) then
        r:=r||jsonb_build_object('totalReceivables',v->'totalReceivables');
      end if;
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'purchases','total','purchases.view') then
      r:=r||jsonb_build_object('totalPurchases',v->'totalPurchases');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'purchases','payments','purchases.view')
       and public.erp_cloud_user_can_view_field(p_company_id,'reports','receivablesPayables',null) then
      r:=r||jsonb_build_object('totalPurchaseDebt',v->'totalPurchaseDebt');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'expenses','amount','accounting.view') then
      r:=r||jsonb_build_object('totalExpenses',v->'totalExpenses');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'reports','inventoryValue',null) then
      r:=r||jsonb_build_object('inventoryValue',v->'inventoryValue');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'reports','cashBalances',null)
       and public.erp_cloud_user_can_view_field(p_company_id,'cashbox','balance','accounting.view') then
      r:=r||jsonb_build_object('cashBalanceUsd',v->'cashBalanceUsd','cashBalanceIqd',v->'cashBalanceIqd');
    end if;
    if public.erp_cloud_user_can_view_field(p_company_id,'reports','netProfit',null) then
      r:=r||jsonb_build_object('netProfit',v->'netProfit');
    end if;
  end if;

  if public.erp_cloud_user_can_view_field(p_company_id,'reports','monthlyTrend',null) then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'label',p->'label',
      'sales',case when public.erp_cloud_user_can_view_field(p_company_id,'sales','total','sales.view') then p->'sales' end,
      'expenses',case when public.erp_cloud_user_can_view_field(p_company_id,'expenses','amount','accounting.view') then p->'expenses' end,
      'purchases',case when public.erp_cloud_user_can_view_field(p_company_id,'purchases','total','purchases.view') then p->'purchases' end
    ))),'[]'::jsonb) into points
    from jsonb_array_elements(coalesce(v->'monthlyPoints','[]'::jsonb)) p;
  end if;
  return r||jsonb_build_object('monthlyPoints',points);
end;
$$;

create or replace function public.erp_r9_can_view_report_module(
  p_company_id uuid,p_module text
) returns boolean language plpgsql stable security definer set search_path=public as $$
declare m text:=lower(trim(coalesce(p_module,'overview'))); p text;
begin
  p:=case m
    when 'cars' then 'cars.view'
    when 'products' then 'inventory.view'
    when 'inventory' then 'inventory.view'
    when 'warehouses' then 'warehouses.view'
    when 'customers' then 'customers.view'
    when 'suppliers' then 'suppliers.view'
    when 'sales' then 'sales.view'
    when 'purchases' then 'purchases.view'
    when 'maintenance' then 'maintenance.view'
    when 'customer_service' then 'customer_service.view'
    when 'opportunities' then 'customer_service.view'
    when 'payments' then 'accounting.view'
    when 'accounting' then 'accounting.view'
    when 'finance' then 'accounting.view'
    when 'partners' then 'accounting.view'
    when 'operations' then 'reports.view'
    when 'overview' then 'reports.view'
    else 'reports.view' end;
  return public.erp_cloud_user_has_permission(p_company_id,'reports.view')
     and public.erp_cloud_user_has_permission(p_company_id,p);
end;
$$;

create or replace function public.erp_r9_cloud_contextual_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'reports','contextualDetails','reports.view') then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  return public.erp_cloud_contextual_report(p_company_id,p_module,p_start_date,p_end_date);
end;
$$;
create or replace function public.erp_r9_cloud_model_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'reports','contextualDetails','reports.view') then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  return public.erp_cloud_model_report(p_company_id,p_module,p_start_date,p_end_date);
end;
$$;
create or replace function public.erp_r9_cloud_customer_service_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'reports','contextualDetails','reports.view') then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  return query select x from public.erp_cloud_customer_service_report(p_company_id,p_module,p_start_date,p_end_date) x;
end;
$$;
create or replace function public.erp_r9_cloud_report_audit(
  p_company_id uuid,p_module text,p_start_date timestamptz default null,p_end_date timestamptz default null,p_limit int default 10000
) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'audit.view')
     or not public.erp_cloud_user_can_view_field(p_company_id,'reports','auditDetails','reports.view') then
    raise exception 'permission_denied:audit.view' using errcode='42501';
  end if;
  return public.erp_cloud_report_audit(p_company_id,p_module,p_start_date,p_end_date,p_limit);
end;
$$;

-- Client code is migrated to the guarded endpoints below. Prevent an
-- authenticated caller from invoking the unfiltered report functions directly.
revoke execute on function public.erp_cloud_trial_balance(uuid,text) from authenticated;
revoke execute on function public.erp_cloud_account_balance_before(uuid,text,timestamptz) from authenticated;
revoke execute on function public.erp_cloud_receivables_payables(uuid) from authenticated;
revoke execute on function public.erp_cloud_partner_subledger_details_v2(uuid,text) from authenticated;
revoke execute on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) from authenticated;
revoke execute on function public.erp_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) from authenticated;
revoke execute on function public.erp_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz) from authenticated;
revoke execute on function public.erp_cloud_reports_summary(uuid,date,date) from authenticated;
revoke execute on function public.erp_cloud_contextual_report(uuid,text,date,date) from authenticated;
revoke execute on function public.erp_cloud_model_report(uuid,text,date,date) from authenticated;
revoke execute on function public.erp_cloud_customer_service_report(uuid,text,date,date) from authenticated;
revoke execute on function public.erp_cloud_report_audit(uuid,text,timestamptz,timestamptz,integer) from authenticated;

revoke all on function public.erp_r9_can_view_report_module(uuid,text) from public,anon,authenticated;
grant execute on function public.erp_r9_cloud_trial_balance(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_account_balance_before(uuid,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_receivables_payables(uuid) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_partner_subledger_details_v2(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_partner_subledger_documents(uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_reports_summary(uuid,date,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_contextual_report(uuid,text,date,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_model_report(uuid,text,date,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_customer_service_report(uuid,text,date,date) to authenticated,service_role;
grant execute on function public.erp_r9_cloud_report_audit(uuid,text,timestamptz,timestamptz,integer) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
