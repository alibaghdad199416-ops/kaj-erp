-- R70.4/R70.5 rollback-safe structural/runtime-contract proof.
-- It intentionally does not modify business data.
begin;

do $$
declare
  v_sales_guard text;
  v_crm_read text;
  v_maintenance_find text;
  v_maintenance_cancel text;
begin
  select pg_get_functiondef('public.erp_validate_sales_order_opportunity_link()'::regprocedure)
    into v_sales_guard;
  if position('v_same_historical_link' in v_sales_guard)=0
     or position('v_cancel_restore' in v_sales_guard)=0
     or position('v_creates_or_relinks' in v_sales_guard)=0
     or position('opportunity_is_lost' in v_sales_guard)=0 then
    raise exception 'R70.4 Sales Opportunity guard is not operation-scoped';
  end if;

  select pg_get_functiondef('public.erp_r70_list_opportunities(uuid)'::regprocedure)
    into v_crm_read;
  if position('maintenanceOrderId' in v_crm_read)=0
     or position('maintenanceOrderNumber' in v_crm_read)=0
     or position('maintenanceOrderStatus' in v_crm_read)=0
     or position('erp_maintenance_orders' in v_crm_read)=0 then
    raise exception 'R70.4 CRM snapshot does not expose canonical Maintenance linkage';
  end if;

  select pg_get_functiondef('public.erp_r56_find_maintenance_by_opportunity(uuid,text)'::regprocedure)
    into v_maintenance_find;
  if position('o.opportunity_id=p_opportunity_id' in replace(v_maintenance_find,' ',''))=0 then
    raise exception 'R70.4 Maintenance Opportunity readback is not canonical';
  end if;
  if position('o.cancelled_at is null' in lower(v_maintenance_find))=0 then
    raise exception 'R70.4 Maintenance readback does not prioritize active history';
  end if;

  select pg_get_functiondef('public.erp_r67_cancel_maintenance_order(uuid,uuid,text)'::regprocedure)
    into v_maintenance_cancel;
  if position('draftCancellation' in v_maintenance_cancel)=0
     or position('workflow_stage=''cancelled''' in v_maintenance_cancel)=0
     or position('maintenance.cancel' in v_maintenance_cancel)=0 then
    raise exception 'R70.5 governed Maintenance Draft cancellation is missing';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname='public'
      and indexname='idx_r70_maintenance_opportunity_history'
  ) then
    raise exception 'R70.4 Maintenance Opportunity history index is missing';
  end if;

  if has_function_privilege('anon','public.erp_r67_cancel_maintenance_order(uuid,uuid,text)','EXECUTE') then
    raise exception 'anon must not execute Maintenance cancellation';
  end if;
end $$;

rollback;
