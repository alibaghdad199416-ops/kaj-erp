\set ON_ERROR_STOP on
\pset pager off

begin;
select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);

-- Re-open the archived MO00006 read model inside this transaction only. Its
-- two reversed issue events came from two actual warehouses (3 + 4).
set local session_replication_role=replica;
update public.erp_maintenance_orders
set is_deleted=false,deleted_at=null,status='approved',workflow_stage='stock_issue_draft'
where company_id='11111111-1111-4111-8111-111111111111'
  and id='c8dd9338-cc8d-4da4-9f32-3c44822e34d3';
update public.erp_maintenance_parts
set is_deleted=false,deleted_at=null
where company_id='11111111-1111-4111-8111-111111111111'
  and maintenance_order_id='c8dd9338-cc8d-4da4-9f32-3c44822e34d3';
set local session_replication_role=origin;

do $verify$
declare
  v jsonb;
  v_reconciliation jsonb;
  v_issue_state jsonb;
begin
  v:=public.erp_r64_get_maintenance_order_snapshot(
    '11111111-1111-4111-8111-111111111111',
    'c8dd9338-cc8d-4da4-9f32-3c44822e34d3'
  );
  v_reconciliation:=v->'reconciliation';
  v_issue_state:=v->'issueState';
  if v->'order'->>'id'<>'c8dd9338-cc8d-4da4-9f32-3c44822e34d3'
     or jsonb_array_length(v->'lines')<>1
     or jsonb_array_length(v_issue_state->'events')<>2 then
    raise exception 'r64_snapshot_shape_failed:%',v;
  end if;
  if (select count(distinct event->>'warehouseId')
      from jsonb_array_elements(v_issue_state->'events') event)<>2
     or (select sum((event->>'quantity')::numeric)
         from jsonb_array_elements(v_issue_state->'events') event)<>7 then
    raise exception 'r64_actual_multiwarehouse_events_collapsed:%',v_issue_state;
  end if;
  if exists(select 1 from jsonb_array_elements(v_issue_state->'events') event
            where event->>'status'<>'reversed')
     or (v_reconciliation->>'issuedMaterialsActualCost')::numeric<>0
     or (v_reconciliation->'lines'->0->>'remainingQuantity')::numeric<0 then
    raise exception 'r64_reversal_or_quantity_state_invalid:%',v;
  end if;
  if (v_reconciliation->>'materialsInvoiced')::numeric =
     (v_reconciliation->>'issuedMaterialsActualCost')::numeric
     and (v_reconciliation->>'materialsInvoiced')::numeric<>0 then
    raise exception 'r64_billable_value_collapsed_to_fifo_cost:%',v_reconciliation;
  end if;
  if (v_reconciliation->>'outstanding')::numeric<0 then
    raise exception 'r64_negative_outstanding:%',v_reconciliation;
  end if;
end $verify$;

rollback;
\echo 'R64 maintenance authoritative snapshot PASS'
