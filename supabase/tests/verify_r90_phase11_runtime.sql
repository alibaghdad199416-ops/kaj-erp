\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare
  v_def text;
  v_sig text;
  v_legacy text[] := array[
    'public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)',
    'public.erp_r57_commercial_reconciliation(uuid,uuid,text)',
    'public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)',
    'public.erp_r57_maintenance_cost_reconciliation(uuid,uuid)',
    'public.erp_r57_maintenance_material_issue_state(uuid,uuid)',
    'public.erp_r64_get_maintenance_order_snapshot(uuid,uuid)',
    'public.erp_r88_list_maintenance_payments(uuid,uuid)',
    'public.erp_r88_vehicle_service_card(uuid,text)',
    'public.erp_r42_list_cash_accounts(uuid)',
    'public.erp_r22_cloud_cash_account_balances(uuid)',
    'public.erp_r22_cloud_cash_ledger_reconciliation(uuid)',
    'public.erp_r42_save_cash_account(uuid,jsonb)',
    'public.erp_delete_cloud_cash_account(uuid,text)',
    'public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)',
    'public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)',
    'public.erp_delete_cloud_cash_transaction(uuid,text)',
    'public.erp_delete_cloud_cash_transfer(uuid,text)'
  ];
  v_secure text[] := array[
    'public.erp_r89_get_commercial_order_snapshot(uuid,uuid,boolean)',
    'public.erp_r89_get_maintenance_order_snapshot(uuid,uuid)',
    'public.erp_r89_maintenance_cost_reconciliation(uuid,uuid)',
    'public.erp_r89_maintenance_material_issue_state(uuid,uuid)',
    'public.erp_r90_list_maintenance_payments(uuid,uuid)',
    'public.erp_r90_vehicle_service_card(uuid,text)',
    'public.erp_r90_list_cash_accounts(uuid)',
    'public.erp_r90_cash_account_balances(uuid)',
    'public.erp_r90_cash_ledger_reconciliation(uuid)',
    'public.erp_r90_save_cash_account(uuid,jsonb)',
    'public.erp_r90_delete_cash_account(uuid,text)',
    'public.erp_r90_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)',
    'public.erp_r90_post_cash_transaction(uuid,jsonb,boolean)',
    'public.erp_r90_delete_cash_transaction(uuid,text)',
    'public.erp_r90_delete_cash_transfer(uuid,text)'
  ];
begin
  -- Required R90 browser-facing functions must be installed.
  foreach v_sig in array v_secure loop
    if to_regprocedure(v_sig) is null then
      raise exception 'r90_secure_endpoint_missing:%',v_sig;
    end if;
    if not has_function_privilege('authenticated',v_sig,'execute') then
      raise exception 'r90_secure_endpoint_not_executable_by_authenticated:%',v_sig;
    end if;
  end loop;

  -- Legacy unfiltered/internal endpoints must not be directly executable by authenticated.
  foreach v_sig in array v_legacy loop
    if to_regprocedure(v_sig) is null then
      raise exception 'r90_expected_legacy_endpoint_missing:%',v_sig;
    end if;
    if has_function_privilege('authenticated',v_sig,'execute') then
      raise exception 'r90_legacy_endpoint_bypass_still_exposed:%',v_sig;
    end if;
  end loop;

  -- Commercial payment data must honor cashbox field permissions as well.
  select pg_get_functiondef(
    'public.erp_r89_filter_commercial_detail_row(uuid,text,jsonb,text)'::regprocedure
  ) into v_def;
  if v_def not like '%cashAccountName%'
     or v_def not like '%cashAccountId%'
     or v_def not like '%cashTransactionId%'
     or v_def not like '%cashAccountCurrency%'
     or v_def not like '%''cashbox''%'
     or v_def not like '%''name''%'
     or v_def not like '%''cashAccount''%'
     or v_def not like '%''reference''%'
     or v_def not like '%''currency''%' then
    raise exception 'r90_commercial_cross_cashbox_field_filter_incomplete';
  end if;

  -- Maintenance payment data must be filtered before browser return.
  select pg_get_functiondef(
    'public.erp_r90_filter_maintenance_payment(uuid,jsonb)'::regprocedure
  ) into v_def;
  if v_def not like '%cashboxName%'
     or v_def not like '%cashboxId%'
     or v_def not like '%cashTransactionId%'
     or v_def not like '%journalEntryId%'
     or v_def not like '%erp_cloud_user_can_view_field%' then
    raise exception 'r90_maintenance_payment_filter_incomplete';
  end if;

  -- Vehicle card must strip linked material/invoice/payment/detail/schedule data independently.
  select pg_get_functiondef(
    'public.erp_r90_vehicle_service_card(uuid,text)'::regprocedure
  ) into v_def;
  if v_def not like '%maintenanceHistory%'
     or v_def not like '%materialIssues%'
     or v_def not like '%invoiceReferences%'
     or v_def not like '%paymentReferences%'
     or v_def not like '%customDetails%'
     or v_def not like '%maintenanceSchedules%'
     or v_def not like '%stockIssue%'
     or v_def not like '%maintenanceHistoryDetails%'
     or v_def not like '%maintenanceSchedule%' then
    raise exception 'r90_vehicle_service_card_filter_incomplete';
  end if;

  -- Cashbox account definitions, balances and reconciliation are independently filtered.
  select pg_get_functiondef(
    'public.erp_r90_filter_cashbox_account(uuid,jsonb)'::regprocedure
  ) into v_def;
  if v_def not like '%openingBalance%'
     or v_def not like '%ledgerAccount%'
     or v_def not like '%linkedCashAccount%'
     or v_def not like '%auditMetadata%'
     or v_def not like '%erp_cloud_user_can_view_field%' then
    raise exception 'r90_cashbox_account_field_filter_incomplete';
  end if;
  select pg_get_functiondef(
    'public.erp_r90_cash_account_balances(uuid)'::regprocedure
  ) into v_def;
  if v_def not like '%''cashbox''%'
     or v_def not like '%''balance''%'
     or v_def not like '%erp_cloud_user_can_view_field%' then
    raise exception 'r90_cashbox_balance_field_filter_incomplete';
  end if;
  select pg_get_functiondef(
    'public.erp_r90_cash_ledger_reconciliation(uuid)'::regprocedure
  ) into v_def;
  if v_def not like '%reconciliationDifference%'
     or v_def not like '%ledgerBalance%'
     or v_def not like '%erp_cloud_user_can_view_field%' then
    raise exception 'r90_cashbox_reconciliation_field_filter_incomplete';
  end if;

  -- Cashbox account definition and transfer mutations require granular actions.
  select pg_get_functiondef('public.erp_r90_save_cash_account(uuid,jsonb)'::regprocedure) into v_def;
  if v_def not like '%erp_r88_action_allowed%'
     or v_def not like '%account.edit%'
     or v_def not like '%account.create%' then
    raise exception 'r90_cashbox_save_action_guard_incomplete';
  end if;
  select pg_get_functiondef('public.erp_r90_delete_cash_account(uuid,text)'::regprocedure) into v_def;
  if v_def not like '%erp_r88_action_allowed%'
     or v_def not like '%account.delete%' then
    raise exception 'r90_cashbox_delete_action_guard_incomplete';
  end if;
  select pg_get_functiondef(
    'public.erp_r90_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_r88_action_allowed%'
     or v_def not like '%''transfer''%' then
    raise exception 'r90_cashbox_transfer_action_guard_incomplete';
  end if;

  -- Cashbox transaction edit/delete must be granular at the server boundary.
  select pg_get_functiondef(
    'public.erp_r90_post_cash_transaction(uuid,jsonb,boolean)'::regprocedure
  ) into v_def;
  if v_def not like '%transaction.edit%'
     or v_def not like '%erp_r88_action_allowed%'
     or v_def not like '%erp_r22_post_cloud_cash_transaction%' then
    raise exception 'r90_cash_transaction_edit_guard_incomplete';
  end if;
  select pg_get_functiondef(
    'public.erp_r90_delete_cash_transaction(uuid,text)'::regprocedure
  ) into v_def;
  if v_def not like '%transaction.delete%'
     or v_def not like '%erp_r88_action_allowed%'
     or v_def not like '%erp_delete_cloud_cash_transaction%' then
    raise exception 'r90_cash_transaction_delete_guard_incomplete';
  end if;
  select pg_get_functiondef(
    'public.erp_r90_delete_cash_transfer(uuid,text)'::regprocedure
  ) into v_def;
  if v_def not like '%transfer.delete%'
     or v_def not like '%erp_r88_action_allowed%'
     or v_def not like '%erp_delete_cloud_cash_transfer%' then
    raise exception 'r90_cash_transfer_delete_guard_incomplete';
  end if;

  -- Raw transfer/link storage is internal-only: no Data API bypass.
  if has_table_privilege('authenticated','public.erp_cash_transfers','select')
     or has_table_privilege('authenticated','public.erp_cash_transfers','insert')
     or has_table_privilege('authenticated','public.erp_cash_transfers','update')
     or has_table_privilege('authenticated','public.erp_cash_transfers','delete') then
    raise exception 'r90_cash_transfer_direct_authenticated_access_exposed';
  end if;
  if has_table_privilege('authenticated','public.erp_cash_account_links','select')
     or has_table_privilege('authenticated','public.erp_cash_account_links','insert')
     or has_table_privilege('authenticated','public.erp_cash_account_links','update')
     or has_table_privilege('authenticated','public.erp_cash_account_links','delete') then
    raise exception 'r90_cash_link_direct_authenticated_access_exposed';
  end if;

  -- Tables that retain legacy Realtime SELECT must have a RESTRICTIVE policy
  -- that hides raw rows whenever field restrictions are enabled.
  foreach v_sig in array array[
    'erp_cash_accounts:erp_cash_accounts_r90_field_scope:cashbox.fields.restrict',
    'erp_cash_transactions:erp_cash_transactions_r90_field_scope:cashbox.fields.restrict',
    'erp_maintenance_orders:erp_maintenance_orders_r90_field_scope:maintenance.fields.restrict',
    'erp_maintenance_parts:erp_maintenance_parts_r90_field_scope:maintenance.fields.restrict',
    'erp_maintenance_payments:erp_maintenance_payments_r90_field_scope:maintenance.fields.restrict',
    'erp_sales_orders_cloud:erp_sales_orders_cloud_r90_field_scope:sales.fields.restrict',
    'erp_sales_order_items_cloud:erp_sales_order_items_cloud_r90_field_scope:sales.fields.restrict',
    'erp_purchase_orders_cloud:erp_purchase_orders_cloud_r90_field_scope:purchases.fields.restrict',
    'erp_purchase_order_items_cloud:erp_purchase_order_items_cloud_r90_field_scope:purchases.fields.restrict'
  ] loop
    if not exists(
      select 1 from pg_policies p
      where p.schemaname='public'
        and p.tablename=split_part(v_sig,':',1)
        and p.policyname=split_part(v_sig,':',2)
        and lower(p.permissive)='restrictive'
        and coalesce(p.qual,'') like '%'||split_part(v_sig,':',3)||'%'
    ) then
      raise exception 'r90_restrictive_field_policy_missing:%',v_sig;
    end if;
  end loop;

  if not exists(
    select 1 from pg_policies p
    where p.schemaname='public'
      and p.tablename='erp_commercial_workflow_documents'
      and p.policyname='erp_commercial_workflow_documents_r90_field_scope'
      and lower(p.permissive)='restrictive'
      and coalesce(p.qual,'') like '%sales.fields.restrict%'
      and coalesce(p.qual,'') like '%purchases.fields.restrict%'
  ) then
    raise exception 'r90_commercial_document_direct_field_policy_missing';
  end if;

  -- Schedule/history direct DML remains closed from R89.
  if has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','select')
     or has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','insert')
     or has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','update')
     or has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','delete') then
    raise exception 'r90_schedule_direct_authenticated_dml_exposed';
  end if;
  if has_table_privilege('authenticated','public.erp_maintenance_history_details','select')
     or has_table_privilege('authenticated','public.erp_maintenance_history_details','insert')
     or has_table_privilege('authenticated','public.erp_maintenance_history_details','update')
     or has_table_privilege('authenticated','public.erp_maintenance_history_details','delete') then
    raise exception 'r90_history_direct_authenticated_dml_exposed';
  end if;
end $$;

rollback;
select 'R90 Phase 11 LOCAL PostgreSQL runtime PASS' as result;
