-- Compatibility helpers for the ERP company membership model.
create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.company_id
  from public.company_memberships m
  join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid()
    and m.is_active
    and c.is_active
  order by m.is_system_admin desc, m.created_at asc
  limit 1;
$$;

create or replace function public.has_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    where m.user_id = auth.uid()
      and m.company_id = public.current_organization_id()
      and m.is_active
      and (m.is_system_admin or m.role_code = p_role)
  );
$$;

create table if not exists public.erp_sales_workflows (
  organization_id uuid not null,
  workflow_id text not null,
  aggregate jsonb not null default '{}'::jsonb,
  version bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (organization_id, workflow_id)
);

create table if not exists public.erp_purchase_workflows (
  organization_id uuid not null,
  workflow_id text not null,
  aggregate jsonb not null default '{}'::jsonb,
  version bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (organization_id, workflow_id)
);

create table if not exists public.erp_financial_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  module text not null check (module in ('sales','purchases')),
  workflow_id text not null,
  event_type text not null,
  idempotency_key text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (organization_id, idempotency_key)
);

alter table public.erp_sales_workflows enable row level security;
alter table public.erp_purchase_workflows enable row level security;
alter table public.erp_financial_events enable row level security;

create policy erp_sales_workflows_company on public.erp_sales_workflows
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy erp_purchase_workflows_company on public.erp_purchase_workflows
for all to authenticated
using (organization_id = public.current_organization_id())
with check (organization_id = public.current_organization_id());

create policy erp_financial_events_company on public.erp_financial_events
for select to authenticated
using (organization_id = public.current_organization_id());

create or replace function public.erp_post_financial_event(
  p_module text,
  p_workflow_id text,
  p_event_type text,
  p_idempotency_key text,
  p_payload jsonb,
  p_expected_version bigint default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := public.current_organization_id();
  v_version bigint;
  v_table regclass;
begin
  if v_org is null then raise exception 'tenant_not_resolved'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;
  if not (public.has_role('admin') or public.has_role('accountant') or public.has_role('sales')) then
    raise exception 'permission_denied';
  end if;

  if exists(select 1 from public.erp_financial_events where organization_id=v_org and idempotency_key=p_idempotency_key) then
    return jsonb_build_object('duplicate', true);
  end if;

  if p_module = 'sales' then
    select version into v_version from public.erp_sales_workflows
      where organization_id=v_org and workflow_id=p_workflow_id for update;
  else
    select version into v_version from public.erp_purchase_workflows
      where organization_id=v_org and workflow_id=p_workflow_id for update;
  end if;

  if v_version is null then raise exception 'workflow_not_found'; end if;
  if p_expected_version is not null and v_version <> p_expected_version then
    raise exception 'record_conflict';
  end if;

  insert into public.erp_financial_events(
    organization_id,module,workflow_id,event_type,idempotency_key,payload,created_by
  ) values (v_org,p_module,p_workflow_id,p_event_type,p_idempotency_key,p_payload,auth.uid());

  if p_module = 'sales' then
    update public.erp_sales_workflows
      set aggregate = aggregate || jsonb_build_object('lastFinancialEvent', p_payload),
          version = version + 1, updated_at=now(), updated_by=auth.uid()
      where organization_id=v_org and workflow_id=p_workflow_id
      returning version into v_version;
  else
    update public.erp_purchase_workflows
      set aggregate = aggregate || jsonb_build_object('lastFinancialEvent', p_payload),
          version = version + 1, updated_at=now(), updated_by=auth.uid()
      where organization_id=v_org and workflow_id=p_workflow_id
      returning version into v_version;
  end if;

  return jsonb_build_object('duplicate', false, 'version', v_version);
end;
$$;

grant execute on function public.erp_post_financial_event(text,text,text,text,jsonb,bigint) to authenticated;

alter publication supabase_realtime add table public.erp_sales_workflows;
alter publication supabase_realtime add table public.erp_purchase_workflows;
alter publication supabase_realtime add table public.erp_financial_events;
