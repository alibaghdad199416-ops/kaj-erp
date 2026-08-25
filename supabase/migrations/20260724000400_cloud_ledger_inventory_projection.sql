-- Quality Line ERP v17.4.0
-- Atomically projects ERP journal entries, journal lines, inventory movements,
-- and stock snapshots into PostgreSQL as part of the financial-event RPC.


create or replace function public.has_company_role(p_company_id uuid, p_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    where m.user_id = auth.uid()
      and m.company_id = p_company_id
      and m.is_active
      and c.is_active
      and (m.is_system_admin or m.role_code = p_role)
  );
$$;


-- Replace the transitional single-membership policies with selected-company-aware policies.
drop policy if exists erp_sales_workflows_company on public.erp_sales_workflows;
create policy erp_sales_workflows_company on public.erp_sales_workflows
for all to authenticated
using (public.is_active_company_member(organization_id))
with check (public.is_active_company_member(organization_id));

drop policy if exists erp_purchase_workflows_company on public.erp_purchase_workflows;
create policy erp_purchase_workflows_company on public.erp_purchase_workflows
for all to authenticated
using (public.is_active_company_member(organization_id))
with check (public.is_active_company_member(organization_id));

drop policy if exists erp_financial_events_company on public.erp_financial_events;
create policy erp_financial_events_company on public.erp_financial_events
for select to authenticated
using (public.is_active_company_member(organization_id));

create table if not exists public.erp_cloud_journal_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.companies(id) on delete cascade,
  financial_event_id uuid not null references public.erp_financial_events(id) on delete restrict,
  module text not null check (module in ('sales', 'purchases')),
  workflow_id text not null,
  source_entry_id text not null,
  entry_number text not null,
  entry_date timestamptz not null,
  description text not null,
  currency text not null,
  reference_type text,
  reference_id text,
  total_debit numeric(20,4) not null,
  total_credit numeric(20,4) not null,
  status text not null default 'posted',
  posted_by uuid references auth.users(id),
  posted_at timestamptz not null default now(),
  unique (organization_id, source_entry_id),
  check (abs(total_debit - total_credit) <= 0.01)
);

create table if not exists public.erp_cloud_journal_lines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.companies(id) on delete cascade,
  entry_id uuid not null references public.erp_cloud_journal_entries(id) on delete cascade,
  source_line_id text not null,
  line_number integer not null,
  account_id text not null,
  account_code text not null,
  account_name text not null,
  debit numeric(20,4) not null default 0,
  credit numeric(20,4) not null default 0,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  unique (organization_id, source_line_id),
  check (debit >= 0 and credit >= 0),
  check (not (debit > 0 and credit > 0))
);

create table if not exists public.erp_cloud_inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.companies(id) on delete cascade,
  financial_event_id uuid not null references public.erp_financial_events(id) on delete restrict,
  module text not null check (module in ('sales', 'purchases')),
  workflow_id text not null,
  source_movement_id text not null,
  movement_number text not null,
  product_id text not null,
  warehouse_id text not null,
  movement_type text not null,
  quantity numeric(20,4) not null,
  unit_cost numeric(20,4) not null default 0,
  total_cost numeric(20,4) not null default 0,
  reference_type text,
  reference_id text,
  movement_date timestamptz not null,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, source_movement_id)
);

create table if not exists public.erp_cloud_stock_balances (
  organization_id uuid not null references public.companies(id) on delete cascade,
  warehouse_id text not null,
  product_id text not null,
  quantity numeric(20,4) not null default 0,
  minimum_quantity numeric(20,4) not null default 0,
  reserved_quantity numeric(20,4) not null default 0,
  expected_incoming numeric(20,4) not null default 0,
  expected_outgoing numeric(20,4) not null default 0,
  average_unit_cost numeric(20,4) not null default 0,
  source_updated_at timestamptz,
  synchronized_by uuid references auth.users(id),
  synchronized_at timestamptz not null default now(),
  primary key (organization_id, warehouse_id, product_id)
);

create index if not exists erp_cloud_journal_entries_workflow_idx
  on public.erp_cloud_journal_entries (organization_id, module, workflow_id);
create index if not exists erp_cloud_inventory_movements_workflow_idx
  on public.erp_cloud_inventory_movements (organization_id, module, workflow_id);
create index if not exists erp_cloud_stock_balances_product_idx
  on public.erp_cloud_stock_balances (organization_id, product_id);

alter table public.erp_cloud_journal_entries enable row level security;
alter table public.erp_cloud_journal_lines enable row level security;
alter table public.erp_cloud_inventory_movements enable row level security;
alter table public.erp_cloud_stock_balances enable row level security;

drop policy if exists erp_cloud_journal_entries_select on public.erp_cloud_journal_entries;
create policy erp_cloud_journal_entries_select
on public.erp_cloud_journal_entries for select to authenticated
using (public.is_active_company_member(organization_id));

drop policy if exists erp_cloud_journal_lines_select on public.erp_cloud_journal_lines;
create policy erp_cloud_journal_lines_select
on public.erp_cloud_journal_lines for select to authenticated
using (public.is_active_company_member(organization_id));

drop policy if exists erp_cloud_inventory_movements_select on public.erp_cloud_inventory_movements;
create policy erp_cloud_inventory_movements_select
on public.erp_cloud_inventory_movements for select to authenticated
using (public.is_active_company_member(organization_id));

drop policy if exists erp_cloud_stock_balances_select on public.erp_cloud_stock_balances;
create policy erp_cloud_stock_balances_select
on public.erp_cloud_stock_balances for select to authenticated
using (public.is_active_company_member(organization_id));

revoke insert, update, delete on public.erp_cloud_journal_entries from anon, authenticated;
revoke insert, update, delete on public.erp_cloud_journal_lines from anon, authenticated;
revoke insert, update, delete on public.erp_cloud_inventory_movements from anon, authenticated;
revoke insert, update, delete on public.erp_cloud_stock_balances from anon, authenticated;

drop function if exists public.erp_post_financial_event(text,text,text,text,jsonb,bigint);

create or replace function public.erp_post_financial_event(
  p_organization_id uuid,
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
  v_org uuid := p_organization_id;
  v_version bigint;
  v_event_id uuid;
  v_entry_id uuid;
  v_entry jsonb := p_payload -> 'journalEntry';
  v_line jsonb;
  v_movement jsonb;
  v_stock jsonb;
  v_line_number integer := 0;
  v_lines_debit numeric(20,4) := 0;
  v_lines_credit numeric(20,4) := 0;
  v_total_debit numeric(20,4);
  v_total_credit numeric(20,4);
begin
  if v_org is null or not public.is_active_company_member(v_org) then
    raise exception 'tenant_not_resolved';
  end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;
  if not (public.has_company_role(v_org, 'admin')
          or public.has_company_role(v_org, 'accountant')
          or public.has_company_role(v_org, 'sales')) then
    raise exception 'permission_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'idempotency_key_required';
  end if;

  select id into v_event_id
  from public.erp_financial_events
  where organization_id = v_org and idempotency_key = p_idempotency_key;
  if v_event_id is not null then
    return jsonb_build_object('duplicate', true, 'eventId', v_event_id);
  end if;

  if p_module = 'sales' then
    select version into v_version from public.erp_sales_workflows
      where organization_id = v_org and workflow_id = p_workflow_id for update;
  else
    select version into v_version from public.erp_purchase_workflows
      where organization_id = v_org and workflow_id = p_workflow_id for update;
  end if;

  if v_version is null then raise exception 'workflow_not_found'; end if;
  if p_expected_version is not null and v_version <> p_expected_version then
    raise exception 'record_conflict';
  end if;

  insert into public.erp_financial_events(
    organization_id,module,workflow_id,event_type,idempotency_key,payload,created_by
  ) values (v_org,p_module,p_workflow_id,p_event_type,p_idempotency_key,p_payload,auth.uid())
  returning id into v_event_id;

  if v_entry is not null and jsonb_typeof(v_entry) = 'object'
     and jsonb_typeof(coalesce(p_payload -> 'journalLines', '[]'::jsonb)) = 'array'
     and jsonb_array_length(coalesce(p_payload -> 'journalLines', '[]'::jsonb)) > 0 then
    v_total_debit := coalesce((v_entry ->> 'totalDebit')::numeric, 0);
    v_total_credit := coalesce((v_entry ->> 'totalCredit')::numeric, 0);

    for v_line in select value from jsonb_array_elements(p_payload -> 'journalLines') loop
      v_lines_debit := v_lines_debit + coalesce((v_line ->> 'debit')::numeric, 0);
      v_lines_credit := v_lines_credit + coalesce((v_line ->> 'credit')::numeric, 0);
    end loop;

    if abs(v_total_debit - v_total_credit) > 0.01
       or abs(v_lines_debit - v_lines_credit) > 0.01
       or abs(v_total_debit - v_lines_debit) > 0.01 then
      raise exception 'unbalanced_cloud_journal';
    end if;

    insert into public.erp_cloud_journal_entries(
      organization_id, financial_event_id, module, workflow_id,
      source_entry_id, entry_number, entry_date, description, currency,
      reference_type, reference_id, total_debit, total_credit, status, posted_by
    ) values (
      v_org, v_event_id, p_module, p_workflow_id,
      v_entry ->> 'id', v_entry ->> 'entryNumber',
      coalesce((v_entry ->> 'entryDate')::timestamptz, now()),
      coalesce(v_entry ->> 'description', p_event_type),
      coalesce(v_entry ->> 'currency', 'USD'),
      v_entry ->> 'referenceType', v_entry ->> 'referenceId',
      v_total_debit, v_total_credit,
      coalesce(v_entry ->> 'status', 'posted'), auth.uid()
    )
    on conflict (organization_id, source_entry_id) do update set
      financial_event_id = excluded.financial_event_id,
      description = excluded.description,
      total_debit = excluded.total_debit,
      total_credit = excluded.total_credit,
      status = excluded.status
    returning id into v_entry_id;

    v_line_number := 0;
    for v_line in select value from jsonb_array_elements(p_payload -> 'journalLines') loop
      v_line_number := v_line_number + 1;
      insert into public.erp_cloud_journal_lines(
        organization_id, entry_id, source_line_id, line_number,
        account_id, account_code, account_name, debit, credit, description, metadata
      ) values (
        v_org, v_entry_id, v_line ->> 'id', v_line_number,
        coalesce(v_line ->> 'accountId', ''),
        coalesce(v_line ->> 'accountCode', ''),
        coalesce(v_line ->> 'accountName', ''),
        coalesce((v_line ->> 'debit')::numeric, 0),
        coalesce((v_line ->> 'credit')::numeric, 0),
        v_line ->> 'description', v_line
      )
      on conflict (organization_id, source_line_id) do update set
        entry_id = excluded.entry_id,
        line_number = excluded.line_number,
        account_id = excluded.account_id,
        account_code = excluded.account_code,
        account_name = excluded.account_name,
        debit = excluded.debit,
        credit = excluded.credit,
        description = excluded.description,
        metadata = excluded.metadata;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_payload -> 'inventoryMovements', '[]'::jsonb)) = 'array' then
    for v_movement in select value from jsonb_array_elements(p_payload -> 'inventoryMovements') loop
      insert into public.erp_cloud_inventory_movements(
        organization_id, financial_event_id, module, workflow_id,
        source_movement_id, movement_number, product_id, warehouse_id,
        movement_type, quantity, unit_cost, total_cost, reference_type,
        reference_id, movement_date, notes, created_by
      ) values (
        v_org, v_event_id, p_module, p_workflow_id,
        v_movement ->> 'id', v_movement ->> 'movementNumber',
        v_movement ->> 'productId', v_movement ->> 'warehouseId',
        v_movement ->> 'movementType',
        coalesce((v_movement ->> 'quantity')::numeric, 0),
        coalesce((v_movement ->> 'unitCost')::numeric, 0),
        coalesce((v_movement ->> 'totalCost')::numeric, 0),
        v_movement ->> 'referenceType', v_movement ->> 'referenceId',
        coalesce((v_movement ->> 'movementDate')::timestamptz, now()),
        v_movement ->> 'notes', auth.uid()
      )
      on conflict (organization_id, source_movement_id) do update set
        financial_event_id = excluded.financial_event_id,
        quantity = excluded.quantity,
        unit_cost = excluded.unit_cost,
        total_cost = excluded.total_cost,
        notes = excluded.notes;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_payload -> 'stockSnapshots', '[]'::jsonb)) = 'array' then
    for v_stock in select value from jsonb_array_elements(p_payload -> 'stockSnapshots') loop
      insert into public.erp_cloud_stock_balances(
        organization_id, warehouse_id, product_id, quantity, minimum_quantity,
        reserved_quantity, expected_incoming, expected_outgoing, average_unit_cost,
        source_updated_at, synchronized_by
      ) values (
        v_org, v_stock ->> 'warehouseId', v_stock ->> 'productId',
        coalesce((v_stock ->> 'quantity')::numeric, 0),
        coalesce((v_stock ->> 'minimumQuantity')::numeric, 0),
        coalesce((v_stock ->> 'reservedQuantity')::numeric, 0),
        coalesce((v_stock ->> 'expectedIncoming')::numeric, 0),
        coalesce((v_stock ->> 'expectedOutgoing')::numeric, 0),
        coalesce((v_stock ->> 'averageUnitCost')::numeric, 0),
        nullif(v_stock ->> 'updatedAt', '')::timestamptz, auth.uid()
      )
      on conflict (organization_id, warehouse_id, product_id) do update set
        quantity = excluded.quantity,
        minimum_quantity = excluded.minimum_quantity,
        reserved_quantity = excluded.reserved_quantity,
        expected_incoming = excluded.expected_incoming,
        expected_outgoing = excluded.expected_outgoing,
        average_unit_cost = excluded.average_unit_cost,
        source_updated_at = excluded.source_updated_at,
        synchronized_by = excluded.synchronized_by,
        synchronized_at = now();
    end loop;
  end if;

  if p_module = 'sales' then
    update public.erp_sales_workflows
      set aggregate = aggregate || jsonb_build_object(
            'lastFinancialEvent', p_payload,
            'cloudLedgerEventId', v_event_id
          ),
          version = version + 1, updated_at = now(), updated_by = auth.uid()
      where organization_id = v_org and workflow_id = p_workflow_id
      returning version into v_version;
  else
    update public.erp_purchase_workflows
      set aggregate = aggregate || jsonb_build_object(
            'lastFinancialEvent', p_payload,
            'cloudLedgerEventId', v_event_id
          ),
          version = version + 1, updated_at = now(), updated_by = auth.uid()
      where organization_id = v_org and workflow_id = p_workflow_id
      returning version into v_version;
  end if;

  return jsonb_build_object(
    'duplicate', false,
    'eventId', v_event_id,
    'journalEntryId', v_entry_id,
    'version', v_version
  );
end;
$$;

grant execute on function public.erp_post_financial_event(uuid,text,text,text,text,jsonb,bigint)
  to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.erp_cloud_journal_entries;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.erp_cloud_inventory_movements;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.erp_cloud_stock_balances;
exception when duplicate_object then null;
end $$;
