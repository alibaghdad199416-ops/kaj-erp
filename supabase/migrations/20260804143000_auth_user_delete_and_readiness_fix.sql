begin;

-- Quality Line ERP 18.8.8 hotfix:
-- 1) allow hard deletion of Auth users without deleting business/audit rows;
-- 2) keep tenant-owned identity rows cascading with auth.users;
-- 3) restore the readiness RPC to Supabase-native auth.uid() membership checks.

-- Historical migrations created several actor/audit foreign keys without an
-- ON DELETE action. PostgreSQL therefore used NO ACTION, which blocked user
-- deletion from both the Dashboard and admin Edge Functions. Identity-owned
-- rows must cascade; historical actor columns must be retained and set NULL.
do $$
declare
  fk record;
  desired_action text;
  desired_code "char";
  deferrability text;
begin
  for fk in
    select
      constraint_row.conname,
      source_namespace.nspname as schema_name,
      source_table.relname as table_name,
      source_column.attname as column_name,
      source_column.attnotnull,
      constraint_row.confdeltype,
      constraint_row.condeferrable,
      constraint_row.condeferred
    from pg_constraint constraint_row
    join pg_class source_table
      on source_table.oid = constraint_row.conrelid
    join pg_namespace source_namespace
      on source_namespace.oid = source_table.relnamespace
    join pg_class target_table
      on target_table.oid = constraint_row.confrelid
    join pg_namespace target_namespace
      on target_namespace.oid = target_table.relnamespace
    join pg_attribute source_column
      on source_column.attrelid = source_table.oid
     and source_column.attnum = constraint_row.conkey[1]
    where constraint_row.contype = 'f'
      and source_namespace.nspname = 'public'
      and target_namespace.nspname = 'auth'
      and target_table.relname = 'users'
      and cardinality(constraint_row.conkey) = 1
      and cardinality(constraint_row.confkey) = 1
  loop
    if fk.table_name in ('profiles', 'company_memberships', 'erp_user_ui_preferences') then
      desired_action := 'cascade';
      desired_code := 'c';
    else
      desired_action := 'set null';
      desired_code := 'n';

      if fk.attnotnull then
        execute format(
          'alter table %I.%I alter column %I drop not null',
          fk.schema_name,
          fk.table_name,
          fk.column_name
        );
      end if;
    end if;

    if fk.confdeltype is distinct from desired_code then
      deferrability := case
        when fk.condeferrable and fk.condeferred then ' deferrable initially deferred'
        when fk.condeferrable then ' deferrable initially immediate'
        else ''
      end;

      execute format(
        'alter table %I.%I drop constraint %I',
        fk.schema_name,
        fk.table_name,
        fk.conname
      );

      execute format(
        'alter table %I.%I add constraint %I foreign key (%I) references auth.users(id) on delete %s%s',
        fk.schema_name,
        fk.table_name,
        fk.conname,
        fk.column_name,
        desired_action,
        deferrability
      );
    end if;
  end loop;
end;
$$;

create or replace function public.erp_operational_readiness(
  p_company_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_is_member boolean := false;
  v_modules jsonb;
begin
  if v_auth_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if p_company_id is null then
    raise exception 'company_id_required' using errcode = '22023';
  end if;

  select exists (
    select 1
    from public.company_memberships membership
    where membership.company_id = p_company_id
      and membership.user_id = v_auth_user_id
      and membership.is_active = true
  )
  into v_is_member;

  if not v_is_member then
    raise exception 'company_membership_required' using errcode = '42501';
  end if;

  v_modules := jsonb_build_object(
    'dashboard', to_regclass('public.erp_cars') is not null
      and to_regclass('public.erp_sales') is not null,
    'search', to_regclass('public.erp_cars') is not null
      and to_regclass('public.erp_customers') is not null,
    'notifications', to_regclass('public.erp_enterprise_notifications') is not null,
    'cars', to_regclass('public.erp_cars') is not null,
    'customers', to_regclass('public.erp_customers') is not null,
    'suppliers', to_regclass('public.erp_suppliers') is not null,
    'customer_service', to_regclass('public.erp_service_cases') is not null,
    'sales', to_regclass('public.erp_sales') is not null,
    'purchases', to_regclass('public.erp_purchases') is not null
      and to_regclass('public.erp_purchase_items') is not null,
    'installments', to_regclass('public.erp_installments') is not null,
    'inventory', to_regclass('public.erp_inventory') is not null
      and to_regclass('public.erp_warehouse_stock') is not null,
    'maintenance', to_regclass('public.erp_maintenance_orders') is not null
      and to_regclass('public.erp_maintenance_parts') is not null
      and to_regclass('public.erp_maintenance_payments') is not null,
    'accounting', to_regclass('public.erp_accounts') is not null
      and to_regclass('public.erp_journal_entries') is not null
      and to_regclass('public.erp_journal_lines') is not null,
    'cashbox', to_regclass('public.erp_cash_transactions') is not null,
    'expenses', to_regclass('public.erp_expenses') is not null,
    'reports', to_regclass('public.erp_saved_report_filters') is not null,
    'settings', to_regclass('public.erp_user_ui_preferences') is not null,
    'access', to_regclass('public.erp_permission_roles') is not null
      and to_regclass('public.erp_role_permission_grants') is not null
      and to_regclass('public.erp_user_role_assignments') is not null,
    'documents', to_regclass('public.erp_document_records') is not null
  );

  return jsonb_build_object(
    'ok', not exists (
      select 1
      from jsonb_each(v_modules) item
      where item.value <> 'true'::jsonb
    ),
    'company_id', p_company_id,
    'auth_user_id', v_auth_user_id,
    'modules', v_modules,
    'checked_at', timezone('utc', now())
  );
end;
$$;

revoke all on function public.erp_operational_readiness(uuid) from public;
grant execute on function public.erp_operational_readiness(uuid) to authenticated;

commit;
