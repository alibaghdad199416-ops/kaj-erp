-- Quality Line ERP 18.0.0
-- Core ERP schema hardening, Supabase identity, tenant RLS and diagnostics.

begin;

create or replace function public.is_active_company_member(
  p_company_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    where m.company_id = p_company_id
      and m.user_uid = public.current_external_uid()
      and m.is_active
  );
$$;

create or replace function public.is_active_company_member(
  p_company_id text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    where m.company_id::text = p_company_id
      and m.user_uid = public.current_external_uid()
      and m.is_active
  );
$$;

create or replace function public.can_manage_master_data(
  p_company_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    where m.company_id = p_company_id
      and m.user_uid = public.current_external_uid()
      and m.is_active
      and (
        m.is_system_admin
        or m.role_code in (
          'owner',
          'admin',
          'manager',
          'sales',
          'warehouse',
          'accountant'
        )
      )
  );
$$;

create or replace function public.can_manage_master_data(
  p_company_id text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    where m.company_id::text = p_company_id
      and m.user_uid = public.current_external_uid()
      and m.is_active
      and (
        m.is_system_admin
        or m.role_code in (
          'owner',
          'admin',
          'manager',
          'sales',
          'warehouse',
          'accountant'
        )
      )
  );
$$;

-- Ensure every ERP tenant table has useful tenant/time indexes and strict RLS.
do $$
declare
  r record;
  policy_name text;
begin
  for r in
    select distinct
      c.table_name,
      c.data_type as company_id_data_type,
      c.udt_name as company_id_udt_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema = c.table_schema
     and t.table_name = c.table_name
    where c.table_schema = 'public'
      and c.column_name = 'company_id'
      and t.table_type = 'BASE TABLE'
      and (
        left(c.table_name, 4) = 'erp_'
        or c.table_name = 'company_memberships'
      )
    order by c.table_name
  loop
    begin
      raise notice
        'Applying tenant RLS hardening to table public.% with company_id type %',
        r.table_name,
        r.company_id_udt_name;

      execute format(
        'alter table public.%I enable row level security',
        r.table_name
      );

      execute format(
        'create index if not exists %I on public.%I (company_id)',
        left(r.table_name || '_company_idx', 63),
        r.table_name
      );

      if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = r.table_name
          and column_name = 'updated_at'
      ) then
        execute format(
          'create index if not exists %I on public.%I (company_id, updated_at desc)',
          left(r.table_name || '_company_updated_idx', 63),
          r.table_name
        );
      end if;

      if r.table_name <> 'company_memberships' then
        policy_name := left(
          r.table_name || '_tenant_select_1767',
          63
        );

        execute format(
          'drop policy if exists %I on public.%I',
          policy_name,
          r.table_name
        );

        execute format(
          'create policy %I on public.%I
             for select
             to authenticated
             using (
               public.is_active_company_member(company_id)
             )',
          policy_name,
          r.table_name
        );

        policy_name := left(
          r.table_name || '_tenant_insert_1767',
          63
        );

        execute format(
          'drop policy if exists %I on public.%I',
          policy_name,
          r.table_name
        );

        execute format(
          'create policy %I on public.%I
             for insert
             to authenticated
             with check (
               public.is_active_company_member(company_id)
             )',
          policy_name,
          r.table_name
        );

        policy_name := left(
          r.table_name || '_tenant_update_1767',
          63
        );

        execute format(
          'drop policy if exists %I on public.%I',
          policy_name,
          r.table_name
        );

        execute format(
          'create policy %I on public.%I
             for update
             to authenticated
             using (
               public.is_active_company_member(company_id)
             )
             with check (
               public.is_active_company_member(company_id)
             )',
          policy_name,
          r.table_name
        );

        policy_name := left(
          r.table_name || '_tenant_delete_1767',
          63
        );

        execute format(
          'drop policy if exists %I on public.%I',
          policy_name,
          r.table_name
        );

        execute format(
          'create policy %I on public.%I
             for delete
             to authenticated
             using (
               public.can_manage_master_data(company_id)
             )',
          policy_name,
          r.table_name
        );

        execute format(
          'grant select, insert, update, delete
             on public.%I
             to authenticated',
          r.table_name
        );
      end if;

    exception
      when others then
        raise exception using
          message = format(
            'RLS hardening failed on table public.%s: %s',
            r.table_name,
            sqlerrm
          ),
          detail = format(
            'company_id data_type=%s, udt_name=%s, SQLSTATE=%s',
            r.company_id_data_type,
            r.company_id_udt_name,
            sqlstate
          ),
          hint =
            'Verify company_id type, required columns, indexes, and helper functions.';
    end;
  end loop;
end
$$;

create or replace function public.erp_schema_health()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with expected(name) as (
    values
      ('companies'),
      ('company_memberships'),
      ('erp_cars'),
      ('erp_customers'),
      ('erp_suppliers'),
      ('erp_sales'),
      ('erp_purchases'),
      ('erp_installments')
  ),
  state as (
    select
      e.name,
      to_regclass('public.' || e.name) is not null as exists
    from expected e
  )
  select jsonb_build_object(
    'ok', bool_and(exists),
    'auth_uid', public.current_external_uid(),
    'tables', jsonb_object_agg(name, exists),
    'checked_at', now()
  )
  from state;
$$;

grant execute
on function public.is_active_company_member(uuid)
to authenticated;

grant execute
on function public.is_active_company_member(text)
to authenticated;

grant execute
on function public.can_manage_master_data(uuid)
to authenticated;

grant execute
on function public.can_manage_master_data(text)
to authenticated;

grant execute
on function public.erp_schema_health()
to authenticated;

commit;