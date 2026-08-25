begin;

-- R15: canonical-state reconciliation.
-- The live normalized PostgreSQL state is authoritative. Unrestored recycle-bin
-- tombstones win over stale payloads, legacy capitalization masters can never be
-- reactivated, and cashbox ledger bindings/opening balances are continuously
-- reconciled to the current cashbox definition.

create or replace function public.erp_r15_pending_delete_exists(
  p_company_id uuid,p_table text,p_record_id text
) returns boolean
language sql stable security definer set search_path=public as $$
  select (auth.uid() is null or public.is_active_company_member(p_company_id)) and exists(
    select 1
    from public.erp_universal_recycle_bin u
    where u.source_table=p_table
      and u.record_id=p_record_id
      and (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null
  )
$$;

-- Re-apply authoritative tombstones once. This repairs rows that were deleted,
-- archived, then accidentally resurrected by an old upsert that forced
-- is_deleted=false. Explicit recycle-bin restore marks restored_at first, so a
-- legitimate restore is never removed by this rule.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'update public.%I r set is_deleted=true, '
        ||'deleted_at=coalesce(r.deleted_at,(select max(u.deleted_at) from public.erp_universal_recycle_bin u '
        ||'where u.source_table=%L and u.record_id=r.id and (u.company_id=r.company_id or u.company_id is null) '
        ||'and u.restored_at is null)), '
        ||'updated_at=now(),version=coalesce(r.version,0)+1 '
        ||'where not coalesce(r.is_deleted,false) and public.erp_r15_pending_delete_exists(r.company_id,%L,r.id)',
        v_table,v_table,v_table
      );
    end if;
  end loop;
end $$;

-- Browser reads also honor tombstones, even if a legacy writer somehow manages
-- to produce an inconsistent live row before a reconciliation pass.
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_row record;
  v_rel regclass;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_row in execute format(
    'select id::text id,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end data,'
    ||'version,updated_at from public.%I r where company_id=$1 and not coalesce(is_deleted,false) '
    ||'and not public.erp_r15_pending_delete_exists($1,%L,r.id) order by updated_at desc',
    p_table,p_table
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
      ||jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
  end loop;
  return;
end;
$$;

create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_row record;
  v_rel regclass;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  if public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id) then
    return null;
  end if;
  execute format(
    'select id::text id,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end data,'
    ||'version,updated_at from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',p_table
  ) into v_row using p_company_id,p_record_id;
  if v_row.id is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
    ||jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
end;
$$;

-- Existing rows require an optimistic-concurrency version and deleted rows can
-- only be restored through the recycle-bin restore workflow. An ordinary save
-- can no longer resurrect a deleted warehouse/customer/product/etc.
create or replace function public.erp_r9_upsert_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text,p_data jsonb,
  p_expected_version bigint default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_existing_version bigint;
  v_existing_data jsonb:='{}'::jsonb;
  v_existing_deleted boolean:=false;
  v_action text;
  v_permission text;
  v_guarded jsonb;
  v_branch_id text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if p_table not in (
    'erp_cars','erp_customers','erp_suppliers','erp_car_images',
    'erp_warehouses','erp_inventory','erp_inventory_groups'
  ) then raise exception 'unsupported_master_write_table:%',p_table; end if;
  if coalesce(btrim(p_record_id),'')='' or p_data is null then raise exception 'invalid_master_record'; end if;

  execute format(
    'select version,data,coalesce(is_deleted,false) from public.%I where company_id=$1 and id=$2 for update',p_table
  ) into v_existing_version,v_existing_data,v_existing_deleted using p_company_id,p_record_id;

  if v_existing_version is not null and
     (v_existing_deleted or public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id)) then
    raise exception 'deleted_master_record_requires_explicit_restore' using errcode='55000',
      hint='Restore the record from Recycle Bin; normal save/upsert cannot resurrect deleted data.';
  end if;
  if v_existing_version is not null and p_expected_version is null then
    raise exception 'expected_version_required' using errcode='40001',
      hint='Refresh the record before saving so a stale screen cannot overwrite newer data.';
  end if;
  if p_expected_version is not null and v_existing_version is not null
     and v_existing_version<>p_expected_version then
    raise exception 'stale_master_record' using errcode='40001';
  end if;

  v_action:=case when v_existing_version is null then 'create' else 'update' end;
  v_permission:=public.erp_r9_master_required_permission(p_table,v_action);
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.'||v_action) using errcode='42501';
  end if;

  v_guarded:=public.erp_r9_guard_writable_master_json(
    p_company_id,p_table,coalesce(v_existing_data,'{}'::jsonb),
    p_data-'_cloudVersion'-'_cloudUpdatedAt'
  );
  if p_table in ('erp_customers','erp_suppliers') then
    if coalesce(btrim(v_guarded->>'name'),'')='' then raise exception 'partner_name_required'; end if;
  elsif p_table='erp_warehouses' then
    if coalesce(btrim(v_guarded->>'code'),'')='' or coalesce(btrim(v_guarded->>'name'),'')='' then
      raise exception 'warehouse_code_and_name_required';
    end if;
    v_branch_id:=nullif(btrim(v_guarded->>'branchId'),'');
    if v_branch_id is not null and not exists(
      select 1 from public.branches where company_id=p_company_id and id=v_branch_id::uuid and is_active
    ) then raise exception 'warehouse_branch_not_found'; end if;
    if exists(
      select 1 from public.erp_warehouses
      where company_id=p_company_id and id<>p_record_id and not is_deleted
        and not public.erp_r15_pending_delete_exists(p_company_id,'erp_warehouses',id)
        and lower(btrim(data->>'code'))=lower(btrim(v_guarded->>'code'))
    ) then raise exception 'warehouse_code_already_exists'; end if;
  elsif p_table='erp_inventory_groups' then
    if coalesce(btrim(v_guarded->>'code'),'')='' or coalesce(btrim(v_guarded->>'name'),'')='' then
      raise exception 'inventory_group_code_and_name_required';
    end if;
  end if;

  execute format(
    'insert into public.%I(company_id,id,data,created_by,updated_by,is_deleted,deleted_at) '
    ||'values($1,$2,$3,$4,$4,false,null) '
    ||'on conflict(company_id,id) do update set data=excluded.data,updated_by=$4 '
    ||'where public.%I.version=$5 and not public.%I.is_deleted '
    ||'returning jsonb_build_object(''id'',id,''version'',version,''updatedAt'',updated_at)',
    p_table,p_table,p_table
  ) into v_result using p_company_id,p_record_id,
    v_guarded||jsonb_build_object('id',p_record_id),auth.uid(),v_existing_version;
  if v_result is null then raise exception 'stale_master_record' using errcode='40001'; end if;
  return v_result;
end;
$$;

-- R15 browser facade: every browser-facing argument is explicitly named so
-- PostgREST can resolve JSON RPC parameters deterministically after schema reload.
create or replace function public.erp_r15_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_list_cloud_master_records(p_company_id,p_table)
$$;
create or replace function public.erp_r15_get_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text
) returns jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_get_cloud_master_record(p_company_id,p_table,p_record_id)
$$;
create or replace function public.erp_r15_upsert_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text,p_data jsonb,p_expected_version bigint default null
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_r9_upsert_cloud_master_record(
    p_company_id,p_table,p_record_id,p_data,p_expected_version)
$$;
create or replace function public.erp_r15_list_deleted_master_ids(
  p_company_id uuid,p_table text
) returns setof text language sql stable security definer set search_path=public as $$
  select * from public.erp_r14_list_deleted_master_ids(p_company_id,p_table)
$$;


-- Existing normalized rows must also carry an explicit version on delete. This
-- prevents a stale screen from deleting a newer server-side edit.
create or replace function public.erp_r15_soft_delete_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text,p_expected_version bigint default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if p_expected_version is null then
    raise exception 'expected_version_required' using errcode='40001',
      hint='Refresh the record before deleting so a stale screen cannot remove newer data.';
  end if;
  return public.erp_r9_soft_delete_cloud_master_record(
    p_company_id,p_table,p_record_id,p_expected_version);
end;
$$;

-- Current account-tree surface. R15 keeps legacy R9 wrappers for compatibility,
-- but the current client uses this namespace and requires a freshness token on
-- every existing-account edit.
create or replace function public.erp_r15_list_cloud_ledger_accounts(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_list_cloud_ledger_accounts($1)
$$;

create or replace function public.erp_r15_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_current_updated timestamptz;
  v_incoming_updated timestamptz;
  v_code text;
  v_name text;
begin
  if v_id='' then raise exception 'ledger_account_id_required'; end if;
  begin
    v_incoming_updated:=nullif(btrim(coalesce(p_account->>'updatedAt','')),'')::timestamptz;
  exception when others then
    raise exception 'invalid_account_snapshot_timestamp' using errcode='22007';
  end;
  select source_updated_at,code,name into v_current_updated,v_code,v_name
  from public.erp_accounts where organization_id=p_company_id and account_id=v_id for update;
  if found then
    if public.erp_v763_forbidden_capitalization_account(v_code,v_name) then
      raise exception 'legacy_capitalization_account_locked' using errcode='55000';
    end if;
    if v_incoming_updated is null then
      raise exception 'account_snapshot_version_required' using errcode='40001';
    end if;
    if v_current_updated is distinct from v_incoming_updated then
      raise exception 'stale_ledger_account' using errcode='40001',
        hint='Reload the chart of accounts before saving; the server copy is newer.';
    end if;
  elsif p_require_existing then
    raise exception 'ledger_account_not_found';
  end if;
  if public.erp_v763_forbidden_capitalization_account(p_account->>'code',p_account->>'name') then
    raise exception 'legacy_capitalization_account_locked' using errcode='55000';
  end if;
  perform public.erp_r9_save_cloud_ledger_account(p_company_id,p_account,p_require_existing);
end;
$$;

-- R15 cash namespace. Existing R9 wrappers remain callable by the already
-- deployed client, while the current client uses an explicit canonical surface.
create or replace function public.erp_r15_save_cloud_cash_account(p_company_id uuid,p_account jsonb)
returns void language sql security definer set search_path=public as $$
  select public.erp_r9_save_cloud_cash_account(p_company_id,p_account)
$$;
create or replace function public.erp_r15_cloud_cash_account_balances(p_company_id uuid)
returns table(cash_account_id text,balance numeric)
language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_cash_account_balances(p_company_id)
$$;
create or replace function public.erp_r15_cloud_cash_ledger_reconciliation(p_company_id uuid)
returns table(cash_account_id text,cash_account_name text,currency text,
  subledger_balance numeric,ledger_balance numeric,difference numeric)
language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_cloud_cash_ledger_reconciliation(p_company_id)
$$;
create or replace function public.erp_r15_cloud_cash_currency_summary(p_company_id uuid,p_currency text)
returns jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_cloud_cash_currency_summary(p_company_id,p_currency)
$$;
create or replace function public.erp_r15_post_cloud_cash_transaction(
  p_company_id uuid,p_transaction jsonb,p_replace boolean default false
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_post_cloud_cash_transaction(p_company_id,p_transaction,p_replace)
$$;
create or replace function public.erp_r15_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric(38,20),
  p_transfer_date timestamptz,p_notes text default null
) returns void language sql security definer set search_path=public as $$
  select public.erp_r9_transfer_cloud_cash(
    p_company_id,p_from_cash_account_id,p_to_cash_account_id,p_source_amount,
    p_target_amount,p_exchange_rate,p_transfer_date,p_notes)
$$;

-- Current accounting policy always wins over historical sync payloads.
create or replace function public.erp_r15_enforce_account_policy()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if public.erp_v763_forbidden_capitalization_account(new.code,new.name) then
    new.is_active:=false;
    new.name:='حساب تاريخي متوقف - رسملة ملغاة';
    if TG_OP='UPDATE' then
      new.account_type:=old.account_type;
      new.parent_account_id:=old.parent_account_id;
      new.currency:=old.currency;
      new.opening_balance:=old.opening_balance;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists erp_r15_enforce_account_policy on public.erp_accounts;
create trigger erp_r15_enforce_account_policy
before insert or update on public.erp_accounts
for each row execute function public.erp_r15_enforce_account_policy();

update public.erp_accounts
set is_active=false,name='حساب تاريخي متوقف - رسملة ملغاة',source_updated_at=now(),synced_at=now()
where public.erp_v763_forbidden_capitalization_account(code,name);

create or replace function public.erp_r9_list_cloud_ledger_accounts(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
    p_company_id,'accounting',
    jsonb_build_object(
      'id',a.account_id,'code',a.code,'name',a.name,'type',a.account_type,
      'parentId',a.parent_account_id,'currency',a.currency,
      'openingBalance',a.opening_balance,'isActive',a.is_active,
      'createdAt',a.synced_at,'updatedAt',a.source_updated_at
    ),'accounting.view')
  from public.erp_accounts a
  where a.organization_id=p_company_id and a.is_active
    and not public.erp_v763_forbidden_capitalization_account(a.code,a.name)
    and public.is_active_company_member(p_company_id)
  order by a.code
$$;

-- Monotonic accounting-master sync. Older cached snapshots can no longer
-- overwrite a newer chart-of-accounts/partner/item-cost state. A payload without
-- updatedAt may create a missing row, but it is not allowed to replace an
-- existing row whose freshness cannot be proven.
create or replace function public.erp_sync_accounting_master_data(
  p_organization_id uuid,
  p_accounts jsonb,
  p_partner_accounts jsonb,
  p_item_costs jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_account jsonb;
  v_partner jsonb;
  v_item jsonb;
  v_accounts_count integer:=0;
  v_partners_count integer:=0;
  v_items_count integer:=0;
  v_stale_skipped integer:=0;
  v_before timestamptz;
  v_incoming timestamptz;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not public.is_active_company_member(p_organization_id) then
    raise exception 'company_membership_required';
  end if;

  for v_account in select value from jsonb_array_elements(coalesce(p_accounts,'[]'::jsonb)) loop
    v_incoming:=nullif(v_account->>'updatedAt','')::timestamptz;
    select source_updated_at into v_before from public.erp_accounts
      where organization_id=p_organization_id and account_id=v_account->>'id';
    insert into public.erp_accounts(
      organization_id,account_id,code,name,account_type,parent_account_id,currency,
      opening_balance,is_active,source_updated_at,synced_at,synced_by
    ) values(
      p_organization_id,v_account->>'id',v_account->>'code',v_account->>'name',v_account->>'type',
      nullif(v_account->>'parentId',''),coalesce(nullif(v_account->>'currency',''),'USD'),
      coalesce((v_account->>'openingBalance')::numeric,0),
      coalesce((v_account->>'isActive')::boolean,true),v_incoming,now(),auth.uid()
    ) on conflict(organization_id,account_id) do update set
      code=excluded.code,name=excluded.name,account_type=excluded.account_type,
      parent_account_id=excluded.parent_account_id,currency=excluded.currency,
      opening_balance=excluded.opening_balance,is_active=excluded.is_active,
      source_updated_at=excluded.source_updated_at,synced_at=now(),synced_by=auth.uid()
    where excluded.source_updated_at is not null
      and (erp_accounts.source_updated_at is null or excluded.source_updated_at>=erp_accounts.source_updated_at);
    if v_before is not null and (v_incoming is null or v_incoming<v_before) then
      v_stale_skipped:=v_stale_skipped+1;
    else
      v_accounts_count:=v_accounts_count+1;
    end if;
  end loop;

  for v_partner in select value from jsonb_array_elements(coalesce(p_partner_accounts,'[]'::jsonb)) loop
    v_incoming:=nullif(v_partner->>'updatedAt','')::timestamptz;
    select source_updated_at into v_before from public.erp_partner_accounts
      where organization_id=p_organization_id and partner_type=v_partner->>'partnerType'
        and partner_id=v_partner->>'id';
    insert into public.erp_partner_accounts(
      organization_id,partner_type,partner_id,partner_name,usd_account_id,iqd_account_id,
      is_active,source_updated_at,synced_at,synced_by
    ) values(
      p_organization_id,v_partner->>'partnerType',v_partner->>'id',v_partner->>'name',
      nullif(v_partner->>'accountIdUsd',''),nullif(v_partner->>'accountIdIqd',''),
      coalesce((v_partner->>'isActive')::boolean,true),v_incoming,now(),auth.uid()
    ) on conflict(organization_id,partner_type,partner_id) do update set
      partner_name=excluded.partner_name,usd_account_id=excluded.usd_account_id,
      iqd_account_id=excluded.iqd_account_id,is_active=excluded.is_active,
      source_updated_at=excluded.source_updated_at,synced_at=now(),synced_by=auth.uid()
    where excluded.source_updated_at is not null
      and (erp_partner_accounts.source_updated_at is null or excluded.source_updated_at>=erp_partner_accounts.source_updated_at);
    if v_before is not null and (v_incoming is null or v_incoming<v_before) then
      v_stale_skipped:=v_stale_skipped+1;
    else
      v_partners_count:=v_partners_count+1;
    end if;
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_item_costs,'[]'::jsonb)) loop
    v_incoming:=nullif(v_item->>'updatedAt','')::timestamptz;
    select source_updated_at into v_before from public.erp_item_costs
      where organization_id=p_organization_id and item_type=v_item->>'itemType'
        and item_id=v_item->>'id';
    insert into public.erp_item_costs(
      organization_id,item_type,item_id,item_name,currency,purchase_cost,landed_cost,
      maintenance_cost,unit_cost,sale_price,is_active,source_updated_at,synced_at,synced_by
    ) values(
      p_organization_id,v_item->>'itemType',v_item->>'id',v_item->>'name',
      coalesce(nullif(v_item->>'currency',''),'USD'),coalesce((v_item->>'purchaseCost')::numeric,0),
      coalesce((v_item->>'landedCost')::numeric,0),coalesce((v_item->>'maintenanceCost')::numeric,0),
      coalesce((v_item->>'unitCost')::numeric,0),coalesce((v_item->>'salePrice')::numeric,0),
      coalesce((v_item->>'isActive')::boolean,true),v_incoming,now(),auth.uid()
    ) on conflict(organization_id,item_type,item_id) do update set
      item_name=excluded.item_name,currency=excluded.currency,purchase_cost=excluded.purchase_cost,
      landed_cost=excluded.landed_cost,maintenance_cost=excluded.maintenance_cost,
      unit_cost=excluded.unit_cost,sale_price=excluded.sale_price,is_active=excluded.is_active,
      source_updated_at=excluded.source_updated_at,synced_at=now(),synced_by=auth.uid()
    where excluded.source_updated_at is not null
      and (erp_item_costs.source_updated_at is null or excluded.source_updated_at>=erp_item_costs.source_updated_at);
    if v_before is not null and (v_incoming is null or v_incoming<v_before) then
      v_stale_skipped:=v_stale_skipped+1;
    else
      v_items_count:=v_items_count+1;
    end if;
  end loop;

  return jsonb_build_object('accounts',v_accounts_count,'partnerAccounts',v_partners_count,
    'itemCosts',v_items_count,'staleSnapshotsSkipped',v_stale_skipped,'syncedAt',now());
end;
$$;

-- Cashbox definitions also follow latest-state semantics. A deleted cashbox may
-- only come back through an explicit restore path; an older form cannot revive
-- it. Existing rows reject an older updated_at snapshot.
create or replace function public.erp_save_cloud_cash_account(
  p_company_id uuid,p_account jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_ledger text:=btrim(coalesce(p_account->>'account_id',p_account->>'accountId',''));
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_linked text:=nullif(btrim(coalesce(p_account->>'linked_cash_account_id',p_account->>'linkedCashAccountId','')),'');
  v_ledger_currency text; v_ledger_type text; v_link_currency text;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'is_active',p_account->>'isActive'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'opening_balance',p_account->>'openingBalance'),0);
  v_existing_deleted boolean;
  v_existing_updated timestamptz;
  v_incoming_updated timestamptz:=nullif(coalesce(p_account->>'updated_at',p_account->>'updatedAt',''),'')::timestamptz;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_name='' or v_ledger='' then raise exception 'cashbox_data_incomplete'; end if;
  if v_currency not in ('USD','IQD') or v_opening<0 then raise exception 'invalid_cashbox_currency_or_opening'; end if;

  select is_deleted,coalesce(nullif(data->>'updatedAt','')::timestamptz,updated_at)
    into v_existing_deleted,v_existing_updated
  from public.erp_cash_accounts where company_id=p_company_id and id=v_id for update;
  if coalesce(v_existing_deleted,false) then
    raise exception 'deleted_cash_account_requires_explicit_restore' using errcode='55000';
  end if;
  if v_existing_updated is not null and v_incoming_updated is null then
    raise exception 'cash_account_snapshot_version_required' using errcode='40001';
  end if;
  if v_existing_updated is not null and v_incoming_updated<v_existing_updated then
    raise exception 'stale_cash_account' using errcode='40001';
  end if;

  select upper(currency),account_type into v_ledger_currency,v_ledger_type
  from public.erp_accounts where organization_id=p_company_id and account_id=v_ledger and is_active;
  if v_ledger_currency is null or v_ledger_type<>'asset' or v_ledger_currency not in (v_currency,'MULTI') then
    raise exception 'invalid_cashbox_ledger_binding';
  end if;
  if exists(select 1 from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id<>v_id
    and not ca.is_deleted and public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true')
    and coalesce(ca.data->>'account_id',ca.data->>'accountId')=v_ledger) then
    raise exception 'ledger_already_linked_to_active_cashbox';
  end if;
  if v_linked is not null then
    select upper(coalesce(data->>'currency','')) into v_link_currency from public.erp_cash_accounts
    where company_id=p_company_id and id=v_linked and not is_deleted
      and public.erp_try_boolean(coalesce(data->>'isActive',data->>'is_active'),'true');
    if v_link_currency is null or v_link_currency=v_currency then raise exception 'linked_cashbox_must_use_other_currency'; end if;
  end if;

  insert into public.erp_cash_accounts(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'id',v_id,'name',v_name,'type',coalesce(nullif(p_account->>'type',''),'cash'),
    'currency',v_currency,'openingBalance',v_opening,'opening_balance',v_opening,
    'isActive',v_active,'is_active',v_active,'accountId',v_ledger,'account_id',v_ledger,
    'linkedCashAccountId',v_linked,'linked_cash_account_id',v_linked,
    'createdAt',coalesce(p_account->'created_at',p_account->'createdAt',to_jsonb(now())),
    'updatedAt',to_jsonb(now()),'updated_at',to_jsonb(now()),'schemaVersion',15,'schema_version',15
  ),auth.uid(),auth.uid())
  on conflict(company_id,id) do update set data=excluded.data,
    version=erp_cash_accounts.version+1,updated_at=now(),updated_by=auth.uid()
  where not erp_cash_accounts.is_deleted;

  delete from public.erp_cash_account_links where company_id=p_company_id
    and (source_cash_account_id=v_id or target_cash_account_id=v_id);
  if v_linked is not null then
    insert into public.erp_cash_account_links(company_id,source_cash_account_id,target_cash_account_id,created_by,updated_by)
    values(p_company_id,v_id,v_linked,auth.uid(),auth.uid()),(p_company_id,v_linked,v_id,auth.uid(),auth.uid())
    on conflict(company_id,source_cash_account_id) do update set
      target_cash_account_id=excluded.target_cash_account_id,updated_at=now(),updated_by=auth.uid();
    update public.erp_cash_accounts
    set data=jsonb_set(jsonb_set(data,'{linkedCashAccountId}',to_jsonb(v_id),true),'{linked_cash_account_id}',to_jsonb(v_id),true),
      version=version+1,updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_linked and not is_deleted;
  end if;
end;
$$;

-- Canonical cashbox binding. The current cashbox definition owns both its
-- ledger opening balance and the cash-side line of every linked cash journal.
-- This makes a corrected cashbox binding persist instead of requiring a manual
-- re-save every time old journal/account links are encountered.
create or replace function public.erp_r15_rebind_cashbox_journals_internal(
  p_company_id uuid,p_cash_account_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_cash public.erp_cash_accounts%rowtype;
  v_ledger record;
  v_tx record;
  v_line_id text;
  v_amount numeric;
  v_type text;
  v_changed integer:=0;
  v_missing integer:=0;
  v_ambiguous integer:=0;
  v_opening numeric;
  v_candidate_count integer;
  v_best_priority integer;
begin
  select * into v_cash from public.erp_cash_accounts
  where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
  if not found then return jsonb_build_object('cashAccountId',p_cash_account_id,'skipped','missing'); end if;
  select account_id,code,name,currency into v_ledger
  from public.erp_accounts
  where organization_id=p_company_id
    and account_id=coalesce(v_cash.data->>'accountId',v_cash.data->>'account_id')
    and is_active;
  if v_ledger.account_id is null then
    return jsonb_build_object('cashAccountId',p_cash_account_id,'skipped','ledger_missing');
  end if;
  if upper(coalesce(v_ledger.currency,''))<>upper(coalesce(v_cash.data->>'currency','')) then
    return jsonb_build_object('cashAccountId',p_cash_account_id,'skipped','ledger_currency_mismatch');
  end if;

  v_opening:=public.erp_try_numeric(coalesce(v_cash.data->>'openingBalance',v_cash.data->>'opening_balance'),0);
  update public.erp_accounts set opening_balance=v_opening,source_updated_at=now(),synced_at=now()
  where organization_id=p_company_id and account_id=v_ledger.account_id
    and opening_balance is distinct from v_opening;

  for v_tx in
    select id,data from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_cash_account_id
      and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is not null
    order by created_at,id
  loop
    v_amount:=abs(public.erp_try_numeric(v_tx.data->>'amount',0));
    v_type:=lower(coalesce(v_tx.data->>'type',''));
    v_line_id:=null;
    v_candidate_count:=0;
    v_best_priority:=null;

    -- Old releases did not always stamp line currency/cashAccountId, so use the
    -- journal header as a currency fallback. Never rewrite an ambiguous line:
    -- the best-priority candidate must be unique.
    with candidates as (
      select jl.id,
        case
          when jl.data->>'cashTransactionId'=v_tx.id
               and jl.data->>'cashAccountId'=p_cash_account_id then 0
          when jl.data->>'cashTransactionId'=v_tx.id then 1
          when jl.data->>'accountId'=v_ledger.account_id then 2
          else 3
        end priority
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId' and not je.is_deleted
      where jl.company_id=p_company_id and not jl.is_deleted
        and jl.data->>'entryId'=coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id')
        and upper(coalesce(nullif(jl.data->>'currency',''),je.data->>'currency',''))=
            upper(coalesce(v_tx.data->>'currency',''))
        and (
          (v_type in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
            and abs(public.erp_try_numeric(jl.data->>'debit',0)-v_amount)<=0.01
            and abs(public.erp_try_numeric(jl.data->>'credit',0))<=0.01)
          or
          (v_type in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
            and abs(public.erp_try_numeric(jl.data->>'credit',0)-v_amount)<=0.01
            and abs(public.erp_try_numeric(jl.data->>'debit',0))<=0.01)
        )
    ), ranked as (
      select *,min(priority) over() best_priority from candidates
    )
    select count(*)::integer,min(id),min(best_priority)
      into v_candidate_count,v_line_id,v_best_priority
    from ranked where priority=best_priority;

    if coalesce(v_candidate_count,0)=0 then
      v_missing:=v_missing+1;
      continue;
    elsif v_candidate_count<>1 then
      v_ambiguous:=v_ambiguous+1;
      v_line_id:=null;
      continue;
    end if;

    update public.erp_journal_lines
    set data=data||jsonb_build_object(
          'accountId',v_ledger.account_id,'accountCode',v_ledger.code,
          'accountName',v_ledger.name,'currency',upper(v_ledger.currency),
          'cashTransactionId',v_tx.id,'cashAccountId',p_cash_account_id,
          'r15CanonicalCashBinding',true),
        updated_at=now()
    where company_id=p_company_id and id=v_line_id
      and (data->>'accountId' is distinct from v_ledger.account_id
           or data->>'cashTransactionId' is distinct from v_tx.id
           or data->>'cashAccountId' is distinct from p_cash_account_id
           or not public.erp_try_boolean(data->>'r15CanonicalCashBinding',false));
    if found then v_changed:=v_changed+1; end if;
    update public.erp_cash_transactions
    set data=data||jsonb_build_object('cashLedgerAccountId',v_ledger.account_id,'r15CanonicalCashBinding',true),
        updated_at=now()
    where company_id=p_company_id and id=v_tx.id
      and (data->>'cashLedgerAccountId' is distinct from v_ledger.account_id
           or not public.erp_try_boolean(data->>'r15CanonicalCashBinding',false));
  end loop;
  return jsonb_build_object('cashAccountId',p_cash_account_id,'ledgerAccountId',v_ledger.account_id,
    'updatedJournalLines',v_changed,'unmatchedTransactions',v_missing,
    'ambiguousTransactions',v_ambiguous,'openingBalance',v_opening);
end;
$$;
create or replace function public.erp_r15_rebind_cashbox_journals(
  p_company_id uuid,p_cash_account_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'accounting.update')
     and not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;
  return public.erp_r15_rebind_cashbox_journals_internal(p_company_id,p_cash_account_id);
end;
$$;

create or replace function public.erp_r15_cashbox_definition_changed()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_r15_rebind_cashbox_journals_internal(new.company_id,new.id);
  return new;
end;
$$;
drop trigger if exists erp_r15_cashbox_definition_changed on public.erp_cash_accounts;
create trigger erp_r15_cashbox_definition_changed
after insert or update of data,is_deleted on public.erp_cash_accounts
for each row when (not new.is_deleted)
execute function public.erp_r15_cashbox_definition_changed();

-- One-time cash canonicalization for existing production data.
do $$
declare r record;
begin
  for r in select company_id,id from public.erp_cash_accounts where not is_deleted loop
    perform public.erp_r15_rebind_cashbox_journals_internal(r.company_id,r.id);
  end loop;
end $$;

-- Source-owned normalization for historical purchase capitalization journals.
-- We never delete a single legacy line in isolation: the approved purchase
-- invoice is re-posted by V7.6.0 so supplier/inventory sides remain balanced.
create or replace function public.erp_r15_legacy_capitalized_purchase_invoices(
  p_company_id uuid
) returns setof uuid
language sql stable security definer set search_path=public as $$
  select distinct d.id
  from public.erp_commercial_workflow_documents d
  join public.erp_journal_entries je
    on je.company_id=d.company_id and not je.is_deleted
   and je.data->>'referenceId'=d.id::text
   and lower(coalesce(je.data->>'referenceType','')) like 'purchase_invoice%'
  join public.erp_journal_lines jl
    on jl.company_id=je.company_id and not jl.is_deleted and jl.data->>'entryId'=je.id
  join public.erp_accounts a
    on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
  where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
    and (auth.uid() is null or public.is_active_company_member(p_company_id))
    and d.status='approved' and not d.is_deleted
    and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
    and public.erp_v763_forbidden_capitalization_account(a.code,a.name)
$$;

create or replace function public.erp_r15_normalize_legacy_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_effective timestamptz;
  v_ids jsonb:='[]'::jsonb;
  v_primary text;
  v_temp_period uuid;
  v_result jsonb;
  v_needs_override boolean:=false;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module='purchases'
    and document_type='invoice' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_purchase_invoice_not_found'; end if;

  if not exists(select 1 from public.erp_r15_legacy_capitalized_purchase_invoices(p_company_id) x where x=p_invoice_id) then
    return jsonb_build_object('ok',true,'invoiceId',p_invoice_id,'alreadyCanonical',true);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('journalEntryId',je.id,'referenceType',je.data->>'referenceType') order by je.created_at,je.id),'[]'::jsonb),
         min(je.id) filter(where lower(coalesce(je.data->>'referenceType',''))='purchase_invoice')
    into v_ids,v_primary
  from public.erp_journal_entries je
  where je.company_id=p_company_id and not je.is_deleted
    and je.data->>'referenceId'=p_invoice_id::text
    and lower(coalesce(je.data->>'referenceType','')) like 'purchase_invoice%';
  if v_primary is null then
    select value->>'journalEntryId' into v_primary from jsonb_array_elements(v_ids) limit 1;
  end if;

  -- Force V760 to re-evaluate this invoice even if an older release stamped the
  -- flag before every legacy journal was actually retired.
  update public.erp_commercial_workflow_documents
  set payload=(payload-'v760NoCapitalizationNormalized')||jsonb_build_object(
      'journalEntryId',v_primary,'costJournalEntries',v_ids,
      'r15LegacyCapitalizationDetectedAt',now()),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;

  v_effective:=coalesce(d.effective_at,d.created_at,now());
  -- A historical correction must keep the original effective date. If that
  -- date is currently closed, use a transaction-local technical period. The
  -- row is inserted and deleted in the same database transaction, so other
  -- sessions never observe an opened business period.
  v_needs_override:=exists(select 1 from public.erp_operational_periods
      where company_id=p_company_id and not is_deleted and module in ('all','purchase','purchases'))
    and not exists(select 1 from public.erp_operational_periods
      where company_id=p_company_id and not is_deleted and status='open'
        and module in ('all','purchase','purchases') and v_effective between starts_at and ends_at);
  if v_needs_override then
    v_temp_period:=gen_random_uuid();
    insert into public.erp_operational_periods(
      id,company_id,module,period_name,starts_at,ends_at,status,notes,created_by,updated_by
    ) values(
      v_temp_period,p_company_id,'all','R15-TECHNICAL-RECONCILIATION-'||p_invoice_id::text,
      v_effective-interval '1 minute',v_effective+interval '1 minute','open',
      'Temporary transaction-local period for canonical legacy accounting reconciliation',auth.uid(),auth.uid()
    );
  end if;

  begin
    v_result:=public.erp_v760_normalize_purchase_invoice_posting(p_company_id,p_invoice_id);
  exception when others then
    if v_temp_period is not null then delete from public.erp_operational_periods where id=v_temp_period; end if;
    raise;
  end;
  if v_temp_period is not null then delete from public.erp_operational_periods where id=v_temp_period; end if;

  update public.erp_journal_entries
  set data=data||jsonb_build_object(
      'r15CanonicalReconciliation',true,'reconciledFromLegacyCapitalization',true,
      'r15ReconciledAt',now()),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and not is_deleted and data->>'referenceId'=p_invoice_id::text
    and lower(coalesce(data->>'referenceType','')) like 'purchase_invoice%';
  update public.erp_commercial_workflow_documents
  set payload=payload||jsonb_build_object(
      'r15CanonicalReconciliation',true,'r15ReconciledAt',now(),
      'accountingPolicy','definition_accounts_no_capitalization'),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;

  return jsonb_build_object('ok',true,'invoiceId',p_invoice_id,'normalized',true,
    'temporaryPeriodUsed',v_needs_override,'result',v_result);
end;
$$;

-- A current-state health report makes legacy contamination explicit instead of
-- allowing it to silently influence new screens/reports.
create or replace function public.erp_r15_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  with resurrected_rows(table_name,id) as (
    select 'erp_cars',id from public.erp_cars where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',id)
    union all select 'erp_car_images',id from public.erp_car_images where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_car_images',id)
    union all select 'erp_customers',id from public.erp_customers where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_customers',id)
    union all select 'erp_suppliers',id from public.erp_suppliers where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_suppliers',id)
    union all select 'erp_warehouses',id from public.erp_warehouses where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_warehouses',id)
    union all select 'erp_inventory',id from public.erp_inventory where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory',id)
    union all select 'erp_inventory_groups',id from public.erp_inventory_groups where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory_groups',id)
    union all select 'erp_product_images',id from public.erp_product_images where company_id=p_company_id and not is_deleted and public.erp_r15_pending_delete_exists(p_company_id,'erp_product_images',id)
  ), resurrected as (
    select count(*)::bigint n from resurrected_rows
  ), resurrected_warehouses as (
    select count(*)::bigint n from resurrected_rows where table_name='erp_warehouses'
  ), cap_accounts as (
    select count(*)::bigint n from public.erp_accounts a
    where a.organization_id=p_company_id and a.is_active
      and public.erp_v763_forbidden_capitalization_account(a.code,a.name)
  ), cap_lines as (
    select count(*)::bigint n
    from public.erp_journal_lines jl
    join public.erp_accounts a on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
    join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
    where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','')) in ('posted','approved','confirmed')
      and public.erp_v763_forbidden_capitalization_account(a.code,a.name)
  ), cap_invoices as (
    select count(*)::bigint n from public.erp_r15_legacy_capitalized_purchase_invoices(p_company_id)
  ), cash_diff as (
    select count(*)::bigint n from public.erp_cloud_cash_ledger_reconciliation(p_company_id)
    where abs(difference)>0.01
  ), cash_binding_issues as (
    select count(*)::bigint n
    from public.erp_cash_transactions ct
    join public.erp_cash_accounts ca
      on ca.company_id=ct.company_id and ca.id=coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id')
      and not ca.is_deleted
    left join lateral (
      select count(*)::integer n
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId' and not je.is_deleted
      where jl.company_id=ct.company_id and not jl.is_deleted
        and jl.data->>'entryId'=coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id')
        and jl.data->>'accountId'=coalesce(ca.data->>'accountId',ca.data->>'account_id')
        and upper(coalesce(nullif(jl.data->>'currency',''),je.data->>'currency',''))=
            upper(coalesce(ct.data->>'currency',''))
        and (
          (lower(coalesce(ct.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
            and abs(public.erp_try_numeric(jl.data->>'debit',0)-abs(public.erp_try_numeric(ct.data->>'amount',0)))<=0.01
            and abs(public.erp_try_numeric(jl.data->>'credit',0))<=0.01)
          or
          (lower(coalesce(ct.data->>'type','')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out')
            and abs(public.erp_try_numeric(jl.data->>'credit',0)-abs(public.erp_try_numeric(ct.data->>'amount',0)))<=0.01
            and abs(public.erp_try_numeric(jl.data->>'debit',0))<=0.01)
        )
    ) match on true
    where ct.company_id=p_company_id and not ct.is_deleted
      and nullif(coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id'),'') is not null
      and coalesce(match.n,0)<>1
  )
  select jsonb_build_object(
    'ok',(select n=0 from resurrected) and (select n=0 from cap_accounts)
      and (select n=0 from cap_lines) and (select n=0 from cash_diff)
      and (select n=0 from cash_binding_issues),
    'resurrectedMasterCount',(select n from resurrected),
    'resurrectedWarehouseCount',(select n from resurrected_warehouses),
    'activeLegacyCapitalizationAccountCount',(select n from cap_accounts),
    'historicalCapitalizationLineCount',(select n from cap_lines),
    'legacyCapitalizedPurchaseInvoiceCount',(select n from cap_invoices),
    'cashboxLedgerMismatchCount',(select n from cash_diff),
    'cashJournalBindingIssueCount',(select n from cash_binding_issues),
    'checkedAt',timezone('utc',now())
  ) into v_result;
  return v_result;
end;
$$;
-- Company-admin reconciliation is safe to re-run. It re-applies tombstones,
-- current account policy, source-normalizes legacy purchase capitalization, and
-- rebinds all cashboxes. No stale row or legacy sync can silently become the
-- canonical state again after this pass.
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_table text;
  v_cash record;
  v_invoice uuid;
  v_redeleted integer:=0;
  v_count integer;
  v_cash_results jsonb:='[]'::jsonb;
  v_invoice_results jsonb:='[]'::jsonb;
  v_invoice_failures jsonb:='[]'::jsonb;
  v_normalized integer:=0;
  v_failed integer:=0;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'update public.%I r set is_deleted=true,deleted_at=coalesce(r.deleted_at,now()),updated_at=now(),version=version+1 '
        ||'where company_id=$1 and not is_deleted and public.erp_r15_pending_delete_exists($1,%L,r.id)',v_table,v_table
      ) using p_company_id;
      get diagnostics v_count=row_count;
      v_redeleted:=v_redeleted+v_count;
    end if;
  end loop;

  update public.erp_accounts
  set is_active=false,name='حساب تاريخي متوقف - رسملة ملغاة',source_updated_at=now(),synced_at=now()
  where organization_id=p_company_id and public.erp_v763_forbidden_capitalization_account(code,name);

  for v_invoice in select * from public.erp_r15_legacy_capitalized_purchase_invoices(p_company_id) loop
    begin
      v_result:=public.erp_r15_normalize_legacy_purchase_invoice(p_company_id,v_invoice);
      v_invoice_results:=v_invoice_results||jsonb_build_array(v_result);
      v_normalized:=v_normalized+1;
    exception when others then
      v_failed:=v_failed+1;
      v_invoice_failures:=v_invoice_failures||jsonb_build_array(jsonb_build_object(
        'invoiceId',v_invoice,'sqlstate',sqlstate,'error',sqlerrm));
    end;
  end loop;

  for v_cash in select id from public.erp_cash_accounts where company_id=p_company_id and not is_deleted loop
    v_cash_results:=v_cash_results||jsonb_build_array(
      public.erp_r15_rebind_cashbox_journals_internal(p_company_id,v_cash.id));
  end loop;

  return jsonb_build_object('ok',v_failed=0,'redeletedStaleRows',v_redeleted,
    'normalizedLegacyPurchaseInvoices',v_normalized,'failedLegacyPurchaseInvoices',v_failed,
    'invoiceResults',v_invoice_results,'invoiceFailures',v_invoice_failures,
    'cashboxes',v_cash_results,'health',public.erp_r15_current_state_health(p_company_id));
end;
$$;

create or replace function public.erp_r15_runtime_contract_probe(p_company_id uuid)
returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'ok',auth.uid() is not null and public.is_active_company_member(p_company_id),
    'r15MasterList',to_regprocedure('public.erp_r15_list_cloud_master_records(uuid,text)') is not null,
    'r15MasterGet',to_regprocedure('public.erp_r15_get_cloud_master_record(uuid,text,text)') is not null,
    'r15MasterUpsert',to_regprocedure('public.erp_r15_upsert_cloud_master_record(uuid,text,text,jsonb,bigint)') is not null,
    'r15MasterDelete',to_regprocedure('public.erp_r15_soft_delete_cloud_master_record(uuid,text,text,bigint)') is not null,
    'r14Phase26',to_regprocedure('public.erp_r14_phase26_cloud_command(text,text,jsonb)') is not null,
    'r14SalesApprove',to_regprocedure('public.erp_r14_approve_sales_invoice(uuid,uuid)') is not null,
    'r14PurchaseApprove',to_regprocedure('public.erp_r14_approve_purchase_invoice(uuid,uuid)') is not null,
    'masterContractsOk',jsonb_array_length(public.erp_r14_master_contract_issues())=0,
    'masterContractIssues',public.erp_r14_master_contract_issues(),
    'currentStateHealth',public.erp_r15_current_state_health(p_company_id),
    'checkedAt',timezone('utc',now())
  )
$$;

revoke all on function public.erp_r15_pending_delete_exists(uuid,text,text) from public,anon;
revoke all on function public.erp_r15_list_cloud_master_records(uuid,text) from public,anon;
revoke all on function public.erp_r15_get_cloud_master_record(uuid,text,text) from public,anon;
revoke all on function public.erp_r15_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) from public,anon;
revoke all on function public.erp_r15_soft_delete_cloud_master_record(uuid,text,text,bigint) from public,anon;
revoke all on function public.erp_r15_list_deleted_master_ids(uuid,text) from public,anon;
revoke all on function public.erp_r15_legacy_capitalized_purchase_invoices(uuid) from public,anon;
revoke all on function public.erp_r15_normalize_legacy_purchase_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_r15_rebind_cashbox_journals(uuid,text) from public,anon;
revoke all on function public.erp_r15_current_state_health(uuid) from public,anon;
revoke all on function public.erp_r15_reconcile_company_state(uuid) from public,anon;
revoke all on function public.erp_r15_runtime_contract_probe(uuid) from public,anon;
revoke all on function public.erp_r15_rebind_cashbox_journals_internal(uuid,text) from public,anon,authenticated;
grant execute on function public.erp_r15_pending_delete_exists(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r15_list_cloud_master_records(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r15_get_cloud_master_record(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r15_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) to authenticated,service_role;
grant execute on function public.erp_r15_soft_delete_cloud_master_record(uuid,text,text,bigint) to authenticated,service_role;
grant execute on function public.erp_r15_list_deleted_master_ids(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r15_legacy_capitalized_purchase_invoices(uuid) to authenticated,service_role;
grant execute on function public.erp_r15_normalize_legacy_purchase_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r15_rebind_cashbox_journals(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r15_current_state_health(uuid) to authenticated,service_role;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated,service_role;
grant execute on function public.erp_r15_runtime_contract_probe(uuid) to authenticated,service_role;
grant execute on function public.erp_r15_rebind_cashbox_journals_internal(uuid,text) to service_role;

notify pgrst,'reload schema';
commit;
