-- Quality Line ERP v17.7.0
-- Normalized cloud chart of accounts, partner ledger bindings, and item costs.

create table if not exists public.erp_accounts (
  organization_id uuid not null references public.companies(id) on delete cascade,
  account_id text not null,
  code text not null,
  name text not null,
  account_type text not null,
  parent_account_id text,
  currency text not null,
  opening_balance numeric(20,4) not null default 0,
  is_active boolean not null default true,
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  synced_by uuid references auth.users(id),
  primary key (organization_id, account_id),
  unique (organization_id, code)
);

create table if not exists public.erp_partner_accounts (
  organization_id uuid not null references public.companies(id) on delete cascade,
  partner_type text not null check (partner_type in ('customer','supplier')),
  partner_id text not null,
  partner_name text,
  usd_account_id text,
  iqd_account_id text,
  is_active boolean not null default true,
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  synced_by uuid references auth.users(id),
  primary key (organization_id, partner_type, partner_id)
);

create table if not exists public.erp_item_costs (
  organization_id uuid not null references public.companies(id) on delete cascade,
  item_type text not null check (item_type in ('car','product')),
  item_id text not null,
  item_name text,
  currency text not null,
  purchase_cost numeric(20,4) not null default 0,
  landed_cost numeric(20,4) not null default 0,
  maintenance_cost numeric(20,4) not null default 0,
  unit_cost numeric(20,4) not null default 0,
  sale_price numeric(20,4) not null default 0,
  is_active boolean not null default true,
  source_updated_at timestamptz,
  synced_at timestamptz not null default now(),
  synced_by uuid references auth.users(id),
  primary key (organization_id, item_type, item_id),
  check (purchase_cost >= 0 and landed_cost >= 0 and maintenance_cost >= 0 and unit_cost >= 0)
);

create index if not exists erp_partner_accounts_lookup_idx
  on public.erp_partner_accounts (organization_id, partner_type, partner_id);
create index if not exists erp_item_costs_lookup_idx
  on public.erp_item_costs (organization_id, item_type, item_id);

alter table public.erp_accounts enable row level security;
alter table public.erp_partner_accounts enable row level security;
alter table public.erp_item_costs enable row level security;

drop policy if exists erp_accounts_select on public.erp_accounts;
create policy erp_accounts_select on public.erp_accounts
for select to authenticated
using (public.is_active_company_member(organization_id));

drop policy if exists erp_partner_accounts_select on public.erp_partner_accounts;
create policy erp_partner_accounts_select on public.erp_partner_accounts
for select to authenticated
using (public.is_active_company_member(organization_id));

drop policy if exists erp_item_costs_select on public.erp_item_costs;
create policy erp_item_costs_select on public.erp_item_costs
for select to authenticated
using (public.is_active_company_member(organization_id));

revoke insert, update, delete on public.erp_accounts from anon, authenticated;
revoke insert, update, delete on public.erp_partner_accounts from anon, authenticated;
revoke insert, update, delete on public.erp_item_costs from anon, authenticated;

grant select on public.erp_accounts to authenticated;
grant select on public.erp_partner_accounts to authenticated;
grant select on public.erp_item_costs to authenticated;

create or replace function public.erp_sync_accounting_master_data(
  p_organization_id uuid,
  p_accounts jsonb,
  p_partner_accounts jsonb,
  p_item_costs jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account jsonb;
  v_partner jsonb;
  v_item jsonb;
  v_accounts_count integer := 0;
  v_partners_count integer := 0;
  v_items_count integer := 0;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not public.is_active_company_member(p_organization_id) then
    raise exception 'company_membership_required';
  end if;

  for v_account in select value from jsonb_array_elements(coalesce(p_accounts, '[]'::jsonb)) loop
    insert into public.erp_accounts(
      organization_id, account_id, code, name, account_type,
      parent_account_id, currency, opening_balance, is_active,
      source_updated_at, synced_at, synced_by
    ) values (
      p_organization_id,
      v_account->>'id',
      v_account->>'code',
      v_account->>'name',
      v_account->>'type',
      nullif(v_account->>'parentId',''),
      coalesce(nullif(v_account->>'currency',''),'USD'),
      coalesce((v_account->>'openingBalance')::numeric,0),
      coalesce((v_account->>'isActive')::boolean,true),
      nullif(v_account->>'updatedAt','')::timestamptz,
      now(), auth.uid()
    )
    on conflict (organization_id, account_id) do update set
      code = excluded.code,
      name = excluded.name,
      account_type = excluded.account_type,
      parent_account_id = excluded.parent_account_id,
      currency = excluded.currency,
      opening_balance = excluded.opening_balance,
      is_active = excluded.is_active,
      source_updated_at = excluded.source_updated_at,
      synced_at = now(),
      synced_by = auth.uid();
    v_accounts_count := v_accounts_count + 1;
  end loop;

  for v_partner in select value from jsonb_array_elements(coalesce(p_partner_accounts, '[]'::jsonb)) loop
    insert into public.erp_partner_accounts(
      organization_id, partner_type, partner_id, partner_name,
      usd_account_id, iqd_account_id, is_active,
      source_updated_at, synced_at, synced_by
    ) values (
      p_organization_id,
      v_partner->>'partnerType',
      v_partner->>'id',
      v_partner->>'name',
      nullif(v_partner->>'accountIdUsd',''),
      nullif(v_partner->>'accountIdIqd',''),
      coalesce((v_partner->>'isActive')::boolean,true),
      nullif(v_partner->>'updatedAt','')::timestamptz,
      now(), auth.uid()
    )
    on conflict (organization_id, partner_type, partner_id) do update set
      partner_name = excluded.partner_name,
      usd_account_id = excluded.usd_account_id,
      iqd_account_id = excluded.iqd_account_id,
      is_active = excluded.is_active,
      source_updated_at = excluded.source_updated_at,
      synced_at = now(),
      synced_by = auth.uid();
    v_partners_count := v_partners_count + 1;
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_item_costs, '[]'::jsonb)) loop
    insert into public.erp_item_costs(
      organization_id, item_type, item_id, item_name, currency,
      purchase_cost, landed_cost, maintenance_cost, unit_cost,
      sale_price, is_active, source_updated_at, synced_at, synced_by
    ) values (
      p_organization_id,
      v_item->>'itemType',
      v_item->>'id',
      v_item->>'name',
      coalesce(nullif(v_item->>'currency',''),'USD'),
      coalesce((v_item->>'purchaseCost')::numeric,0),
      coalesce((v_item->>'landedCost')::numeric,0),
      coalesce((v_item->>'maintenanceCost')::numeric,0),
      coalesce((v_item->>'unitCost')::numeric,0),
      coalesce((v_item->>'salePrice')::numeric,0),
      coalesce((v_item->>'isActive')::boolean,true),
      nullif(v_item->>'updatedAt','')::timestamptz,
      now(), auth.uid()
    )
    on conflict (organization_id, item_type, item_id) do update set
      item_name = excluded.item_name,
      currency = excluded.currency,
      purchase_cost = excluded.purchase_cost,
      landed_cost = excluded.landed_cost,
      maintenance_cost = excluded.maintenance_cost,
      unit_cost = excluded.unit_cost,
      sale_price = excluded.sale_price,
      is_active = excluded.is_active,
      source_updated_at = excluded.source_updated_at,
      synced_at = now(),
      synced_by = auth.uid();
    v_items_count := v_items_count + 1;
  end loop;

  return jsonb_build_object(
    'accounts', v_accounts_count,
    'partnerAccounts', v_partners_count,
    'itemCosts', v_items_count,
    'syncedAt', now()
  );
end;
$$;

grant execute on function public.erp_sync_accounting_master_data(uuid,jsonb,jsonb,jsonb) to authenticated;

-- Read-only realtime projections for accounting administration screens.
do $$ begin
  alter publication supabase_realtime add table public.erp_accounts;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.erp_partner_accounts;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.erp_item_costs;
exception when duplicate_object then null; end $$;
