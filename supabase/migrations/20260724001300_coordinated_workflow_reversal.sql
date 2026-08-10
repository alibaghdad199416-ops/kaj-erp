-- Quality Line ERP v17.13.0 P14
-- Coordinates invoice, payment journal, and inventory reversal in one PostgreSQL transaction.

create table if not exists public.erp_reversal_operations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  module text not null check (module in ('sales','purchases')),
  workflow_id text not null,
  invoice_id text not null,
  idempotency_key text not null,
  status text not null default 'processing' check (status in ('processing','committed','failed')),
  reason text not null,
  result jsonb not null default '{}'::jsonb,
  requested_by uuid not null,
  requested_at timestamptz not null default now(),
  committed_at timestamptz,
  unique (organization_id,idempotency_key)
);

alter table public.erp_reversal_operations enable row level security;

drop policy if exists erp_reversal_operations_select on public.erp_reversal_operations;
create policy erp_reversal_operations_select on public.erp_reversal_operations
for select to authenticated
using (public.erp_is_active_member(organization_id));

revoke insert, update, delete on public.erp_reversal_operations from anon, authenticated;
grant select on public.erp_reversal_operations to authenticated;

create or replace function public.erp_reverse_workflow_cloud(
  p_organization_id uuid,
  p_module text,
  p_invoice_id text,
  p_reason text default 'coordinated workflow reversal'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workflow_id text;
  v_operation_id uuid;
  v_existing_status text;
  v_existing_result jsonb;
  v_idempotency_key text;
  v_invoice_result jsonb;
  v_inventory_result jsonb;
  v_inventory_results jsonb := '[]'::jsonb;
  v_document record;
  v_result jsonb;
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not public.erp_is_active_member(p_organization_id) then raise exception 'permission_denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;

  if p_module='sales' then
    select workflow_id into v_workflow_id
    from public.erp_sales_workflows
    where organization_id=p_organization_id
      and aggregate#>>'{invoice,id}'=p_invoice_id
    for update;
  else
    select workflow_id into v_workflow_id
    from public.erp_purchase_workflows
    where organization_id=p_organization_id
      and aggregate#>>'{invoice,id}'=p_invoice_id
    for update;
  end if;
  if v_workflow_id is null then raise exception 'cloud_workflow_not_found'; end if;

  v_idempotency_key := p_module||':workflow-reversal:'||p_invoice_id;
  select id,status,result into v_operation_id,v_existing_status,v_existing_result
  from public.erp_reversal_operations
  where organization_id=p_organization_id and idempotency_key=v_idempotency_key
  for update;

  if v_operation_id is not null and v_existing_status='committed' then
    return coalesce(v_existing_result,'{}'::jsonb)||jsonb_build_object('duplicate',true);
  end if;

  if v_operation_id is null then
    insert into public.erp_reversal_operations(
      organization_id,module,workflow_id,invoice_id,idempotency_key,status,reason,requested_by
    ) values (
      p_organization_id,p_module,v_workflow_id,p_invoice_id,v_idempotency_key,'processing',p_reason,auth.uid()
    ) returning id into v_operation_id;
  else
    update public.erp_reversal_operations
    set status='processing',reason=p_reason,requested_by=auth.uid(),requested_at=v_now
    where id=v_operation_id;
  end if;

  -- Existing RPCs execute inside this same database transaction.
  v_invoice_result := public.erp_reverse_invoice_cloud(
    p_organization_id,p_module,p_invoice_id,p_reason
  );

  for v_document in
    select distinct reference_id as document_id
    from public.erp_cloud_inventory_movements
    where organization_id=p_organization_id
      and module=p_module
      and workflow_id=v_workflow_id
      and reference_type=case when p_module='sales' then 'sales_delivery' else 'purchase_receipt' end
      and source_movement_id not like 'REV:%'
  loop
    v_inventory_result := public.erp_reverse_inventory_document_cloud(
      p_organization_id,p_module,v_document.document_id,p_reason
    );
    v_inventory_results := v_inventory_results||jsonb_build_array(v_inventory_result);
  end loop;

  -- Preserve the approved order while closing dependent documents.
  if p_module='sales' then
    update public.erp_sales_workflows
    set aggregate=jsonb_set(
          jsonb_set(aggregate,'{order,status}','"approved"'::jsonb,true),
          '{reversal}',jsonb_build_object(
            'status','committed','operationId',v_operation_id,'reason',p_reason,'at',v_now
          ),true
        ),
        version=version+1,updated_at=v_now,updated_by=auth.uid()
    where organization_id=p_organization_id and workflow_id=v_workflow_id;
  else
    update public.erp_purchase_workflows
    set aggregate=jsonb_set(
          jsonb_set(aggregate,'{order,status}','"approved"'::jsonb,true),
          '{reversal}',jsonb_build_object(
            'status','committed','operationId',v_operation_id,'reason',p_reason,'at',v_now
          ),true
        ),
        version=version+1,updated_at=v_now,updated_by=auth.uid()
    where organization_id=p_organization_id and workflow_id=v_workflow_id;
  end if;

  v_result := jsonb_build_object(
    'operationId',v_operation_id,
    'workflowId',v_workflow_id,
    'invoice',v_invoice_result,
    'inventory',v_inventory_results,
    'duplicate',false
  );

  update public.erp_reversal_operations
  set status='committed',result=v_result,committed_at=v_now
  where id=v_operation_id;

  return v_result;
exception when others then
  -- The surrounding PostgreSQL transaction rolls back all financial and inventory changes.
  raise;
end;
$$;

grant execute on function public.erp_reverse_workflow_cloud(uuid,text,text,text) to authenticated;
