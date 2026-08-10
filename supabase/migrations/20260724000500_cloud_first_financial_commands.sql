create table if not exists public.erp_financial_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  module text not null check (module in ('sales','purchases')),
  workflow_id text not null,
  event_type text not null,
  idempotency_key text not null,
  status text not null default 'reserved' check (status in ('reserved','committed','aborted')),
  expected_version bigint,
  request_payload jsonb not null default '{}'::jsonb,
  result_payload jsonb,
  error_message text,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  committed_at timestamptz,
  aborted_at timestamptz,
  unique (organization_id, idempotency_key)
);

create index if not exists erp_financial_commands_lookup_idx
  on public.erp_financial_commands (organization_id, module, workflow_id, status);

alter table public.erp_financial_commands enable row level security;

drop policy if exists erp_financial_commands_select on public.erp_financial_commands;
create policy erp_financial_commands_select
on public.erp_financial_commands for select to authenticated
using (public.is_active_company_member(organization_id));

revoke insert, update, delete on public.erp_financial_commands from anon, authenticated;

create or replace function public.erp_begin_financial_command(
  p_organization_id uuid,
  p_module text,
  p_workflow_id text,
  p_event_type text,
  p_idempotency_key text,
  p_request_payload jsonb default '{}'::jsonb,
  p_expected_version bigint default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_status text;
  v_version bigint;
begin
  if p_organization_id is null or not public.is_active_company_member(p_organization_id) then
    raise exception 'tenant_not_resolved';
  end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;
  if not (public.has_company_role(p_organization_id, 'admin')
          or public.has_company_role(p_organization_id, 'accountant')
          or public.has_company_role(p_organization_id, 'sales')) then
    raise exception 'permission_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'idempotency_key_required';
  end if;

  select id, status into v_id, v_status
  from public.erp_financial_commands
  where organization_id = p_organization_id
    and idempotency_key = p_idempotency_key;

  if v_id is not null then
    return jsonb_build_object('commandId', v_id, 'status', v_status, 'duplicate', true);
  end if;

  if p_module = 'sales' then
    select version into v_version from public.erp_sales_workflows
      where organization_id = p_organization_id and workflow_id = p_workflow_id for update;
  else
    select version into v_version from public.erp_purchase_workflows
      where organization_id = p_organization_id and workflow_id = p_workflow_id for update;
  end if;

  if v_version is null then raise exception 'workflow_not_found'; end if;
  if p_expected_version is not null and v_version <> p_expected_version then
    raise exception 'record_conflict';
  end if;

  insert into public.erp_financial_commands(
    organization_id,module,workflow_id,event_type,idempotency_key,
    expected_version,request_payload,created_by
  ) values (
    p_organization_id,p_module,p_workflow_id,p_event_type,p_idempotency_key,
    v_version,p_request_payload,auth.uid()
  ) returning id into v_id;

  return jsonb_build_object('commandId', v_id, 'status', 'reserved', 'duplicate', false, 'version', v_version);
end;
$$;

create or replace function public.erp_commit_financial_command(
  p_command_id uuid,
  p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cmd public.erp_financial_commands%rowtype;
  v_result jsonb;
begin
  select * into v_cmd from public.erp_financial_commands where id = p_command_id for update;
  if not found then raise exception 'financial_command_not_found'; end if;
  if not public.is_active_company_member(v_cmd.organization_id) then raise exception 'permission_denied'; end if;

  if v_cmd.status = 'committed' then
    return coalesce(v_cmd.result_payload, jsonb_build_object('commandId', v_cmd.id, 'status', 'committed', 'duplicate', true));
  end if;
  if v_cmd.status = 'aborted' then raise exception 'financial_command_aborted'; end if;

  select public.erp_post_financial_event(
    v_cmd.organization_id,
    v_cmd.module,
    v_cmd.workflow_id,
    v_cmd.event_type,
    v_cmd.idempotency_key,
    p_payload,
    v_cmd.expected_version
  ) into v_result;

  update public.erp_financial_commands
  set status = 'committed', result_payload = v_result, committed_at = now(), error_message = null
  where id = v_cmd.id;

  return v_result || jsonb_build_object('commandId', v_cmd.id, 'status', 'committed');
end;
$$;

create or replace function public.erp_abort_financial_command(
  p_command_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_status text;
begin
  select organization_id, status into v_org, v_status
  from public.erp_financial_commands where id = p_command_id for update;
  if v_org is null then return; end if;
  if not public.is_active_company_member(v_org) then raise exception 'permission_denied'; end if;
  if v_status = 'committed' then raise exception 'financial_command_already_committed'; end if;
  update public.erp_financial_commands
  set status = 'aborted', error_message = p_reason, aborted_at = now()
  where id = p_command_id;
end;
$$;

grant execute on function public.erp_begin_financial_command(uuid,text,text,text,text,jsonb,bigint) to authenticated;
grant execute on function public.erp_commit_financial_command(uuid,jsonb) to authenticated;
grant execute on function public.erp_abort_financial_command(uuid,text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.erp_financial_commands;
exception when duplicate_object then null;
end $$;
