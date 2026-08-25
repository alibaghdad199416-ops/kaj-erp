-- Quality Line ERP v17.14.0 P15
-- Authoritative cloud reconciliation snapshot for detecting workflow drift.

create or replace function public.erp_get_workflow_reconciliation_snapshot(
  p_organization_id uuid,
  p_module text,
  p_invoice_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workflow_id text;
  v_aggregate jsonb;
  v_version bigint;
  v_updated_at timestamptz;
  v_journals jsonb;
  v_movements jsonb;
  v_balances jsonb;
  v_operation jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not public.erp_is_active_member(p_organization_id) then raise exception 'permission_denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;

  if p_module='sales' then
    select workflow_id,aggregate,version,updated_at
      into v_workflow_id,v_aggregate,v_version,v_updated_at
    from public.erp_sales_workflows
    where organization_id=p_organization_id
      and aggregate#>>'{invoice,id}'=p_invoice_id;
  else
    select workflow_id,aggregate,version,updated_at
      into v_workflow_id,v_aggregate,v_version,v_updated_at
    from public.erp_purchase_workflows
    where organization_id=p_organization_id
      and aggregate#>>'{invoice,id}'=p_invoice_id;
  end if;
  if v_workflow_id is null then raise exception 'cloud_workflow_not_found'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'entry',to_jsonb(e),
    'lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.line_number)
                      from public.erp_cloud_journal_lines l
                      where l.entry_id=e.id),'[]'::jsonb)
  ) order by e.entry_date,e.id),'[]'::jsonb)
  into v_journals
  from public.erp_cloud_journal_entries e
  where e.organization_id=p_organization_id and e.workflow_id=v_workflow_id;

  select coalesce(jsonb_agg(to_jsonb(m) order by m.movement_date,m.id),'[]'::jsonb)
  into v_movements
  from public.erp_cloud_inventory_movements m
  where m.organization_id=p_organization_id and m.workflow_id=v_workflow_id;

  select coalesce(jsonb_agg(to_jsonb(b) order by b.warehouse_id,b.product_id),'[]'::jsonb)
  into v_balances
  from public.erp_cloud_stock_balances b
  where b.organization_id=p_organization_id
    and exists (
      select 1 from public.erp_cloud_inventory_movements m
      where m.organization_id=b.organization_id
        and m.workflow_id=v_workflow_id
        and m.warehouse_id=b.warehouse_id
        and m.product_id=b.product_id
    );

  select to_jsonb(o) into v_operation
  from public.erp_reversal_operations o
  where o.organization_id=p_organization_id
    and o.module=p_module
    and o.invoice_id=p_invoice_id
  order by o.requested_at desc
  limit 1;

  return jsonb_build_object(
    'workflowId',v_workflow_id,
    'version',v_version,
    'updatedAt',v_updated_at,
    'aggregate',v_aggregate,
    'journals',v_journals,
    'inventoryMovements',v_movements,
    'stockBalances',v_balances,
    'reversalOperation',coalesce(v_operation,'{}'::jsonb)
  );
end;
$$;

grant execute on function public.erp_get_workflow_reconciliation_snapshot(uuid,text,text) to authenticated;
