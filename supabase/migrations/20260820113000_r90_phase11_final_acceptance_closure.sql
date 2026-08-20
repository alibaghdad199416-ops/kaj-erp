-- Quality Line ERP / KAJ ERP R90
-- Phase 11 final acceptance closure.
-- Forward-only hardening for data-field boundaries, legacy RPC bypasses,
-- cashbox read/action permissions, and cross-resource payment/history fields.
begin;

-- ---------------------------------------------------------------------------
-- 1. Commercial details: keep R89 filtering authoritative and also enforce
--    cashbox field restrictions for payment-linked cashbox metadata.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r89_filter_commercial_detail_row(
  p_company_id uuid,p_module text,p_payload jsonb,p_kind text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
  v_module text:=lower(btrim(coalesce(p_module,'')));
  v_kind text:=lower(btrim(coalesce(p_kind,'')));
  v_allowed boolean;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    if v_item.key in ('rawData','raw_data','recordMeta','invoiceRawData','payload','invoicePayload','details','allocations','items','lines') then
      continue;
    end if;
    if v_item.key='id' then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
      continue;
    end if;

    v_field:=public.erp_r89_commercial_detail_field_for_key(v_module,v_item.key,v_kind);
    v_allowed:=v_field is not null and public.erp_cloud_user_can_view_field(
      p_company_id,v_module,v_field,null
    );

    if v_kind='payment' and v_item.key in ('cashAccountName') then
      v_allowed:=v_allowed and public.erp_cloud_user_can_view_field(
        p_company_id,'cashbox','name',null
      );
    elsif v_kind='payment' and v_item.key in ('cashAccountId') then
      v_allowed:=v_allowed and public.erp_cloud_user_can_view_field(
        p_company_id,'cashbox','cashAccount',null
      );
    elsif v_kind='payment' and v_item.key in ('cashTransactionId') then
      v_allowed:=v_allowed and public.erp_cloud_user_can_view_field(
        p_company_id,'cashbox','reference',null
      );
    elsif v_kind='payment' and v_item.key in ('cashAccountCurrency') then
      v_allowed:=v_allowed and public.erp_cloud_user_can_view_field(
        p_company_id,'cashbox','currency',null
      );
    end if;

    if v_allowed then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

-- Legacy unfiltered commercial read RPCs are internal implementation details.
revoke execute on function public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)
  from authenticated;
revoke execute on function public.erp_r57_commercial_reconciliation(uuid,uuid,text)
  from authenticated;
revoke execute on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  from authenticated;
grant execute on function public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)
  to service_role;
grant execute on function public.erp_r57_commercial_reconciliation(uuid,uuid,text)
  to service_role;
grant execute on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  to service_role;

-- ---------------------------------------------------------------------------
-- 2. Maintenance payment/detail boundary.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r90_filter_maintenance_payment(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_allowed boolean;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_allowed:=case
      when v_item.key='id' then true
      when v_item.key in ('paymentReference','status','amount','invoiceAmount') then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','payments',null)
      when v_item.key in ('currency','invoiceCurrency') then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','currencyCode',null)
      when v_item.key in ('exchangeRate','exchangeDifference') then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','exchangeRate',null)
      when v_item.key='paymentDate' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','operationalDate',null)
      when v_item.key in ('userId','userName') then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','createdBy',null)
      when v_item.key='relatedInvoice' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','invoice',null)
      when v_item.key='relatedOrder' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','orderNumber',null)
      when v_item.key='notes' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','notes',null)
      when v_item.key='journalEntryId' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','accounting',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'cashbox','journalEntryId',null)
      when v_item.key='cashboxName' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','payments',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'cashbox','name',null)
      when v_item.key='cashboxId' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','payments',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'cashbox','cashAccount',null)
      when v_item.key='cashTransactionId' then
        public.erp_cloud_user_can_view_field(p_company_id,'maintenance','payments',null)
        and public.erp_cloud_user_can_view_field(p_company_id,'cashbox','reference',null)
      else false end;
    if v_allowed then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r90_list_maintenance_payments(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r90_filter_maintenance_payment(p_company_id,x)
  from public.erp_r88_list_maintenance_payments(p_company_id,p_order_id) x
$$;

create or replace function public.erp_r90_vehicle_service_card(
  p_company_id uuid,p_car_id text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_card jsonb;
  v_history jsonb:='[]'::jsonb;
  v_row jsonb;
  v_can_history boolean;
  v_can_stock boolean;
  v_can_invoice boolean;
  v_can_payments boolean;
  v_can_details boolean;
  v_can_schedule boolean;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'cars.view')
     or not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:vehicle_service_card' using errcode='42501';
  end if;

  v_card:=public.erp_r88_vehicle_service_card(p_company_id,p_car_id);
  v_can_history:=public.erp_cloud_user_can_view_field(
    p_company_id,'cars','maintenanceHistory','cars.view'
  );
  v_can_stock:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','stockIssue','maintenance.view'
  );
  v_can_invoice:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','invoice','maintenance.view'
  );
  v_can_payments:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','payments','maintenance.view'
  );
  v_can_details:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','maintenanceHistoryDetails','maintenance.view'
  );
  v_can_schedule:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','maintenanceSchedule','maintenance.view'
  );

  if v_can_history then
    for v_row in select value from jsonb_array_elements(
      coalesce(v_card->'maintenanceHistory','[]'::jsonb)
    ) loop
      if not v_can_stock then v_row:=v_row-'materialIssues'; end if;
      if not v_can_invoice then v_row:=v_row-'invoiceReferences'; end if;
      if not v_can_payments then v_row:=v_row-'paymentReferences'-'payments'; end if;
      if not v_can_details then v_row:=v_row-'customDetails'; end if;
      v_history:=v_history||jsonb_build_array(v_row);
    end loop;
  end if;

  return (v_card-'maintenanceHistory'-'maintenanceSchedules')||jsonb_build_object(
    'maintenanceHistory',case when v_can_history then v_history else '[]'::jsonb end,
    'maintenanceSchedules',case when v_can_schedule
      then coalesce(v_card->'maintenanceSchedules','[]'::jsonb)
      else '[]'::jsonb end,
    'profileVersion','R90'
  );
end;
$$;

-- The filtered R89/R90 endpoints are the only authenticated maintenance detail
-- boundary. Revoke legacy snapshots/reconciliation and the R88 aggregate reads.
revoke execute on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid)
  from authenticated;
revoke execute on function public.erp_r57_maintenance_material_issue_state(uuid,uuid)
  from authenticated;
revoke execute on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid)
  from authenticated;
revoke execute on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  from authenticated;
revoke execute on function public.erp_r88_vehicle_service_card(uuid,text)
  from authenticated;
grant execute on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid) to service_role;
grant execute on function public.erp_r57_maintenance_material_issue_state(uuid,uuid) to service_role;
grant execute on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid) to service_role;
grant execute on function public.erp_r88_list_maintenance_payments(uuid,uuid) to service_role;
grant execute on function public.erp_r88_vehicle_service_card(uuid,text) to service_role;

revoke all on function public.erp_r90_filter_maintenance_payment(uuid,jsonb) from public,anon;
revoke all on function public.erp_r90_list_maintenance_payments(uuid,uuid) from public,anon;
revoke all on function public.erp_r90_vehicle_service_card(uuid,text) from public,anon;
grant execute on function public.erp_r90_filter_maintenance_payment(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r90_list_maintenance_payments(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r90_vehicle_service_card(uuid,text) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3. Cashbox definition/balance/reconciliation server-side field boundary.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r90_filter_cashbox_account(
  p_company_id uuid,p_payload jsonb
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb:=jsonb_build_object('id',coalesce(p_payload->>'id',''));
  v_item record;
  v_field text;
  v_allowed boolean;
  v_epoch text:='1970-01-01T00:00:00Z';
begin
  if p_payload is null then return '{}'::jsonb; end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    if v_item.key='id' then continue; end if;
    v_field:=case v_item.key
      when 'name' then 'name'
      when 'type' then 'type'
      when 'currency' then 'currency'
      when 'openingBalance' then 'openingBalance'
      when 'opening_balance' then 'openingBalance'
      when 'isActive' then 'isActive'
      when 'is_active' then 'isActive'
      when 'accountId' then 'ledgerAccount'
      when 'account_id' then 'ledgerAccount'
      when 'canonical' then 'ledgerAccount'
      when 'ledgerAccountId' then 'ledgerAccount'
      when 'ledgerAccountCode' then 'ledgerAccount'
      when 'ledgerAccountName' then 'ledgerAccount'
      when 'ledgerAccountCurrency' then 'ledgerAccount'
      when 'ledgerAccountType' then 'ledgerAccount'
      when 'linkedCashAccountId' then 'linkedCashAccount'
      when 'linked_cash_account_id' then 'linkedCashAccount'
      when 'createdAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      when '_cloudCreatedAt' then 'auditMetadata'
      when '_cloudUpdatedAt' then 'auditMetadata'
      else null end;
    if v_item.key in ('_cloudVersion','schemaVersion','schema_version') then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
      continue;
    end if;
    v_allowed:=v_field is not null and public.erp_cloud_user_can_view_field(
      p_company_id,'cashbox',v_field,'accounting.view'
    );
    if v_allowed then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    elsif v_item.key in ('createdAt','created_at','updatedAt','updated_at','_cloudCreatedAt','_cloudUpdatedAt') then
      -- Keep the model contract parseable without returning the real audit time.
      v_result:=v_result||jsonb_build_object(v_item.key,v_epoch);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r90_list_cash_accounts(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r90_filter_cashbox_account(p_company_id,x)
  from public.erp_r42_list_cash_accounts(p_company_id) x
  where public.erp_cloud_user_has_permission(p_company_id,'accounting.view')
$$;

create or replace function public.erp_r90_cash_account_balances(p_company_id uuid)
returns table(cash_account_id text,balance numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
    raise exception 'permission_denied:accounting.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(
    p_company_id,'cashbox','balance','accounting.view'
  ) then return; end if;
  return query select b.cash_account_id,b.balance
    from public.erp_r22_cloud_cash_account_balances(p_company_id) b;
end;
$$;

create or replace function public.erp_r90_cash_ledger_reconciliation(p_company_id uuid)
returns table(
  cash_account_id text,cash_account_name text,currency text,
  subledger_balance numeric,ledger_balance numeric,difference numeric
)
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
    raise exception 'permission_denied:accounting.view' using errcode='42501';
  end if;
  return query
  select r.cash_account_id,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','name',null)
      then r.cash_account_name else '' end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','currency',null)
      then r.currency else '' end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','balance',null)
      then r.subledger_balance else null end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','ledgerBalance',null)
      then r.ledger_balance else null end,
    case when public.erp_cloud_user_can_view_field(p_company_id,'cashbox','reconciliationDifference',null)
      then r.difference else null end
  from public.erp_r22_cloud_cash_ledger_reconciliation(p_company_id) r;
end;
$$;

-- The browser now uses the R90 filtered readers.
revoke execute on function public.erp_r42_list_cash_accounts(uuid) from authenticated;
revoke execute on function public.erp_r22_cloud_cash_account_balances(uuid) from authenticated;
revoke execute on function public.erp_r22_cloud_cash_ledger_reconciliation(uuid) from authenticated;
grant execute on function public.erp_r42_list_cash_accounts(uuid) to service_role;
grant execute on function public.erp_r22_cloud_cash_account_balances(uuid) to service_role;
grant execute on function public.erp_r22_cloud_cash_ledger_reconciliation(uuid) to service_role;

revoke all on function public.erp_r90_filter_cashbox_account(uuid,jsonb) from public,anon;
revoke all on function public.erp_r90_list_cash_accounts(uuid) from public,anon;
revoke all on function public.erp_r90_cash_account_balances(uuid) from public,anon;
revoke all on function public.erp_r90_cash_ledger_reconciliation(uuid) from public,anon;
grant execute on function public.erp_r90_filter_cashbox_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r90_list_cash_accounts(uuid) to authenticated,service_role;
grant execute on function public.erp_r90_cash_account_balances(uuid) to authenticated,service_role;
grant execute on function public.erp_r90_cash_ledger_reconciliation(uuid) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 4. Cashbox granular action enforcement for account definitions and transfer.
--    Existing R24 field guards remain authoritative for individual writes.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r90_save_cash_account(
  p_company_id uuid,p_account jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_exists boolean;
begin
  perform public.erp_active_company_context(p_company_id);
  select exists(
    select 1 from public.erp_cash_accounts ca
    where ca.company_id=p_company_id and ca.id=coalesce(p_account->>'id','')
      and not ca.is_deleted
  ) into v_exists;
  if not public.erp_r88_action_allowed(
    p_company_id,'cashbox',case when v_exists then 'account.edit' else 'account.create' end,
    case when v_exists then 'accounting.update' else 'accounting.create' end
  ) then
    raise exception 'permission_denied:cashbox.account.%',case when v_exists then 'edit' else 'create' end using errcode='42501';
  end if;
  return public.erp_r42_save_cash_account(p_company_id,p_account);
end;
$$;

create or replace function public.erp_r90_delete_cash_account(
  p_company_id uuid,p_cash_account_id text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'cashbox','account.delete','accounting.delete'
  ) then raise exception 'permission_denied:cashbox.account.delete' using errcode='42501'; end if;
  perform public.erp_delete_cloud_cash_account(p_company_id,p_cash_account_id);
end;
$$;

create or replace function public.erp_r90_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'cashbox','transfer','accounting.update'
  ) then raise exception 'permission_denied:cashbox.transfer' using errcode='42501'; end if;
  return public.erp_r22_transfer_cloud_cash(
    p_company_id,p_from_cash_account_id,p_to_cash_account_id,
    p_source_amount,p_target_amount,p_exchange_rate,p_transfer_date,p_notes
  );
end;
$$;

revoke execute on function public.erp_r42_save_cash_account(uuid,jsonb) from authenticated;
revoke execute on function public.erp_delete_cloud_cash_account(uuid,text) from authenticated;
revoke execute on function public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from authenticated;
grant execute on function public.erp_r42_save_cash_account(uuid,jsonb) to service_role;
grant execute on function public.erp_delete_cloud_cash_account(uuid,text) to service_role;
grant execute on function public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to service_role;

revoke all on function public.erp_r90_save_cash_account(uuid,jsonb) from public,anon;
revoke all on function public.erp_r90_delete_cash_account(uuid,text) from public,anon;
revoke all on function public.erp_r90_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from public,anon;
grant execute on function public.erp_r90_save_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r90_delete_cash_account(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r90_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;


-- ---------------------------------------------------------------------------
-- 5. Cashbox transaction mutation boundary + direct-table fail-closed reads.
--    The browser must not bypass granular actions by calling older accounting
--    RPCs directly. Realtime/direct SELECT remains available only for legacy
--    unrestricted roles; once cashbox.fields.restrict is enabled, RLS denies
--    the raw JSON row and the filtered R88/R90 RPCs are authoritative.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r90_post_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_type text:=lower(btrim(coalesce(p_transaction->>'type','')));
  v_action text;
  v_legacy text;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_type not in ('receipt','payment') then
    raise exception 'cash_transaction_type_invalid' using errcode='22023';
  end if;

  if p_replace then
    if not public.erp_r88_action_allowed(
      p_company_id,'cashbox','transaction.edit','accounting.update'
    ) then
      raise exception 'permission_denied:cashbox.transaction.edit' using errcode='42501';
    end if;
  else
    v_action:=case when v_type='receipt' then 'receipt' else 'payment' end;
    v_legacy:=case when v_type='receipt' then 'cashbox.receipt' else 'cashbox.payment' end;
    if not public.erp_r88_action_allowed(
      p_company_id,'cashbox',v_action,v_legacy
    ) then
      raise exception 'permission_denied:cashbox.%',v_action using errcode='42501';
    end if;
  end if;

  -- R22 -> R15 -> R9 remains the authoritative accounting/field guard and
  -- additionally validates receipt/payment permission for both old/new type.
  perform public.erp_r22_post_cloud_cash_transaction(
    p_company_id,p_transaction,p_replace
  );
end;
$$;

create or replace function public.erp_r90_delete_cash_transaction(
  p_company_id uuid,p_transaction_id text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'cashbox','transaction.delete','accounting.delete'
  ) then
    raise exception 'permission_denied:cashbox.transaction.delete' using errcode='42501';
  end if;
  perform public.erp_delete_cloud_cash_transaction(
    p_company_id,p_transaction_id
  );
end;
$$;

create or replace function public.erp_r90_delete_cash_transfer(
  p_company_id uuid,p_transfer_id text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'cashbox','transfer.delete','accounting.delete'
  ) then
    raise exception 'permission_denied:cashbox.transfer.delete' using errcode='42501';
  end if;
  perform public.erp_delete_cloud_cash_transfer(p_company_id,p_transfer_id);
end;
$$;

-- These mature implementations remain callable from trusted SECURITY DEFINER
-- workflows/service_role, but authenticated browser callers must use R90.
revoke execute on function public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)
  from authenticated;
revoke execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  from authenticated;
revoke execute on function public.erp_delete_cloud_cash_transfer(uuid,text)
  from authenticated;
grant execute on function public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)
  to service_role;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  to service_role;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text)
  to service_role;

revoke all on function public.erp_r90_post_cash_transaction(uuid,jsonb,boolean)
  from public,anon;
revoke all on function public.erp_r90_delete_cash_transaction(uuid,text)
  from public,anon;
revoke all on function public.erp_r90_delete_cash_transfer(uuid,text)
  from public,anon;
grant execute on function public.erp_r90_post_cash_transaction(uuid,jsonb,boolean)
  to authenticated,service_role;
grant execute on function public.erp_r90_delete_cash_transaction(uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_r90_delete_cash_transfer(uuid,text)
  to authenticated,service_role;

-- Raw transfer/link tables have no browser read model and are not used by the
-- Flutter client. Keep them internal so a Data API caller cannot inspect or
-- mutate FX/link payloads outside the guarded cashbox RPCs.
revoke all on table public.erp_cash_transfers from public,anon,authenticated;
revoke all on table public.erp_cash_account_links from public,anon,authenticated;
grant select,insert,update,delete on table public.erp_cash_transfers to service_role;
grant select,insert,update,delete on table public.erp_cash_account_links to service_role;

-- For JSON tables that intentionally retain Realtime/direct SELECT in legacy
-- unrestricted mode, add a RESTRICTIVE field boundary. In restricted mode the
-- raw row is invisible, forcing the masked RPC and preventing JSON-field leaks.
do $$
declare
  v_table text;
  v_resource text;
  v_base text;
  v_policy text;
begin
  for v_table,v_resource,v_base in values
    ('erp_cash_accounts','cashbox','accounting.view'),
    ('erp_cash_transactions','cashbox','accounting.view'),
    ('erp_maintenance_orders','maintenance','maintenance.view'),
    ('erp_maintenance_parts','maintenance','maintenance.view'),
    ('erp_maintenance_payments','maintenance','maintenance.view'),
    ('erp_sales_orders_cloud','sales','sales.view'),
    ('erp_sales_order_items_cloud','sales','sales.view'),
    ('erp_purchase_orders_cloud','purchases','purchases.view'),
    ('erp_purchase_order_items_cloud','purchases','purchases.view')
  loop
    if to_regclass('public.'||v_table) is null then continue; end if;
    v_policy:=left(v_table||'_r90_field_scope',63);
    execute format('drop policy if exists %I on public.%I',v_policy,v_table);
    execute format(
      'create policy %I on public.%I as restrictive for select to authenticated using ('||
      'public.is_active_company_member(company_id) and '||
      'public.erp_cloud_user_has_permission(company_id,%L) and '||
      'not public.erp_cloud_user_has_permission(company_id,%L))',
      v_policy,v_table,v_base,v_resource||'.fields.restrict'
    );
  end loop;
end $$;

-- Workflow documents are shared by Sales and Purchases. Their raw JSON is
-- likewise hidden when the corresponding module has field restrictions.
drop policy if exists erp_commercial_workflow_documents_r90_field_scope
  on public.erp_commercial_workflow_documents;
create policy erp_commercial_workflow_documents_r90_field_scope
on public.erp_commercial_workflow_documents as restrictive for select to authenticated using (
  public.is_active_company_member(company_id)
  and (
    (lower(module)='sales'
      and public.erp_cloud_user_has_permission(company_id,'sales.view')
      and not public.erp_cloud_user_has_permission(company_id,'sales.fields.restrict'))
    or
    (lower(module)='purchases'
      and public.erp_cloud_user_has_permission(company_id,'purchases.view')
      and not public.erp_cloud_user_has_permission(company_id,'purchases.fields.restrict'))
  )
);

-- Seed R90 granular actions when the SQL permission catalog is present. The
-- Flutter catalog also exposes these codes and role-save can create them on
-- older databases, so this remains backward compatible.
do $$
begin
  if to_regclass('public.erp_permissions') is not null then
    insert into public.erp_permissions(code,module,action,description) values
      ('cashbox.account.create','cashbox','create','Create Cashbox definition'),
      ('cashbox.account.edit','cashbox','update','Edit Cashbox definition'),
      ('cashbox.account.delete','cashbox','delete','Delete Cashbox definition'),
      ('cashbox.transfer','cashbox','transfer','Transfer between Cashboxes'),
      ('cashbox.transfer.delete','cashbox','delete','Delete/reverse Cashbox transfer'),
      ('cashbox.transaction.print','cashbox','print','Print Cashbox transaction')
    on conflict(code) do nothing;
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 6. Maintenance material issue approval ownership.
--    Drafting warehouse/quantity selections must never touch inventory. The
--    mature R57 FIFO/journal execution is invoked only when the draft is
--    explicitly approved, keeping Inventory changes approval-owned.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_r90_maintenance_issue_drafts(
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  maintenance_order_id uuid not null references public.erp_maintenance_orders(id),
  document_number text not null,
  status text not null default 'draft' check(status in ('draft','approved','cancelled')),
  created_by uuid,
  created_at timestamptz not null default now(),
  approved_by uuid,
  approved_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(company_id,id)
);
create unique index if not exists erp_r90_maintenance_issue_one_draft_idx
  on public.erp_r90_maintenance_issue_drafts(company_id,maintenance_order_id)
  where status='draft';
create index if not exists erp_r90_maintenance_issue_order_idx
  on public.erp_r90_maintenance_issue_drafts(company_id,maintenance_order_id,created_at desc);
alter table public.erp_r90_maintenance_issue_drafts enable row level security;

create table if not exists public.erp_r90_maintenance_issue_draft_lines(
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  draft_id uuid not null references public.erp_r90_maintenance_issue_drafts(id) on delete cascade,
  maintenance_order_id uuid not null references public.erp_maintenance_orders(id),
  maintenance_part_id uuid not null references public.erp_maintenance_parts(id),
  warehouse_id text not null,
  quantity numeric(20,4) not null check(quantity>0),
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz not null default now(),
  unique(company_id,draft_id,maintenance_part_id,warehouse_id)
);
create index if not exists erp_r90_maintenance_issue_draft_lines_order_idx
  on public.erp_r90_maintenance_issue_draft_lines(company_id,maintenance_order_id,draft_id);
alter table public.erp_r90_maintenance_issue_draft_lines enable row level security;

alter table public.erp_maintenance_material_issues
  add column if not exists r90_draft_id uuid references public.erp_r90_maintenance_issue_drafts(id);
create index if not exists erp_maintenance_material_issues_r90_draft_idx
  on public.erp_maintenance_material_issues(company_id,r90_draft_id)
  where r90_draft_id is not null;

revoke all on table public.erp_r90_maintenance_issue_drafts from public,anon,authenticated;
revoke all on table public.erp_r90_maintenance_issue_draft_lines from public,anon,authenticated;
grant select,insert,update,delete on table public.erp_r90_maintenance_issue_drafts to service_role;
grant select,insert,update,delete on table public.erp_r90_maintenance_issue_draft_lines to service_role;

create or replace function public.erp_r90_ensure_maintenance_issue_draft(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid;
  v_order public.erp_maintenance_orders%rowtype;
  v_number text;
begin
  perform public.erp_active_company_context(p_company_id);
  select * into v_order
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;
  if v_order.workflow_stage<>'stock_issue_draft' then
    raise exception 'maintenance_issue_draft_stage_invalid:%',v_order.workflow_stage using errcode='P0001';
  end if;

  select id into v_id
  from public.erp_r90_maintenance_issue_drafts
  where company_id=p_company_id and maintenance_order_id=p_order_id and status='draft'
  order by created_at desc limit 1 for update;
  if v_id is not null then return v_id; end if;

  v_number:=public.erp_next_document_number(
    p_company_id,'maintenance_stock_issue','MSI',coalesce(v_order.maintenance_date,now())
  );
  v_id:=gen_random_uuid();
  insert into public.erp_r90_maintenance_issue_drafts(
    id,company_id,maintenance_order_id,document_number,status,created_by,created_at,updated_at
  ) values(
    v_id,p_company_id,p_order_id,v_number,'draft',auth.uid(),now(),now()
  );
  update public.erp_maintenance_orders
  set stock_issue_number=case
        when stock_issue_number is null or stock_issue_number='PENDING' then v_number
        else stock_issue_number end,
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_order_id;
  return v_id;
end;
$$;

create or replace function public.erp_r90_save_maintenance_issue_draft_line(
  p_company_id uuid,p_order_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_draft uuid;
  v_part public.erp_maintenance_parts%rowtype;
  v_product text;
  v_issued numeric:=0;
  v_other_draft numeric:=0;
  v_available numeric:=0;
  v_line_id uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','material_issue.create','maintenance.approve'
  ) then raise exception 'permission_denied:maintenance.material_issue.create' using errcode='42501'; end if;
  if not public.erp_cloud_user_can_edit_field(p_company_id,'maintenance','itemWarehouse',null)
     or not public.erp_cloud_user_can_edit_field(p_company_id,'maintenance','itemQuantity',null) then
    raise exception 'field_permission_denied:maintenance.material_issue_draft' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then
    raise exception 'maintenance_issue_warehouse_required' using errcode='22023';
  end if;
  if coalesce(p_quantity,0)<=0 then
    raise exception 'maintenance_issue_quantity_must_be_positive' using errcode='22023';
  end if;

  select * into v_part
  from public.erp_maintenance_parts
  where company_id=p_company_id and id=p_part_id and maintenance_order_id=p_order_id
    and not is_deleted and line_type<>'service'
  for update;
  if not found then raise exception 'maintenance_part_not_found' using errcode='P0002'; end if;
  v_product:=coalesce(v_part.source_product_id,v_part.product_id::text);
  v_draft:=public.erp_r90_ensure_maintenance_issue_draft(p_company_id,p_order_id);

  select coalesce(sum(il.quantity),0) into v_issued
  from public.erp_maintenance_material_issue_lines il
  join public.erp_maintenance_material_issues i
    on i.company_id=il.company_id and i.id=il.issue_id and i.status='executed'
  where il.company_id=p_company_id and il.maintenance_part_id=p_part_id;

  select coalesce(sum(dl.quantity),0) into v_other_draft
  from public.erp_r90_maintenance_issue_draft_lines dl
  where dl.company_id=p_company_id and dl.draft_id=v_draft
    and dl.maintenance_part_id=p_part_id and dl.warehouse_id<>p_warehouse_id;

  if v_issued+v_other_draft+p_quantity>v_part.quantity then
    raise exception 'maintenance_issue_draft_exceeds_remaining:%',greatest(v_part.quantity-v_issued-v_other_draft,0)
      using errcode='22023';
  end if;

  select coalesce(max(x.available_quantity),0) into v_available
  from public.erp_r57_maintenance_issue_warehouse_options(p_company_id,p_part_id) x
  where x.warehouse_id=p_warehouse_id;
  if v_available<p_quantity then
    raise exception 'maintenance_insufficient_stock:%:%',v_part.product_name,v_available using errcode='P0001';
  end if;

  insert into public.erp_r90_maintenance_issue_draft_lines(
    company_id,draft_id,maintenance_order_id,maintenance_part_id,warehouse_id,
    quantity,created_by,created_at,updated_by,updated_at
  ) values(
    p_company_id,v_draft,p_order_id,p_part_id,p_warehouse_id,
    p_quantity,auth.uid(),now(),auth.uid(),now()
  )
  on conflict(company_id,draft_id,maintenance_part_id,warehouse_id) do update
    set quantity=excluded.quantity,updated_by=auth.uid(),updated_at=now()
  returning id into v_line_id;

  return jsonb_build_object(
    'draftId',v_draft,'lineId',v_line_id,'partId',p_part_id,
    'warehouseId',p_warehouse_id,'quantity',p_quantity,'inventoryChanged',false
  );
end;
$$;

create or replace function public.erp_r90_delete_maintenance_issue_draft_line(
  p_company_id uuid,p_line_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare v_order_id uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','material_issue.create','maintenance.approve'
  ) then raise exception 'permission_denied:maintenance.material_issue.create' using errcode='42501'; end if;
  select maintenance_order_id into v_order_id
  from public.erp_r90_maintenance_issue_draft_lines
  where company_id=p_company_id and id=p_line_id;
  if v_order_id is null then raise exception 'maintenance_issue_draft_line_not_found' using errcode='P0002'; end if;
  if not exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=v_order_id and not o.is_deleted
      and o.workflow_stage='stock_issue_draft'
  ) then raise exception 'maintenance_issue_draft_stage_invalid' using errcode='P0001'; end if;
  delete from public.erp_r90_maintenance_issue_draft_lines
  where company_id=p_company_id and id=p_line_id;
end;
$$;


create or replace function public.erp_r90_maintenance_issue_warehouse_options(
  p_company_id uuid,p_part_id uuid
) returns table(warehouse_id text,warehouse_name text,available_quantity numeric)
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','material_issue.create','maintenance.approve'
  ) then raise exception 'permission_denied:maintenance.material_issue.create' using errcode='42501'; end if;
  if not public.erp_cloud_user_can_view_field(
       p_company_id,'maintenance','itemWarehouse','maintenance.view'
     ) then raise exception 'field_permission_denied:maintenance.itemWarehouse' using errcode='42501'; end if;
  if not public.erp_cloud_user_can_view_field(
       p_company_id,'inventory','quantity','inventory.view'
     ) then raise exception 'field_permission_denied:inventory.quantity' using errcode='42501'; end if;
  return query
    select x.warehouse_id,x.warehouse_name,x.available_quantity
    from public.erp_r57_maintenance_issue_warehouse_options(p_company_id,p_part_id) x;
end;
$$;

create or replace function public.erp_r90_maintenance_issue_draft_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_current jsonb:='{}'::jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_history jsonb:='[]'::jsonb;
  v_can_stock boolean;
  v_can_actor boolean;
  v_can_warehouse boolean;
  v_can_qty boolean;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_cloud_user_has_permission(p_company_id,'maintenance.view') then
    raise exception 'permission_denied:maintenance.view' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
      and public.erp_r84_record_visible(p_company_id,'maintenance',o.created_by,null)
  ) then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;

  v_can_stock:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','stockIssue','maintenance.view'
  );
  if not v_can_stock then return jsonb_build_object('currentDraft','{}'::jsonb,'draftLines','[]'::jsonb,'history','[]'::jsonb); end if;
  v_can_actor:=public.erp_cloud_user_can_view_field(p_company_id,'maintenance','createdBy',null);
  v_can_warehouse:=public.erp_cloud_user_can_view_field(p_company_id,'maintenance','itemWarehouse',null);
  v_can_qty:=public.erp_cloud_user_can_view_field(p_company_id,'maintenance','itemQuantity',null);

  select jsonb_strip_nulls(jsonb_build_object(
    'id',d.id,'documentNumber',d.document_number,'status',d.status,
    'createdAt',d.created_at,
    'createdBy',case when v_can_actor then d.created_by else null end,
    'createdByName',case when v_can_actor then cp.full_name else null end
  )) into v_current
  from public.erp_r90_maintenance_issue_drafts d
  left join public.profiles cp on cp.id=d.created_by
  where d.company_id=p_company_id and d.maintenance_order_id=p_order_id and d.status='draft'
  order by d.created_at desc limit 1;
  v_current:=coalesce(v_current,'{}'::jsonb);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',dl.id,'draftId',dl.draft_id,'partId',dl.maintenance_part_id,
    'productId',coalesce(mp.source_product_id,mp.product_id::text),
    'productName',mp.product_name,
    'warehouseId',case when v_can_warehouse then dl.warehouse_id else null end,
    'warehouseName',case when v_can_warehouse then coalesce(w.data->>'name',w.data->>'nameAr',w.data->>'nameEn',dl.warehouse_id) else null end,
    'quantity',case when v_can_qty then dl.quantity else null end,
    'createdAt',dl.created_at,
    'createdBy',case when v_can_actor then dl.created_by else null end,
    'createdByName',case when v_can_actor then lp.full_name else null end
  )) order by dl.created_at,dl.id),'[]'::jsonb) into v_lines
  from public.erp_r90_maintenance_issue_draft_lines dl
  join public.erp_r90_maintenance_issue_drafts d
    on d.company_id=dl.company_id and d.id=dl.draft_id and d.status='draft'
  join public.erp_maintenance_parts mp
    on mp.company_id=dl.company_id and mp.id=dl.maintenance_part_id and not mp.is_deleted
  left join public.erp_warehouses w
    on w.company_id=dl.company_id and w.id=dl.warehouse_id and not w.is_deleted
  left join public.profiles lp on lp.id=dl.created_by
  where dl.company_id=p_company_id and dl.maintenance_order_id=p_order_id;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',d.id,'documentNumber',d.document_number,'status',d.status,
    'createdAt',d.created_at,'approvedAt',d.approved_at,
    'createdBy',case when v_can_actor then d.created_by else null end,
    'createdByName',case when v_can_actor then cp.full_name else null end,
    'approvedBy',case when v_can_actor then d.approved_by else null end,
    'approvedByName',case when v_can_actor then ap.full_name else null end,
    'lineCount',(select count(*) from public.erp_r90_maintenance_issue_draft_lines x where x.company_id=d.company_id and x.draft_id=d.id),
    'quantity',case when v_can_qty then (select coalesce(sum(x.quantity),0) from public.erp_r90_maintenance_issue_draft_lines x where x.company_id=d.company_id and x.draft_id=d.id) else null end
  )) order by d.created_at desc),'[]'::jsonb) into v_history
  from public.erp_r90_maintenance_issue_drafts d
  left join public.profiles cp on cp.id=d.created_by
  left join public.profiles ap on ap.id=d.approved_by
  where d.company_id=p_company_id and d.maintenance_order_id=p_order_id and d.status<>'draft';

  return jsonb_build_object(
    'currentDraft',v_current,
    'draftLines',coalesce(v_lines,'[]'::jsonb),
    'history',coalesce(v_history,'[]'::jsonb)
  );
end;
$$;

create or replace function public.erp_r90_maintenance_material_issue_state(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_draft jsonb;
  v_events jsonb:='[]'::jsonb;
  v_event jsonb;
  v_actor uuid;
  v_actor_name text;
  v_issue_number text;
  v_actor_allowed boolean;
begin
  v_base:=public.erp_r89_maintenance_material_issue_state(p_company_id,p_order_id);
  v_draft:=public.erp_r90_maintenance_issue_draft_state(p_company_id,p_order_id);
  v_actor_allowed:=public.erp_cloud_user_can_view_field(
    p_company_id,'maintenance','createdBy','maintenance.view'
  );
  for v_event in select value from jsonb_array_elements(coalesce(v_base->'events','[]'::jsonb)) loop
    v_actor:=null;
    v_actor_name:=null;
    v_issue_number:=null;
    select i.created_by,
           case when v_actor_allowed then p.full_name else null end,
           d.document_number
      into v_actor,v_actor_name,v_issue_number
    from public.erp_maintenance_material_issues i
    left join public.profiles p on p.id=i.created_by
    left join public.erp_r90_maintenance_issue_drafts d
      on d.company_id=i.company_id and d.id=i.r90_draft_id
    where i.company_id=p_company_id and i.id::text=coalesce(v_event->>'issueId','');
    v_events:=v_events||jsonb_build_array(
      jsonb_strip_nulls(v_event||jsonb_build_object(
        'issueNumber',v_issue_number,
        'approvedBy',case when v_actor_allowed then v_actor else null end,
        'approvedByName',case when v_actor_allowed then v_actor_name else null end,
        'approvalTime',v_event->'effectiveAt'
      ))
    );
  end loop;
  return (v_base-'events')||jsonb_build_object(
    'events',v_events,
    'issueDraft',v_draft
  );
end;
$$;

create or replace function public.erp_r90_get_maintenance_order_snapshot(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_issue jsonb;
begin
  v_base:=public.erp_r89_get_maintenance_order_snapshot(p_company_id,p_order_id);
  v_issue:=public.erp_r90_maintenance_material_issue_state(p_company_id,p_order_id);
  return jsonb_set(v_base,'{issueState}',v_issue,true)||jsonb_build_object('snapshotProfile','R90');
end;
$$;

create or replace function public.erp_r90_approve_maintenance_issue_draft(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_draft public.erp_r90_maintenance_issue_drafts%rowtype;
  v_line record;
  v_result jsonb;
  v_issue_id uuid;
  v_count integer:=0;
  v_actor_name text:='';
  v_car text:='';
  v_remaining_stage text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.erp_r88_action_allowed(
    p_company_id,'maintenance','material_issue.approve','maintenance.approve'
  ) then raise exception 'permission_denied:maintenance.material_issue.approve' using errcode='42501'; end if;

  select * into v_order
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;
  if v_order.workflow_stage<>'stock_issue_draft' then
    raise exception 'maintenance_issue_approval_stage_invalid:%',v_order.workflow_stage using errcode='P0001';
  end if;

  if not exists(
    select 1 from public.erp_maintenance_parts p
    where p.company_id=p_company_id and p.maintenance_order_id=p_order_id
      and not p.is_deleted and p.line_type<>'service'
  ) then
    update public.erp_maintenance_orders
    set workflow_stage='stock_issue_approved',updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=p_order_id;
    select workflow_stage into v_remaining_stage
    from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id;
    return jsonb_build_object(
      'ok',true,'approvedLines',0,'workflowStage',v_remaining_stage,
      'inventoryChanged',false,'serviceOnly',true
    );
  end if;

  select * into v_draft
  from public.erp_r90_maintenance_issue_drafts
  where company_id=p_company_id and maintenance_order_id=p_order_id and status='draft'
  order by created_at desc limit 1 for update;
  if not found then raise exception 'maintenance_issue_draft_missing' using errcode='P0001'; end if;
  if not exists(
    select 1 from public.erp_r90_maintenance_issue_draft_lines dl
    where dl.company_id=p_company_id and dl.draft_id=v_draft.id
  ) then raise exception 'maintenance_issue_draft_empty' using errcode='P0001'; end if;

  -- Each mature R57 issue call performs FIFO, inventory movement and journal
  -- ownership. Because all calls run in this approval transaction, any error
  -- rolls the whole approval back; a draft can never be partially posted.
  for v_line in
    select * from public.erp_r90_maintenance_issue_draft_lines dl
    where dl.company_id=p_company_id and dl.draft_id=v_draft.id
    order by dl.created_at,dl.id
  loop
    v_issue_id:=gen_random_uuid();
    v_result:=public.erp_r57_execute_maintenance_material_issue(
      p_company_id,p_order_id,v_issue_id,v_line.maintenance_part_id,
      v_line.warehouse_id,v_line.quantity,coalesce(v_order.maintenance_date,now())
    );
    update public.erp_maintenance_material_issues
    set r90_draft_id=v_draft.id
    where company_id=p_company_id and id=v_issue_id;
    v_count:=v_count+1;
  end loop;

  update public.erp_r90_maintenance_issue_drafts
  set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now()
  where company_id=p_company_id and id=v_draft.id;

  select workflow_stage into v_remaining_stage
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id;
  if v_remaining_stage='stock_issue_draft' then
    perform public.erp_r90_ensure_maintenance_issue_draft(p_company_id,p_order_id);
  end if;

  select coalesce(full_name,'') into v_actor_name from public.profiles where id=auth.uid();
  v_car:=coalesce(nullif(v_order.car_name,''),v_order.car_id::text);
  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(p_company_id,gen_random_uuid(),jsonb_build_object(
    'eventKey','r90:maintenance_material_issue:'||v_draft.id::text,
    'eventType','maintenance_material_issue','event','maintenance_material_issue',
    'type','success','module','maintenance',
    'documentReference',v_draft.document_number,'orderReference',v_order.order_number,
    'actorUserId',auth.uid(),'actorUser',v_actor_name,'dateTime',now(),
    'carId',v_order.car_id,'carName',v_car,'customerName',coalesce(v_order.customer_name,''),
    'currency',upper(v_order.currency_code),'referenceType','maintenance_order',
    'referenceId',p_order_id::text,'deepLink','/maintenance',
    'titleAr','تم تصديق صرف مواد الصيانة','titleEn','Maintenance material issue approved',
    'bodyAr',v_actor_name||' • '||v_draft.document_number||' • '||v_car,
    'bodyEn',v_actor_name||' • '||v_draft.document_number||' • '||v_car,
    'createdAt',now()
  )) on conflict do nothing;

  return jsonb_build_object(
    'ok',true,'draftId',v_draft.id,'documentNumber',v_draft.document_number,
    'approvedLines',v_count,'approvedBy',auth.uid(),'approvedAt',now(),
    'workflowStage',v_remaining_stage,'inventoryChanged',true
  );
end;
$$;

-- Preserve the R88 wrapper as an internal implementation, then make R90 own
-- the stock-issue approval transition. Order approval/invoice stages continue
-- through the mature R88 chain unchanged.
alter function public.erp_r37_advance_maintenance_workflow(uuid,uuid)
  rename to erp_r37_advance_maintenance_workflow_pre_r90;
revoke all on function public.erp_r37_advance_maintenance_workflow_pre_r90(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.erp_r37_advance_maintenance_workflow_pre_r90(uuid,uuid)
  to service_role;

create or replace function public.erp_r37_advance_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_stage text;
  v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  select workflow_stage into v_stage
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;

  if v_stage='stock_issue_draft' then
    return public.erp_r90_approve_maintenance_issue_draft(p_company_id,p_order_id);
  end if;

  v_result:=public.erp_r37_advance_maintenance_workflow_pre_r90(p_company_id,p_order_id);
  select workflow_stage into v_stage
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id;
  if v_stage='stock_issue_draft' then
    perform public.erp_r90_ensure_maintenance_issue_draft(p_company_id,p_order_id);
  end if;
  return v_result;
end;
$$;

-- Direct R57 material execution is now internal. Browser users can only save a
-- non-posting draft and approve that draft through the R90/R37 boundary.
revoke execute on function public.erp_r57_execute_maintenance_material_issue(
  uuid,uuid,uuid,uuid,text,numeric,timestamptz
) from authenticated;
grant execute on function public.erp_r57_execute_maintenance_material_issue(
  uuid,uuid,uuid,uuid,text,numeric,timestamptz
) to service_role;
revoke execute on function public.erp_r57_maintenance_issue_warehouse_options(uuid,uuid)
  from authenticated;
grant execute on function public.erp_r57_maintenance_issue_warehouse_options(uuid,uuid)
  to service_role;

revoke all on function public.erp_r90_ensure_maintenance_issue_draft(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.erp_r90_save_maintenance_issue_draft_line(uuid,uuid,uuid,text,numeric)
  from public,anon;
revoke all on function public.erp_r90_delete_maintenance_issue_draft_line(uuid,uuid)
  from public,anon;
revoke all on function public.erp_r90_maintenance_issue_warehouse_options(uuid,uuid)
  from public,anon;
revoke all on function public.erp_r90_maintenance_issue_draft_state(uuid,uuid)
  from public,anon;
revoke all on function public.erp_r90_maintenance_material_issue_state(uuid,uuid)
  from public,anon;
revoke all on function public.erp_r90_get_maintenance_order_snapshot(uuid,uuid)
  from public,anon;
revoke all on function public.erp_r90_approve_maintenance_issue_draft(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.erp_r37_advance_maintenance_workflow(uuid,uuid)
  from public,anon;

grant execute on function public.erp_r90_save_maintenance_issue_draft_line(uuid,uuid,uuid,text,numeric)
  to authenticated,service_role;
grant execute on function public.erp_r90_delete_maintenance_issue_draft_line(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r90_maintenance_issue_warehouse_options(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r90_maintenance_issue_draft_state(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r90_maintenance_material_issue_state(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r90_get_maintenance_order_snapshot(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_r90_approve_maintenance_issue_draft(uuid,uuid)
  to service_role;
grant execute on function public.erp_r37_advance_maintenance_workflow(uuid,uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
