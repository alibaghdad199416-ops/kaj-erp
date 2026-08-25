-- Quality Line ERP 17.15.5
-- Complete native Supabase runtime repair:
-- * canonical membership/RLS authorization for native Supabase Auth
-- * protected cloud master-data writes (no browser-side table mutations)
-- * default chart of accounts, cashboxes, inventory group and main warehouse
-- * automatic customer/supplier ledger bindings
-- * corrected cash-account linkage for posted expenses

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Canonical tenant authorization for every identity representation.
-- ---------------------------------------------------------------------------
create or replace function public.is_company_member(company_slug text)
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
    where c.slug = company_slug
      and c.is_active
      and m.is_active
      and public.erp_membership_matches_current_user(m.user_id, m.user_uid)
  );
$$;

create or replace function public.has_company_role(
  p_company_id uuid,
  p_role text
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
    join public.companies c on c.id = m.company_id
    where m.company_id = p_company_id
      and c.is_active
      and m.is_active
      and public.erp_membership_matches_current_user(m.user_id, m.user_uid)
      and (
        m.is_system_admin
        or m.role_code in ('owner', 'admin')
        or m.role_code = p_role
      )
  );
$$;

-- Core policies that originally embedded user_id = auth.uid().
drop policy if exists companies_member_select on public.companies;
create policy companies_member_select on public.companies
for select to authenticated
using (public.is_active_company_member(id));

drop policy if exists memberships_self_select on public.company_memberships;
create policy memberships_self_select on public.company_memberships
for select to authenticated
using (public.erp_membership_matches_current_user(user_id, user_uid));

drop policy if exists branches_member_select on public.branches;
create policy branches_member_select on public.branches
for select to authenticated
using (public.is_active_company_member(company_id));

drop policy if exists branches_admin_write on public.branches;
create policy branches_admin_write on public.branches
for all to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

drop policy if exists exchange_rates_member_select on public.exchange_rates;
create policy exchange_rates_member_select on public.exchange_rates
for select to authenticated
using (public.is_active_company_member(company_id));

drop policy if exists exchange_rates_admin_write on public.exchange_rates;
create policy exchange_rates_admin_write on public.exchange_rates
for all to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

drop policy if exists erp_records_member_select on public.erp_records;
create policy erp_records_member_select on public.erp_records
for select to authenticated
using (public.is_company_member(company_id));

drop policy if exists erp_records_member_insert on public.erp_records;
create policy erp_records_member_insert on public.erp_records
for insert to authenticated
with check (public.is_company_member(company_id));

drop policy if exists erp_records_member_update on public.erp_records;
create policy erp_records_member_update on public.erp_records
for update to authenticated
using (public.is_company_member(company_id))
with check (public.is_company_member(company_id));

drop policy if exists erp_records_member_delete on public.erp_records;
create policy erp_records_member_delete on public.erp_records
for delete to authenticated
using (public.is_company_member(company_id));

-- Anonymous compatibility access must never remain enabled in production.
drop policy if exists erp_records_bootstrap_select on public.erp_records;
drop policy if exists erp_records_bootstrap_insert on public.erp_records;
drop policy if exists erp_records_bootstrap_update on public.erp_records;
drop policy if exists erp_records_bootstrap_delete on public.erp_records;

-- Rebuild the normalized-cloud policies around the canonical helpers.  Writes
-- are still available for compatibility, while the Flutter application below
-- uses protected SECURITY DEFINER commands.
do $$
declare
  t text;
begin
  foreach t in array array[
    'erp_cars', 'erp_customers', 'erp_suppliers',
    'erp_car_images', 'erp_warehouses', 'erp_car_warehouse_transfers',
    'erp_inventory', 'erp_inventory_groups'
  ] loop
    if to_regclass('public.' || t) is null then
      continue;
    end if;
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('drop policy if exists %I_delete on public.%I', t, t);
    execute format(
      'create policy %I_select on public.%I for select to authenticated using (public.is_active_company_member(company_id))',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert to authenticated with check (public.can_manage_master_data(company_id))',
      t, t
    );
    execute format(
      'create policy %I_update on public.%I for update to authenticated using (public.can_manage_master_data(company_id)) with check (public.can_manage_master_data(company_id))',
      t, t
    );
    execute format(
      'create policy %I_delete on public.%I for delete to authenticated using (public.can_manage_master_data(company_id))',
      t, t
    );
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Default cloud accounting and operational master data.
-- ---------------------------------------------------------------------------
create or replace function public.erp_seed_default_accounts(p_company_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_account_id text;
  v_parent_id text;
  v_candidate_id text;
  v_inserted integer := 0;
  v_rows integer := 0;
begin
  if p_company_id is null
     or not exists (
       select 1 from public.companies c
       where c.id = p_company_id and c.is_active
     ) then
    raise exception 'active_company_required';
  end if;

  for r in
    select *
    from (values
      ('acc-1000','1000','الأصول','asset',null::text,'USD'),
      ('acc-1100','1100','الصندوق - دولار أمريكي','asset','1000','USD'),
      ('acc-1101','1101','الصندوق - دينار عراقي','asset','1000','IQD'),
      ('acc-1200','1200','البنوك','asset','1000','USD'),
      ('acc-1300','1300','مخزون السيارات','asset','1000','USD'),
      ('acc-1400','1400','العملاء','asset','1000','MULTI'),
      ('acc-2000','2000','الالتزامات','liability',null::text,'USD'),
      ('acc-2100','2100','الموردون','liability','2000','MULTI'),
      ('acc-3000','3000','حقوق الملكية','equity',null::text,'USD'),
      ('acc-4000','4000','الإيرادات','revenue',null::text,'USD'),
      ('acc-4100','4100','إيرادات مبيعات السيارات','revenue','4000','USD'),
      ('acc-5000','5000','المصروفات','expense',null::text,'USD'),
      ('acc-5100','5100','تكلفة السيارات المباعة','expense','5000','USD'),
      ('acc-5200','5200','مصروفات تشغيلية','expense','5000','USD')
    ) as x(preferred_id, code, default_name, account_type, parent_code, currency)
  loop
    select a.account_id
      into v_account_id
    from public.erp_accounts a
    where a.organization_id = p_company_id
      and a.code = r.code
    limit 1;

    if r.parent_code is null then
      v_parent_id := null;
    else
      select a.account_id
        into v_parent_id
      from public.erp_accounts a
      where a.organization_id = p_company_id
        and a.code = r.parent_code
      limit 1;
      if v_parent_id is null then
        raise exception 'default_parent_account_missing:%', r.parent_code;
      end if;
    end if;

    if v_account_id is null then
      v_candidate_id := r.preferred_id;
      if exists (
        select 1 from public.erp_accounts a
        where a.organization_id = p_company_id
          and a.account_id = v_candidate_id
          and a.code <> r.code
      ) then
        v_candidate_id := 'default-' || r.code || '-' ||
          substr(md5(p_company_id::text || ':' || r.code), 1, 12);
      end if;

      insert into public.erp_accounts(
        organization_id, account_id, code, name, account_type,
        parent_account_id, currency, opening_balance, is_active,
        source_updated_at, synced_at, synced_by
      ) values (
        p_company_id, v_candidate_id, r.code, r.default_name, r.account_type,
        v_parent_id, r.currency, 0, true, now(), now(), auth.uid()
      )
      on conflict do nothing;

      get diagnostics v_rows = row_count;
      v_inserted := v_inserted + v_rows;

      select a.account_id
        into v_account_id
      from public.erp_accounts a
      where a.organization_id = p_company_id
        and a.code = r.code
      limit 1;

      if v_account_id is null then
        raise exception 'default_account_seed_failed:%', r.code;
      end if;
    end if;

    update public.erp_accounts a
    set name = case
          when nullif(btrim(a.name), '') is null then r.default_name
          else a.name
        end,
        account_type = r.account_type,
        parent_account_id = v_parent_id,
        currency = r.currency,
        is_active = true,
        source_updated_at = now(),
        synced_at = now(),
        synced_by = coalesce(auth.uid(), a.synced_by)
    where a.organization_id = p_company_id
      and a.account_id = v_account_id;
  end loop;

  return v_inserted;
end;
$$;

-- Internal idempotent initializer used both by authenticated startup and by the
-- migration backfill. It is intentionally not granted to browser roles.
create or replace function public.erp_seed_company_runtime_defaults(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch_id uuid;
  v_warehouse_id text;
  v_group_id text;
  v_cash_usd_id text;
  v_cash_iqd_id text;
  v_usd_ledger_id text;
  v_iqd_ledger_id text;
  v_accounts integer := 0;
  v_actor uuid := auth.uid();
begin
  if p_company_id is null
     or not exists (
       select 1 from public.companies c
       where c.id = p_company_id and c.is_active
     ) then
    raise exception 'active_company_required';
  end if;

  v_accounts := public.erp_seed_default_accounts(p_company_id);

  select a.account_id into v_usd_ledger_id
  from public.erp_accounts a
  where a.organization_id = p_company_id and a.code = '1100' and a.is_active
  limit 1;

  select a.account_id into v_iqd_ledger_id
  from public.erp_accounts a
  where a.organization_id = p_company_id and a.code = '1101' and a.is_active
  limit 1;

  if v_usd_ledger_id is null or v_iqd_ledger_id is null then
    raise exception 'default_cash_ledger_accounts_missing';
  end if;

  select b.id into v_branch_id
  from public.branches b
  where b.company_id = p_company_id and b.is_main
  order by b.is_active desc, b.created_at
  limit 1;

  if v_branch_id is null then
    select b.id into v_branch_id
    from public.branches b
    where b.company_id = p_company_id and b.is_active
    order by b.created_at
    limit 1;
  end if;

  if v_branch_id is null then
    v_branch_id := gen_random_uuid();
    insert into public.branches(
      id, company_id, code, name_ar, name_en, is_main, is_active
    ) values (
      v_branch_id, p_company_id, 'MAIN', 'الفرع الرئيسي', 'Main Branch', true, true
    );
  else
    update public.branches
    set is_main = true,
        is_active = true,
        updated_at = now()
    where id = v_branch_id and company_id = p_company_id;
  end if;

  select w.id into v_warehouse_id
  from public.erp_warehouses w
  where w.company_id = p_company_id
    and lower(btrim(coalesce(w.data->>'code', ''))) = 'main'
  order by w.is_deleted, w.created_at
  limit 1;

  if v_warehouse_id is null then
    v_warehouse_id := 'warehouse-main';
    if exists (
      select 1 from public.erp_warehouses w
      where w.company_id = p_company_id and w.id = v_warehouse_id
    ) then
      v_warehouse_id := 'warehouse-main-' || substr(md5(p_company_id::text), 1, 10);
    end if;

    insert into public.erp_warehouses(
      company_id, id, data, created_by, updated_by, is_deleted, deleted_at
    ) values (
      p_company_id,
      v_warehouse_id,
      jsonb_build_object(
        'id',v_warehouse_id, 'code','MAIN', 'name','المخزن الرئيسي',
        'branchId',v_branch_id::text, 'address','', 'notes','',
        'isActive',true, 'createdAt',now()
      ),
      v_actor, v_actor, false, null
    );
  else
    update public.erp_warehouses
    set data = data || jsonb_build_object(
          'id', id,
          'branchId', v_branch_id::text,
          'isActive', true,
          'accountId', coalesce(data->>'accountId', '')
        ),
        is_deleted = false,
        deleted_at = null,
        updated_by = v_actor
    where company_id = p_company_id and id = v_warehouse_id;
  end if;

  select g.id into v_group_id
  from public.erp_inventory_groups g
  where g.company_id = p_company_id
    and lower(btrim(coalesce(g.data->>'code', ''))) = 'general'
  order by g.is_deleted, g.created_at
  limit 1;

  if v_group_id is null then
    v_group_id := 'inventory-group-general';
    if exists (
      select 1 from public.erp_inventory_groups g
      where g.company_id = p_company_id and g.id = v_group_id
    ) then
      v_group_id := 'inventory-group-general-' || substr(md5(p_company_id::text), 1, 10);
    end if;

    insert into public.erp_inventory_groups(
      company_id, id, data, created_by, updated_by, is_deleted, deleted_at
    ) values (
      p_company_id,
      v_group_id,
      jsonb_build_object(
        'id',v_group_id, 'code','GENERAL', 'name','عام',
        'description','المجموعة الافتراضية', 'isActive',true, 'createdAt',now()
      ),
      v_actor, v_actor, false, null
    );
  else
    update public.erp_inventory_groups
    set data = data || jsonb_build_object('id', id, 'isActive', true),
        is_deleted = false,
        deleted_at = null,
        updated_by = v_actor
    where company_id = p_company_id and id = v_group_id;
  end if;

  select a.id into v_cash_usd_id
  from public.erp_cash_accounts a
  where a.company_id = p_company_id
    and (
      a.id = 'cash-main-usd'
      or lower(btrim(coalesce(a.data->>'name', ''))) = lower('الصندوق الرئيسي - دولار')
    )
  order by (a.id = 'cash-main-usd') desc, a.is_deleted, a.created_at
  limit 1;

  if v_cash_usd_id is null then
    v_cash_usd_id := 'cash-main-usd';
    insert into public.erp_cash_accounts(
      company_id, id, data, created_by, updated_by, is_deleted, deleted_at
    ) values (
      p_company_id, v_cash_usd_id,
      jsonb_build_object(
        'id',v_cash_usd_id,'name','الصندوق الرئيسي - دولار','type','cash',
        'currency','USD','openingBalance',0,'isActive',true,
        'accountId',v_usd_ledger_id,'createdAt',now()
      ), v_actor, v_actor, false, null
    );
  else
    update public.erp_cash_accounts
    set data = data || jsonb_build_object(
          'id', id, 'type','cash', 'currency','USD',
          'isActive',true, 'accountId',v_usd_ledger_id
        ),
        is_deleted = false,
        deleted_at = null,
        updated_by = v_actor
    where company_id = p_company_id and id = v_cash_usd_id;
  end if;

  select a.id into v_cash_iqd_id
  from public.erp_cash_accounts a
  where a.company_id = p_company_id
    and (
      a.id = 'cash-main-iqd'
      or lower(btrim(coalesce(a.data->>'name', ''))) = lower('الصندوق الرئيسي - دينار')
    )
  order by (a.id = 'cash-main-iqd') desc, a.is_deleted, a.created_at
  limit 1;

  if v_cash_iqd_id is null then
    v_cash_iqd_id := 'cash-main-iqd';
    insert into public.erp_cash_accounts(
      company_id, id, data, created_by, updated_by, is_deleted, deleted_at
    ) values (
      p_company_id, v_cash_iqd_id,
      jsonb_build_object(
        'id',v_cash_iqd_id,'name','الصندوق الرئيسي - دينار','type','cash',
        'currency','IQD','openingBalance',0,'isActive',true,
        'accountId',v_iqd_ledger_id,'createdAt',now()
      ), v_actor, v_actor, false, null
    );
  else
    update public.erp_cash_accounts
    set data = data || jsonb_build_object(
          'id', id, 'type','cash', 'currency','IQD',
          'isActive',true, 'accountId',v_iqd_ledger_id
        ),
        is_deleted = false,
        deleted_at = null,
        updated_by = v_actor
    where company_id = p_company_id and id = v_cash_iqd_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'companyId', p_company_id,
    'branchId', v_branch_id,
    'warehouseId', v_warehouse_id,
    'inventoryGroupId', v_group_id,
    'usdCashAccountId', v_cash_usd_id,
    'iqdCashAccountId', v_cash_iqd_id,
    'accountsInserted', v_accounts
  );
end;
$$;

create or replace function public.erp_prepare_company_runtime(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_branch_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode = '42501';
  end if;

  v_result := public.erp_seed_company_runtime_defaults(p_company_id);
  v_branch_id := (v_result->>'branchId')::uuid;

  update public.company_memberships
  set default_branch_id = coalesce(default_branch_id, v_branch_id),
      updated_at = now()
  where company_id = p_company_id
    and public.erp_membership_matches_current_user(user_id, user_uid)
    and is_active;

  return v_result || jsonb_build_object('preparedAt', now());
end;
$$;

-- Prepare every existing active company without requiring a browser session.
do $$
declare
  c record;
begin
  for c in select id from public.companies where is_active loop
    perform public.erp_seed_company_runtime_defaults(c.id);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Protected, allow-listed master-data write boundary.
-- ---------------------------------------------------------------------------
create or replace function public.erp_upsert_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text,
  p_data jsonb,
  p_expected_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_version bigint;
  v_branch_id text;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_table not in (
    'erp_cars','erp_customers','erp_suppliers','erp_car_images',
    'erp_warehouses','erp_car_warehouse_transfers',
    'erp_inventory','erp_inventory_groups'
  ) then
    raise exception 'unsupported_master_table:%', p_table;
  end if;
  if coalesce(btrim(p_record_id),'') = '' or p_data is null then
    raise exception 'invalid_master_record';
  end if;

  if p_table in ('erp_customers','erp_suppliers') then
    if coalesce(btrim(p_data->>'name'),'') = '' then
      raise exception 'partner_name_required';
    end if;
  elsif p_table = 'erp_warehouses' then
    if coalesce(btrim(p_data->>'code'),'') = ''
       or coalesce(btrim(p_data->>'name'),'') = '' then
      raise exception 'warehouse_code_and_name_required';
    end if;
    v_branch_id := nullif(btrim(p_data->>'branchId'),'');
    if v_branch_id is not null and not exists (
      select 1 from public.branches
      where company_id=p_company_id and id=v_branch_id::uuid and is_active
    ) then
      raise exception 'warehouse_branch_not_found';
    end if;
    if exists (
      select 1 from public.erp_warehouses
      where company_id=p_company_id and id<>p_record_id and not is_deleted
        and lower(btrim(data->>'code'))=lower(btrim(p_data->>'code'))
    ) then
      raise exception 'warehouse_code_already_exists';
    end if;
  elsif p_table = 'erp_inventory_groups' then
    if coalesce(btrim(p_data->>'code'),'') = ''
       or coalesce(btrim(p_data->>'name'),'') = '' then
      raise exception 'inventory_group_code_and_name_required';
    end if;
  end if;

  execute format(
    'select version from public.%I where company_id=$1 and id=$2 for update',
    p_table
  ) into v_existing_version using p_company_id, p_record_id;

  if p_expected_version is not null
     and v_existing_version is not null
     and v_existing_version <> p_expected_version then
    raise exception 'stale_master_record' using errcode = '40001';
  end if;

  execute format(
    'insert into public.%I(company_id,id,data,created_by,updated_by,is_deleted,deleted_at) '
    || 'values($1,$2,$3,$4,$4,false,null) '
    || 'on conflict(company_id,id) do update set '
    || 'data=excluded.data,updated_by=$4,is_deleted=false,deleted_at=null '
    || 'returning jsonb_build_object(''id'',id,''version'',version,''updatedAt'',updated_at)',
    p_table
  ) into v_result using
    p_company_id,
    p_record_id,
    (p_data - '_cloudVersion' - '_cloudUpdatedAt') || jsonb_build_object('id',p_record_id),
    auth.uid();

  return v_result;
end;
$$;

create or replace function public.erp_soft_delete_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text,
  p_expected_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version bigint;
  v_now timestamptz := now();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if p_table not in (
    'erp_cars','erp_customers','erp_suppliers','erp_car_images',
    'erp_warehouses','erp_car_warehouse_transfers',
    'erp_inventory','erp_inventory_groups'
  ) then
    raise exception 'unsupported_master_table:%', p_table;
  end if;

  execute format(
    'select version from public.%I where company_id=$1 and id=$2 and not is_deleted for update',
    p_table
  ) into v_version using p_company_id,p_record_id;
  if v_version is null then
    raise exception 'master_record_not_found';
  end if;
  if p_expected_version is not null and v_version <> p_expected_version then
    raise exception 'stale_master_record' using errcode = '40001';
  end if;

  if p_table='erp_warehouses' then
    if exists(select 1 from public.erp_cars where company_id=p_company_id and not is_deleted and coalesce(data->>'warehouse_id',data->>'warehouseId')=p_record_id)
       or exists(select 1 from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'warehouseId'=p_record_id and coalesce(nullif(data->>'quantity','')::numeric,0)<>0) then
      raise exception 'warehouse_has_active_inventory';
    end if;
  elsif p_table='erp_inventory_groups' then
    if exists(select 1 from public.erp_inventory where company_id=p_company_id and not is_deleted and coalesce(data->>'groupId',data->>'group_id')=p_record_id) then
      raise exception 'inventory_group_has_products';
    end if;
  end if;

  execute format(
    'update public.%I set is_deleted=true,deleted_at=$3,updated_by=$4 '
    || 'where company_id=$1 and id=$2 returning jsonb_build_object(''id'',id,''version'',version,''deletedAt'',deleted_at)',
    p_table
  ) into v_result using p_company_id,p_record_id,v_now,auth.uid();
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer/supplier accounting links are maintained atomically in PostgreSQL.
-- ---------------------------------------------------------------------------
create or replace function public.erp_partner_ledger_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := case when tg_table_name='erp_suppliers' then 'supplier' else 'customer' end;
  v_parent_code text := case when tg_table_name='erp_suppliers' then '2100' else '1400' end;
  v_parent text;
  v_account_type text := case when tg_table_name='erp_suppliers' then 'liability' else 'asset' end;
  v_prefix text := case when tg_table_name='erp_suppliers' then '21' else '14' end;
  v_name text := coalesce(nullif(btrim(new.data->>'name'),''), new.id);
  v_account_id text := 'partner-' || v_type || '-' || substr(md5(new.id),1,20);
  v_code text := v_prefix || '-' || upper(substr(md5(new.id),1,8));
  v_active boolean := not coalesce(new.is_deleted,false)
    and lower(coalesce(new.data->>'is_active',new.data->>'isActive','true')) in ('1','true','yes','on');
begin
  perform public.erp_seed_default_accounts(new.company_id);

  select a.account_id into v_parent
  from public.erp_accounts a
  where a.organization_id = new.company_id
    and a.code = v_parent_code
    and a.is_active
  limit 1;
  if v_parent is null then
    raise exception 'partner_parent_account_missing:%', v_parent_code;
  end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values (
    new.company_id,v_account_id,v_code,
    (case when v_type='supplier' then 'المورد ' else 'العميل ' end)||v_name,
    v_account_type,v_parent,'MULTI',0,v_active,now(),now(),auth.uid()
  ) on conflict(organization_id,account_id) do update set
    name=excluded.name,
    account_type=excluded.account_type,
    parent_account_id=excluded.parent_account_id,
    currency='MULTI',
    is_active=excluded.is_active,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();

  insert into public.erp_partner_accounts(
    organization_id,partner_type,partner_id,partner_name,
    usd_account_id,iqd_account_id,is_active,source_updated_at,synced_at,synced_by
  ) values (
    new.company_id,v_type,new.id,v_name,
    v_account_id,v_account_id,v_active,now(),now(),auth.uid()
  ) on conflict(organization_id,partner_type,partner_id) do update set
    partner_name=excluded.partner_name,
    usd_account_id=excluded.usd_account_id,
    iqd_account_id=excluded.iqd_account_id,
    is_active=excluded.is_active,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();

  new.data := new.data || jsonb_build_object(
    'accountIdUsd',v_account_id,
    'accountIdIqd',v_account_id,
    'ledgerAccountId',v_account_id
  );
  return new;
end;
$$;

drop trigger if exists erp_customers_partner_ledger on public.erp_customers;
create trigger erp_customers_partner_ledger
before insert or update on public.erp_customers
for each row execute function public.erp_partner_ledger_before_write();

drop trigger if exists erp_suppliers_partner_ledger on public.erp_suppliers;
create trigger erp_suppliers_partner_ledger
before insert or update on public.erp_suppliers
for each row execute function public.erp_partner_ledger_before_write();

-- Backfill ledger bindings for partners created before this repair.
do $$
declare
  r record;
begin
  for r in select * from public.erp_customers loop
    update public.erp_customers set data=data where company_id=r.company_id and id=r.id;
  end loop;
  for r in select * from public.erp_suppliers loop
    update public.erp_suppliers set data=data where company_id=r.company_id and id=r.id;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Account projections and expense posting use authoritative ledger links.
-- ---------------------------------------------------------------------------
create or replace function public.erp_list_cloud_ledger_accounts(p_company_id uuid)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id',a.account_id,
    'code',a.code,
    'name',a.name,
    'type',a.account_type,
    'parentId',a.parent_account_id,
    'currency',a.currency,
    'openingBalance',a.opening_balance,
    'isActive',a.is_active,
    'createdAt',a.synced_at,
    'updatedAt',a.source_updated_at
  )
  from public.erp_accounts a
  where a.organization_id=p_company_id
    and a.is_active
    and public.is_active_company_member(p_company_id)
  order by a.code;
$$;

create or replace function public.erp_post_cloud_expense(
  p_company_id uuid,
  p_expense jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id text := p_expense->>'id';
  v_cash_account_id text := nullif(p_expense->>'accountId','');
  v_cash_ledger_id text;
  v_expense_ledger_id text;
  v_amount numeric := coalesce((p_expense->>'amount')::numeric,0);
  v_rate numeric := coalesce((p_expense->>'exchangeRate')::numeric,1);
  v_currency text := upper(coalesce(nullif(p_expense->>'currency',''),'USD'));
  v_amount_usd numeric;
  v_amount_iqd numeric;
  v_journal_id text;
  v_cash_transaction_id text;
  v_now timestamptz := now();
  v_date date;
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'access denied' using errcode='42501';
  end if;
  perform public.erp_seed_default_accounts(p_company_id);
  if coalesce(v_id,'')='' or coalesce(p_expense->>'title','')='' or coalesce(p_expense->>'category','')='' then
    raise exception 'بيانات المصروف غير مكتملة';
  end if;
  if v_amount<=0 or v_rate<=0 then raise exception 'المبلغ وسعر الصرف يجب أن يكونا أكبر من صفر'; end if;
  v_date := (p_expense->>'date')::date;
  if exists(select 1 from public.erp_expenses where company_id=p_company_id and id=v_id and not is_deleted) then
    raise exception 'المصروف موجود مسبقاً';
  end if;

  if v_currency='IQD' then
    v_amount_iqd:=v_amount; v_amount_usd:=round(v_amount/nullif(v_rate,0),2);
  else
    v_amount_usd:=v_amount; v_amount_iqd:=round(v_amount*v_rate,0);
  end if;

  if v_cash_account_id is null then
    insert into public.erp_expenses(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_id,p_expense||jsonb_build_object(
      'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,
      'postingStatus','draft','journalEntryId',null,'updatedAt',v_now
    ),auth.uid(),auth.uid());
    return jsonb_build_object('id',v_id,'postingStatus','draft');
  end if;

  select nullif(coalesce(data->>'accountId',data->>'account_id'),'')
  into v_cash_ledger_id
  from public.erp_cash_accounts
  where company_id=p_company_id and id=v_cash_account_id and not is_deleted
    and lower(coalesce(data->>'isActive',data->>'is_active','true')) in ('1','true','yes','on')
  for update;
  if not found then raise exception 'الصندوق غير موجود أو غير فعال'; end if;
  if v_cash_ledger_id is null then raise exception 'الصندوق غير مرتبط بحساب في شجرة الحسابات'; end if;

  select account_id into v_expense_ledger_id
  from public.erp_accounts
  where organization_id=p_company_id and code='5200' and is_active
  limit 1;
  if v_expense_ledger_id is null then raise exception 'حساب المصروفات 5200 غير موجود أو غير فعال'; end if;
  if not exists(select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_cash_ledger_id and is_active) then
    raise exception 'حساب الصندوق في شجرة الحسابات غير موجود أو غير فعال';
  end if;

  v_journal_id := gen_random_uuid()::text;
  v_cash_transaction_id := gen_random_uuid()::text;

  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_journal_id,jsonb_build_object(
    'id',v_journal_id,'entryNumber','EXP-'||replace(v_id,'-',''),
    'entryDate',v_date,'description',p_expense->>'title','referenceType','expense',
    'referenceId',v_id,'status','posted','currency','USD',
    'totalDebit',v_amount_usd,'totalCredit',v_amount_usd,
    'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',v_journal_id,'accountId',v_expense_ledger_id,
    'debit',v_amount_usd,'credit',0,'description',p_expense->>'title',
    'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid()),
  (p_company_id,gen_random_uuid()::text,jsonb_build_object(
    'entryId',v_journal_id,'accountId',v_cash_ledger_id,
    'debit',0,'credit',v_amount_usd,'description',p_expense->>'title',
    'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_cash_transaction_id,jsonb_build_object(
    'id',v_cash_transaction_id,'voucherNumber','EXP-'||replace(v_id,'-',''),
    'type','payment','category',p_expense->>'category',
    'cashAccountId',v_cash_account_id,'accountId',v_cash_account_id,
    'branchId',p_expense->>'branchId','amount',v_amount,'currency',v_currency,
    'exchangeRate',v_rate,'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,
    'transactionDate',v_date,'referenceType','expense','referenceId',v_id,
    'partyType','other','partyName',p_expense->>'title','notes',p_expense->>'notes',
    'journalEntryId',v_journal_id,'createdAt',v_now,'updatedAt',v_now
  ),auth.uid(),auth.uid());

  insert into public.erp_expenses(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,p_expense||jsonb_build_object(
    'amountUsd',v_amount_usd,'amountIqd',v_amount_iqd,'postingStatus','posted',
    'journalEntryId',v_journal_id,'cashTransactionId',v_cash_transaction_id,
    'updatedAt',v_now
  ),auth.uid(),auth.uid());

  return jsonb_build_object('id',v_id,'postingStatus','posted','journalEntryId',v_journal_id);
end;
$$;

create or replace function public.erp_cloud_runtime_health(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'authenticated',auth.uid() is not null,
    'member',public.is_active_company_member(p_company_id),
    'canManage',public.can_manage_master_data(p_company_id),
    'accounts',(select count(*) from public.erp_accounts where organization_id=p_company_id and is_active),
    'warehouses',(select count(*) from public.erp_warehouses where company_id=p_company_id and not is_deleted),
    'cashAccounts',(select count(*) from public.erp_cash_accounts where company_id=p_company_id and not is_deleted),
    'customers',(select count(*) from public.erp_customers where company_id=p_company_id and not is_deleted),
    'suppliers',(select count(*) from public.erp_suppliers where company_id=p_company_id and not is_deleted)
  )
  where public.is_active_company_member(p_company_id);
$$;

revoke all on function public.is_company_member(text) from public, anon;
revoke all on function public.has_company_role(uuid,text) from public, anon;
revoke all on function public.erp_seed_default_accounts(uuid) from public, anon, authenticated;
revoke all on function public.erp_seed_company_runtime_defaults(uuid) from public, anon, authenticated;
revoke all on function public.erp_prepare_company_runtime(uuid) from public, anon;
revoke all on function public.erp_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) from public, anon;
revoke all on function public.erp_soft_delete_cloud_master_record(uuid,text,text,bigint) from public, anon;
revoke all on function public.erp_list_cloud_ledger_accounts(uuid) from public, anon;
revoke all on function public.erp_cloud_runtime_health(uuid) from public, anon;

grant execute on function public.is_company_member(text) to authenticated, service_role;
grant execute on function public.has_company_role(uuid,text) to authenticated, service_role;
grant execute on function public.erp_seed_default_accounts(uuid) to service_role;
grant execute on function public.erp_seed_company_runtime_defaults(uuid) to service_role;
grant execute on function public.erp_prepare_company_runtime(uuid) to authenticated, service_role;
grant execute on function public.erp_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) to authenticated, service_role;
grant execute on function public.erp_soft_delete_cloud_master_record(uuid,text,text,bigint) to authenticated, service_role;
grant execute on function public.erp_list_cloud_ledger_accounts(uuid) to authenticated, service_role;
grant execute on function public.erp_post_cloud_expense(uuid,jsonb) to authenticated, service_role;
grant execute on function public.erp_cloud_runtime_health(uuid) to authenticated, service_role;

commit;
