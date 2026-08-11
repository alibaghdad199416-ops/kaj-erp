\set ON_ERROR_STOP on
\pset pager off

begin;

do $verify$
declare v_definition text; v_count integer;
begin
  select count(*) into v_count from pg_indexes
  where schemaname='public' and indexname in (
    'uq_r56_maintenance_active_opportunity',
    'idx_r56_maintenance_vehicle_timeline',
    'idx_r56_maintenance_customer_timeline');
  if v_count<>3 then raise exception 'r56_required_indexes_missing:%',v_count; end if;

  if not exists(select 1 from information_schema.columns
    where table_schema='public' and table_name='erp_maintenance_orders'
      and column_name='opportunity_id') then
    raise exception 'r56_opportunity_link_column_missing';
  end if;

  select pg_get_functiondef('public.erp_r56_vehicle_service_card(uuid,text)'::regprocedure)
  into v_definition;
  if v_definition ~* '(purchasePrice|acquisition|unit_cost|parts_cost|labor_cost|total_cost|profit|car_cost_added)' then
    raise exception 'r56_vehicle_service_card_leaks_internal_cost';
  end if;
  if v_definition not like '%source_car_id=p_car_id%' then
    raise exception 'r56_vehicle_history_not_canonical';
  end if;

  select pg_get_functiondef('public.erp_r56_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,text,timestamptz)'::regprocedure)
  into v_definition;
  if v_definition not like '%return v_existing%' then
    raise exception 'r56_opportunity_action_not_idempotent';
  end if;

  if not exists(select 1 from information_schema.triggers
    where event_object_schema='public' and event_object_table='erp_maintenance_orders'
      and trigger_name='trg_r56_validate_maintenance_relationship') then
    raise exception 'r56_relationship_guard_missing';
  end if;
end
$verify$;

rollback;
