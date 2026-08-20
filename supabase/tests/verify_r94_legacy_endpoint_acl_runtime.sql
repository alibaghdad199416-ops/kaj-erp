\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare
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
  foreach v_sig in array v_legacy loop
    if to_regprocedure(v_sig) is null then
      raise exception 'r94_expected_legacy_endpoint_missing:%', v_sig;
    end if;
    -- has_function_privilege includes privileges inherited from PUBLIC, so these
    -- assertions prove the R90 bypass is closed rather than merely revoking a
    -- direct role grant.
    if has_function_privilege('authenticated', v_sig, 'execute') then
      raise exception 'r94_authenticated_legacy_execute_exposed:%', v_sig;
    end if;
    if has_function_privilege('anon', v_sig, 'execute') then
      raise exception 'r94_anon_legacy_execute_exposed:%', v_sig;
    end if;
    if not has_function_privilege('service_role', v_sig, 'execute') then
      raise exception 'r94_internal_service_role_execute_missing:%', v_sig;
    end if;
  end loop;

  -- Closing the low-level engines must not remove the governed browser API.
  foreach v_sig in array v_secure loop
    if to_regprocedure(v_sig) is null then
      raise exception 'r94_secure_endpoint_missing:%', v_sig;
    end if;
    if not has_function_privilege('authenticated', v_sig, 'execute') then
      raise exception 'r94_secure_endpoint_not_executable_by_authenticated:%', v_sig;
    end if;
  end loop;
end $$;

rollback;
select 'R94 legacy endpoint ACL LOCAL PostgreSQL runtime PASS' as result;
