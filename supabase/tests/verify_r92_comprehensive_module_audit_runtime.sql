\set ON_ERROR_STOP on
begin;

do $$
declare
  v_def text;
  v_policy_count integer;
begin
  if to_regprocedure('public.erp_r92_list_journal_entries(uuid)') is null then
    raise exception 'r92_journal_balance_reader_missing';
  end if;
  select pg_get_functiondef('public.erp_r92_list_journal_entries(uuid)'::regprocedure) into v_def;
  if v_def not like '%erp_r9_list_cloud_master_records%'
     or v_def not like '%balanceDifference%'
     or v_def not like '%isBalanced%'
     or v_def not like '%accounting%debit%'
     or v_def not like '%accounting%credit%'
     or v_def not like '%accounting%balances%' then
    raise exception 'r92_journal_balance_contract_incomplete';
  end if;
  if not has_function_privilege('authenticated','public.erp_r92_list_journal_entries(uuid)','execute') then
    raise exception 'r92_journal_reader_not_exposed';
  end if;
  if has_function_privilege('anon','public.erp_r92_list_journal_entries(uuid)','execute') then
    raise exception 'r92_journal_reader_exposed_to_anon';
  end if;

  if has_function_privilege('authenticated','public.erp_r49_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text)','execute') then
    raise exception 'r92_direct_inventory_receive_exposed';
  end if;
  if has_function_privilege('authenticated','public.erp_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text)','execute') then
    raise exception 'r92_legacy_inventory_receive_exposed';
  end if;
  if has_function_privilege('authenticated','public.erp_sell_inventory_stock(uuid,text,text,integer,numeric,text,text)','execute') then
    raise exception 'r92_direct_inventory_sale_exposed';
  end if;

  if not has_function_privilege('authenticated','public.erp_r92_delete_cloud_sale(uuid,text)','execute')
     or not has_function_privilege('authenticated','public.erp_r92_delete_cloud_purchase(uuid,text)','execute') then
    raise exception 'r92_exact_commercial_delete_wrappers_not_exposed';
  end if;
  if has_function_privilege('authenticated','public.erp_delete_cloud_sale(uuid,text)','execute')
     or has_function_privilege('authenticated','public.erp_delete_cloud_purchase(uuid,text)','execute') then
    raise exception 'r92_legacy_commercial_delete_exposed';
  end if;

  if not has_function_privilege('authenticated','public.erp_r92_list_workflow_cash_accounts(uuid,text)','execute')
     or not has_function_privilege('authenticated','public.erp_r92_list_workflow_warehouses(uuid,text)','execute')
     or not has_function_privilege('authenticated','public.erp_r92_list_workflow_settlement_accounts(uuid,text)','execute')
     or not has_function_privilege('authenticated','public.erp_r92_get_commercial_order_allocation_context(uuid,uuid,text)','execute') then
    raise exception 'r92_filtered_workflow_selectors_not_exposed';
  end if;
  if has_function_privilege('authenticated','public.erp_r49_list_cloud_active_cash_accounts(uuid)','execute')
     or has_function_privilege('authenticated','public.erp_r49_list_cloud_active_warehouses(uuid)','execute')
     or has_function_privilege('authenticated','public.erp_list_cloud_settlement_accounts(uuid)','execute')
     or has_function_privilege('authenticated','public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text)','execute') then
    raise exception 'r92_unfiltered_workflow_selector_exposed';
  end if;

  select count(*) into v_policy_count
  from pg_policies
  where schemaname='public'
    and policyname in (
      'erp_r92_cost_centers_select_guard',
      'erp_r92_accounting_projects_select_guard',
      'erp_r92_fiscal_years_select_guard',
      'erp_r92_fiscal_periods_select_guard'
    )
    and permissive='RESTRICTIVE';
  if v_policy_count <> 4 then
    raise exception 'r92_professional_accounting_restrictive_rls_missing:%',v_policy_count;
  end if;

  if not has_function_privilege('authenticated','public.erp_r92_list_professional_accounting_records(uuid,text,text)','execute')
     or not has_function_privilege('authenticated','public.erp_r92_list_accounting_branches(uuid)','execute') then
    raise exception 'r92_professional_accounting_rpc_not_exposed';
  end if;

  if has_function_privilege('authenticated','public.erp_sync_accounting_master_data(uuid,jsonb,jsonb,jsonb)','execute')
     or has_function_privilege('authenticated','public.erp_ensure_fx_clearing_account(uuid,text)','execute')
     or has_function_privilege('authenticated','public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)','execute')
     or has_function_privilege('authenticated','public.erp_apply_cloud_workflow_invoice_payment(uuid,uuid,text,jsonb)','execute')
     or has_function_privilege('authenticated','public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb)','execute')
     or has_function_privilege('authenticated','public.erp_transfer_cloud_cash_v5(uuid,text,text,numeric,numeric,numeric,timestamptz,text)','execute') then
    raise exception 'r92_internal_accounting_or_payment_engine_exposed';
  end if;
end $$;

rollback;
select 'R92 comprehensive module audit LOCAL PostgreSQL runtime PASS' as result;
