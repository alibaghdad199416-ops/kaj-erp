\set ON_ERROR_STOP on
\pset pager off

begin;

do $$
declare
  v_def text;
  v_trigger_count bigint;
  v_company_id uuid;
  v_schedule_id uuid:=gen_random_uuid();
  v_due timestamptz:=date_trunc('second',now())+interval '5 days';
  v_next_due timestamptz;
  v_count bigint;
begin
  -- R88/R89 must be applied and the browser-facing adapters must exist.
  if to_regprocedure('public.erp_manage_commercial_order_component_v3(uuid,text,uuid,text,uuid,text,text)') is null then
    raise exception 'r89_purchase_receipt_adapter_missing';
  end if;
  if to_regprocedure('public.erp_r88_filter_trial_balance_row(uuid,jsonb)') is null then
    raise exception 'r89_trial_balance_filter_missing';
  end if;
  if to_regprocedure('public.erp_r89_get_commercial_order_snapshot(uuid,uuid,boolean)') is null
     or to_regprocedure('public.erp_r89_get_maintenance_order_snapshot(uuid,uuid)') is null
     or to_regprocedure('public.erp_r89_maintenance_cost_reconciliation(uuid,uuid)') is null
     or to_regprocedure('public.erp_r89_maintenance_material_issue_state(uuid,uuid)') is null then
    raise exception 'r89_secure_detail_read_boundary_missing';
  end if;
  if to_regprocedure('public.erp_r89_cloud_cash_flow_hierarchy(uuid,text,text,text,text,timestamptz,timestamptz)') is null
     or to_regprocedure('public.erp_r89_list_cashboxes_for_cash_flow(uuid)') is null then
    raise exception 'r89_cash_flow_cashbox_contract_missing';
  end if;

  -- Purchase receipt/delivery must normalize to the mature logistics boundary.
  select pg_get_functiondef(
    'public.erp_manage_commercial_order_component_v3(uuid,text,uuid,text,uuid,text,text)'::regprocedure
  ) into v_def;
  if v_def not like '%receipt%'
     or v_def not like '%delivery%'
     or v_def not like '%logistics%'
     or v_def not like '%v_inner_type%' then
    raise exception 'r89_purchase_receipt_normalization_not_active';
  end if;

  -- Trial balance must retain all six signed debit/credit fields.
  select pg_get_functiondef(
    'public.erp_r88_filter_trial_balance_row(uuid,jsonb)'::regprocedure
  ) into v_def;
  if v_def not like '%openingDebit%'
     or v_def not like '%openingCredit%'
     or v_def not like '%periodDebit%'
     or v_def not like '%periodCredit%'
     or v_def not like '%closingDebit%'
     or v_def not like '%closingCredit%' then
    raise exception 'r89_trial_balance_six_value_contract_not_active';
  end if;

  -- Cash Flow must remain explicit-cash only and support a selected cashbox.
  select pg_get_functiondef(
    'public.erp_r9_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz)'::regprocedure
  ) into v_def;
  if v_def not like '%cashIn%'
     or v_def not like '%cashOut%' then
    raise exception 'r89_explicit_cash_flow_filter_not_active';
  end if;
  select pg_get_functiondef(
    'public.erp_cloud_cash_flow_hierarchy(uuid,text,text,text,timestamptz,timestamptz)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_cash_transactions%' then
    raise exception 'r89_cash_flow_not_sourced_from_cash_transactions';
  end if;
  select pg_get_functiondef(
    'public.erp_r89_cloud_cash_flow_hierarchy(uuid,text,text,text,text,timestamptz,timestamptz)'::regprocedure
  ) into v_def;
  if v_def not like '%p_cash_account_id%'
     or v_def not like '%cashAccountId%' then
    raise exception 'r89_cashbox_scope_not_active';
  end if;

  -- Sensitive detail reads must be filtered before returning to the browser.
  select pg_get_functiondef(
    'public.erp_r89_get_commercial_order_snapshot(uuid,uuid,boolean)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_r89_filter_commercial_detail_row%'
     or v_def not like '%erp_r89_filter_commercial_document_array%'
     or v_def not like '%erp_r84_record_visible%' then
    raise exception 'r89_commercial_detail_server_filter_not_active';
  end if;
  select pg_get_functiondef(
    'public.erp_r89_get_maintenance_order_snapshot(uuid,uuid)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_r89_maintenance_cost_reconciliation%'
     or v_def not like '%erp_r89_maintenance_material_issue_state%' then
    raise exception 'r89_maintenance_snapshot_secure_wrappers_not_active';
  end if;
  select pg_get_functiondef(
    'public.erp_r89_maintenance_cost_reconciliation(uuid,uuid)'::regprocedure
  ) into v_def;
  if v_def not like '%erp_r89_filter_maintenance_cost_payload%'
     or v_def not like '%erp_r84_record_visible%' then
    raise exception 'r89_maintenance_detail_server_filter_not_active';
  end if;

  -- Browser roles must not bypass schedule/history action RPCs with direct DML.
  if has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','select')
     or has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','insert')
     or has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','update')
     or has_table_privilege('authenticated','public.erp_vehicle_maintenance_schedules','delete') then
    raise exception 'r89_schedule_direct_authenticated_dml_still_exposed';
  end if;
  if has_table_privilege('authenticated','public.erp_maintenance_history_details','select')
     or has_table_privilege('authenticated','public.erp_maintenance_history_details','insert')
     or has_table_privilege('authenticated','public.erp_maintenance_history_details','update')
     or has_table_privilege('authenticated','public.erp_maintenance_history_details','delete') then
    raise exception 'r89_history_direct_authenticated_dml_still_exposed';
  end if;
  if not has_function_privilege(
       'authenticated','public.erp_r89_get_commercial_order_snapshot(uuid,uuid,boolean)','execute')
     or not has_function_privilege(
       'authenticated','public.erp_r89_get_maintenance_order_snapshot(uuid,uuid)','execute') then
    raise exception 'r89_secure_snapshot_rpc_not_exposed_to_authenticated';
  end if;

  select count(*) into v_trigger_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relname='erp_vehicle_maintenance_schedules'
    and t.tgname='erp_r89_spawn_next_maintenance_schedule'
    and not t.tgisinternal
    and t.tgenabled<>'D';
  if v_trigger_count<>1 then
    raise exception 'r89_schedule_recurrence_trigger_not_active:%',v_trigger_count;
  end if;

  select pg_get_functiondef('public.erp_r89_spawn_next_maintenance_schedule()'::regprocedure)
    into v_def;
  if v_def not like '%completed%'
     or v_def not like '%converted%'
     or v_def not like '%recurrence_sequence%'
     or v_def not like '%interval ''1 day''%'
     or v_def not like '%interval ''1 week''%'
     or v_def not like '%interval ''1 month''%'
     or v_def not like '%interval ''1 year''%' then
    raise exception 'r89_schedule_recurrence_definition_incomplete';
  end if;

  -- Exercise the recurrence trigger against the current LOCAL database when a
  -- company exists. The transaction is rolled back, so no fixture survives.
  select id into v_company_id from public.companies order by id limit 1;
  if v_company_id is not null then
    insert into public.erp_vehicle_maintenance_schedules(
      id,company_id,car_id,title,description,due_at,recurrence,
      reminder_minutes,status,is_deleted,recurrence_series_id,recurrence_sequence
    ) values(
      v_schedule_id,v_company_id,'__r89_runtime_vehicle__','R89 runtime recurrence',
      'Rolled back automatically',v_due,'daily',0,'scheduled',false,v_schedule_id,0
    );

    update public.erp_vehicle_maintenance_schedules
    set status='converted',updated_at=now()
    where id=v_schedule_id;

    select count(*),max(due_at) into v_count,v_next_due
    from public.erp_vehicle_maintenance_schedules
    where company_id=v_company_id
      and recurrence_series_id=v_schedule_id
      and recurrence_sequence=1
      and not is_deleted;
    if v_count<>1 then
      raise exception 'r89_converted_schedule_successor_count:%',v_count;
    end if;
    if abs(extract(epoch from (v_next_due-(v_due+interval '1 day'))))>1 then
      raise exception 'r89_converted_schedule_successor_due_mismatch:%',v_next_due;
    end if;
  else
    raise notice 'R89 recurrence data exercise skipped: no company row exists in this LOCAL database.';
  end if;
end $$;

rollback;
select 'R89 Phase 11 LOCAL PostgreSQL runtime PASS' as result;
