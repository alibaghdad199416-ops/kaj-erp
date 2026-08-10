-- Quality Line ERP v17 P2: normalized PostgreSQL master data.
begin;

create table if not exists public.erp_cars (
  company_id uuid not null references public.companies(id) on delete cascade,
  id text not null,
  data jsonb not null,
  version bigint not null default 1,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id, id)
);
create table if not exists public.erp_customers (like public.erp_cars including all);
create table if not exists public.erp_suppliers (like public.erp_cars including all);

create index if not exists erp_cars_updated_idx on public.erp_cars(company_id, updated_at desc);
create unique index if not exists erp_cars_company_chassis_key on public.erp_cars(company_id, lower(btrim(data->>'chassis'))) where coalesce(btrim(data->>'chassis'),'') <> '';
create unique index if not exists erp_cars_company_plate_key on public.erp_cars(company_id, lower(btrim(data->>'plate_number'))) where coalesce(btrim(data->>'plate_number'),'') <> '';
create index if not exists erp_customers_updated_idx on public.erp_customers(company_id, updated_at desc);
create index if not exists erp_suppliers_updated_idx on public.erp_suppliers(company_id, updated_at desc);

create or replace function public.is_active_company_member(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.company_memberships m
    where m.company_id = p_company_id
      and m.user_id = auth.uid()
      and m.is_active
  );
$$;

create or replace function public.can_manage_master_data(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.company_memberships m
    where m.company_id = p_company_id
      and m.user_id = auth.uid()
      and m.is_active
      and (m.is_system_admin or m.role_code in ('admin','manager','sales','warehouse','accountant'))
  );
$$;

alter table public.erp_cars enable row level security;
alter table public.erp_customers enable row level security;
alter table public.erp_suppliers enable row level security;

-- Recreate compact policies for every normalized master table.
do $$
declare t text;
begin
  foreach t in array array['erp_cars','erp_customers','erp_suppliers'] loop
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('drop policy if exists %I_delete on public.%I', t, t);
    execute format('create policy %I_select on public.%I for select to authenticated using (public.is_active_company_member(company_id))', t, t);
    execute format('create policy %I_insert on public.%I for insert to authenticated with check (public.can_manage_master_data(company_id) and created_by = auth.uid() and updated_by = auth.uid())', t, t);
    execute format('create policy %I_update on public.%I for update to authenticated using (public.can_manage_master_data(company_id)) with check (public.can_manage_master_data(company_id) and updated_by = auth.uid())', t, t);
    execute format('create policy %I_delete on public.%I for delete to authenticated using (public.can_manage_master_data(company_id))', t, t);
  end loop;
end $$;

grant select, insert, update, delete on public.erp_cars, public.erp_customers, public.erp_suppliers to authenticated;

create table if not exists public.erp_master_audit_log (
  id bigint generated always as identity primary key,
  company_id uuid not null,
  table_name text not null,
  record_id text not null,
  operation text not null,
  old_data jsonb,
  new_data jsonb,
  changed_by uuid references auth.users(id),
  changed_at timestamptz not null default now()
);
alter table public.erp_master_audit_log enable row level security;
drop policy if exists erp_master_audit_log_select on public.erp_master_audit_log;
create policy erp_master_audit_log_select on public.erp_master_audit_log
for select to authenticated using (public.is_active_company_member(company_id));
grant select on public.erp_master_audit_log to authenticated;

create or replace function public.erp_master_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    new.version := 1;
  else
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

create or replace function public.erp_master_write_audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_company_id uuid;
  v_record_id text;
begin
  if tg_op = 'DELETE' then
    v_company_id := old.company_id;
    v_record_id := old.id;
  else
    v_company_id := new.company_id;
    v_record_id := new.id;
  end if;

  insert into public.erp_master_audit_log(
    company_id, table_name, record_id, operation, old_data, new_data, changed_by
  ) values (
    v_company_id, tg_table_name, v_record_id, tg_op,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end,
    auth.uid()
  );

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['erp_cars','erp_customers','erp_suppliers'] loop
    execute format('drop trigger if exists %I_before_write on public.%I', t, t);
    execute format('create trigger %I_before_write before insert or update on public.%I for each row execute function public.erp_master_before_write()', t, t);
    execute format('drop trigger if exists %I_audit on public.%I', t, t);
    execute format('create trigger %I_audit after insert or update or delete on public.%I for each row execute function public.erp_master_write_audit()', t, t);
  end loop;
end $$;


-- Add the normalized tables to Realtime publication when available.
do $$ begin
  alter publication supabase_realtime add table public.erp_cars;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.erp_customers;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.erp_suppliers;
exception when duplicate_object then null; when undefined_object then null; end $$;

commit;
