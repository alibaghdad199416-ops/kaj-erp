-- Quality Line ERP R14 runtime RPC / invoice root closure.
-- Root causes addressed:
--   1) R9 generic master reads could raise HTTP 500 on malformed JSON/legacy metadata.
--   2) R9 table triggers enforced user field permissions on server-owned workflow writes.
--   3) Phase-26 facade was created without an explicit PostgREST schema reload in its final migration.
--   4) Invoice approval needs one stable, diagnosable RPC surface while preserving V23.0.2 accounting policy.
begin;

create or replace function public.erp_r14_try_boolean(
  p_value text,
  p_default boolean default false
) returns boolean
language sql
immutable
as $$
  select case lower(btrim(coalesce(p_value,'')))
    when 'true' then true when 't' then true when '1' then true when 'yes' then true when 'y' then true when 'on' then true
    when 'false' then false when 'f' then false when '0' then false when 'no' then false when 'n' then false when 'off' then false
    else coalesce(p_default,false)
  end
$$;

-- Harden the permission resolver. Legacy JSON must never turn an ordinary read
-- into a PostgreSQL 500 because an old boolean value is blank/non-canonical.
create or replace function public.erp_cloud_user_has_permission(
  p_company_id uuid,
  p_permission_code text
) returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_user_id text;
  v_role_id text;
  v_has_override boolean := false;
begin
  if p_company_id is null
     or btrim(coalesce(p_permission_code,''))=''
     or not public.is_active_company_member(p_company_id) then
    return false;
  end if;

  if public.is_company_admin(p_company_id)
     or public.erp_has_permission(p_company_id,btrim(p_permission_code)) then
    return true;
  end if;

  select slug into v_slug
  from public.companies
  where id=p_company_id and is_active
  limit 1;
  v_user_id:=public.erp_current_cloud_erp_user_id(p_company_id);
  if v_slug is null or v_user_id is null then return false; end if;

  select exists(
    select 1
    from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='user_permission_overrides'
      and r.record_id=v_user_id
      and r.deleted_at is null and not r.is_deleted
      and public.erp_r14_try_boolean(r.payload->>'enabled',true)
  ) into v_has_override;

  if v_has_override then
    return exists(
      select 1
      from public.erp_records up
      join public.erp_records p
        on p.company_id=v_slug
       and p.entity_type='permissions'
       and p.record_id=up.payload->>'permissionId'
       and p.deleted_at is null and not p.is_deleted
      where up.company_id=v_slug
        and up.entity_type='user_permissions'
        and up.payload->>'userId'=v_user_id
        and up.deleted_at is null and not up.is_deleted
        and p.payload->>'code'=btrim(p_permission_code)
    );
  end if;

  select payload->>'roleId' into v_role_id
  from public.erp_records
  where company_id=v_slug and entity_type='users' and record_id=v_user_id
    and deleted_at is null and not is_deleted
  limit 1;
  if v_role_id is null then return false; end if;

  return exists(
    select 1
    from public.erp_records rp
    join public.erp_records p
      on p.company_id=v_slug
     and p.entity_type='permissions'
     and p.record_id=rp.payload->>'permissionId'
     and p.deleted_at is null and not p.is_deleted
    where rp.company_id=v_slug
      and rp.entity_type='role_permissions'
      and rp.payload->>'roleId'=v_role_id
      and rp.deleted_at is null and not rp.is_deleted
      and p.payload->>'code'=btrim(p_permission_code)
  );
end;
$$;

-- Fail-safe JSON filtering: malformed legacy payloads are treated as empty
-- business objects instead of causing jsonb_each() to raise HTTP 500.
create or replace function public.erp_r9_filter_readable_master_json(
  p_company_id uuid,
  p_table text,
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_resource text:=public.erp_r9_master_resource_for_table(p_table);
  v_result jsonb:='{}'::jsonb;
  v_item record;
  v_field text;
begin
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_resource||'.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_field:=public.erp_r9_master_field_for_table_key(p_table,v_item.key);
    if v_field is not null
       and public.erp_cloud_user_can_view_field(p_company_id,v_resource,v_field,null) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_guard_writable_master_json(
  p_company_id uuid,
  p_table text,
  p_existing jsonb,
  p_incoming jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_resource text:=public.erp_r9_master_resource_for_table(p_table);
  v_existing jsonb:=case when jsonb_typeof(coalesce(p_existing,'{}'::jsonb))='object' then coalesce(p_existing,'{}'::jsonb) else '{}'::jsonb end;
  v_result jsonb;
  v_item record;
  v_field text;
begin
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table; end if;
  if p_incoming is null or jsonb_typeof(p_incoming)<>'object' then
    raise exception 'master_payload_must_be_object' using errcode='22023';
  end if;
  v_result:=p_incoming;
  if not public.erp_cloud_user_has_permission(p_company_id,v_resource||'.fields.restrict') then
    return v_result;
  end if;

  for v_item in select key,value from jsonb_each(p_incoming) loop
    v_field:=public.erp_r9_master_field_for_table_key(p_table,v_item.key);
    if v_field is null
       or not public.erp_cloud_user_can_edit_field(p_company_id,v_resource,v_field,null) then
      if v_existing ? v_item.key then
        v_result:=jsonb_set(v_result,array[v_item.key],v_existing->v_item.key,true);
      else
        v_result:=v_result-v_item.key;
      end if;
    end if;
  end loop;

  for v_item in select key,value from jsonb_each(v_existing) loop
    v_field:=public.erp_r9_master_field_for_table_key(p_table,v_item.key);
    if (v_field is null
        or not public.erp_cloud_user_can_edit_field(p_company_id,v_resource,v_field,null))
       and not (v_result ? v_item.key) then
      v_result:=v_result||jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

-- The generic R9 write RPC already calls erp_r9_guard_writable_master_json and
-- direct authenticated DML is revoked. These row triggers therefore duplicated
-- authorization and incorrectly filtered server-owned inventory/accounting
-- mutations made by SECURITY DEFINER workflow functions. Remove them.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images',
    'erp_car_warehouse_transfers','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_warehouse_stock','erp_inventory_movements','erp_cash_accounts','erp_cash_transactions',
    'erp_expenses','erp_journal_entries','erp_installments','erp_sales','erp_purchases','erp_purchase_items'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop trigger if exists aa_r9_field_write_guard on public.%I',v_table);
    end if;
  end loop;
end $$;

-- Commercial/maintenance tables remain field-protected, but permission checks
-- now run only when a user-editable input column actually changes. Server-owned
-- status/accounting/timestamps may change during approve/cancel/post without
-- incorrectly requiring *.update in addition to the operation permission.
create or replace function public.erp_r9_guard_input_fields()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_resource text:=coalesce(TG_ARGV[0],'');
  v_insert_permission text:=nullif(coalesce(TG_ARGV[1],''),'');
  v_update_permission text:=nullif(coalesce(TG_ARGV[2],''),'');
  v_base_permission text;
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_pair text;
  v_column text;
  v_field text;
  v_index integer;
  v_changed boolean;
  v_any_user_field_changed boolean:=false;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then return new; end if;

  v_company_id:=nullif(v_new->>'company_id','')::uuid;
  if v_company_id is null then raise exception 'field_permission_company_required' using errcode='22023'; end if;

  if TG_NARGS>3 then
    for v_index in 3..TG_NARGS-1 loop
      v_pair:=TG_ARGV[v_index];
      v_column:=split_part(v_pair,'=',1);
      v_field:=split_part(v_pair,'=',2);
      if v_column='' or v_field='' then continue; end if;
      if TG_OP='INSERT' then
        v_changed:=v_new ? v_column and jsonb_typeof(v_new->v_column) is distinct from 'null';
      else
        v_changed:=(v_old->v_column) is distinct from (v_new->v_column);
      end if;
      if not v_changed then continue; end if;
      v_any_user_field_changed:=true;
      if not public.erp_cloud_user_can_edit_field(v_company_id,v_resource,v_field,null) then
        raise exception 'field_permission_denied:%.%',v_resource,v_field using errcode='42501';
      end if;
    end loop;
  end if;

  -- Status, workflow stage, posted references, audit timestamps and other
  -- server-owned columns must not trigger the generic update permission.
  if not v_any_user_field_changed then return new; end if;

  v_base_permission:=case when TG_OP='INSERT' then v_insert_permission else v_update_permission end;
  if v_base_permission is not null
     and not public.erp_cloud_user_has_permission(v_company_id,v_base_permission) then
    raise exception 'permission_denied:%',v_base_permission using errcode='42501';
  end if;
  return new;
end;
$$;

-- Every table exposed through the generic master gateway must satisfy one exact
-- storage contract. This is checked both before dynamic SQL and by the runtime
-- production probe, so a legacy table can never surface as an opaque HTTP 500.
create or replace function public.erp_r14_master_table_contract_ok(
  p_table text
) returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_rel regclass;
  v_column text;
begin
  if public.erp_r9_master_resource_for_table(p_table) is null then return false; end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then return false; end if;
  if not exists(select 1 from pg_attribute where attrelid=v_rel and attname='company_id' and atttypid='uuid'::regtype and not attisdropped) then return false; end if;
  if not exists(select 1 from pg_attribute where attrelid=v_rel and attname='id' and atttypid='text'::regtype and not attisdropped) then return false; end if;
  if not exists(select 1 from pg_attribute where attrelid=v_rel and attname='data' and atttypid='jsonb'::regtype and not attisdropped) then return false; end if;
  if not exists(select 1 from pg_attribute where attrelid=v_rel and attname='version' and atttypid='bigint'::regtype and not attisdropped) then return false; end if;
  if not exists(select 1 from pg_attribute where attrelid=v_rel and attname='updated_at' and atttypid='timestamp with time zone'::regtype and not attisdropped) then return false; end if;
  if not exists(select 1 from pg_attribute where attrelid=v_rel and attname='is_deleted' and atttypid='boolean'::regtype and not attisdropped) then return false; end if;
  return true;
end;
$$;

create or replace function public.erp_r14_master_contract_issues()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_table text;
  v_issues jsonb:='[]'::jsonb;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images',
    'erp_car_warehouse_transfers','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_warehouse_stock','erp_inventory_movements','erp_cash_accounts','erp_cash_transactions',
    'erp_expenses','erp_journal_entries','erp_installments','erp_sales','erp_purchases','erp_purchase_items'
  ] loop
    if not public.erp_r14_master_table_contract_ok(v_table) then
      v_issues:=v_issues||jsonb_build_array(v_table);
    end if;
  end loop;
  return v_issues;
end;
$$;

-- Rebuild R9 list/get for immediate backward compatibility with the already
-- deployed R13 client. R14 browser code uses new R14 facade names below.
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,
  p_table text
) returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
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
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023',
      hint='Required typed columns: company_id uuid,id text,data jsonb,version bigint,updated_at timestamptz,is_deleted boolean';
  end if;

  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_row in execute format(
    'select id::text id,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end data,'||
    'version,updated_at from public.%I where company_id=$1 and not coalesce(is_deleted,false) order by updated_at desc',
    p_table
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
      ||jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
  end loop;
  return;
end;
$$;

create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
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
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023',
      hint='Required typed columns: company_id uuid,id text,data jsonb,version bigint,updated_at timestamptz,is_deleted boolean';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  execute format(
    'select id::text id,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end data,'||
    'version,updated_at from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false) limit 1',
    p_table
  ) into v_row using p_company_id,p_record_id;
  if not found then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
    ||jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
end;
$$;

-- R14 is the browser-facing master contract. The old R9 names remain redefined
-- above only so the already deployed R13 client recovers immediately after the
-- database migration, before Firebase Hosting is replaced.
create or replace function public.erp_r14_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language sql stable security definer set search_path=public as $$
  select * from public.erp_r9_list_cloud_master_records($1,$2)
$$;

create or replace function public.erp_r14_get_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text
) returns jsonb
language sql stable security definer set search_path=public as $$
  select public.erp_r9_get_cloud_master_record($1,$2,$3)
$$;

create or replace function public.erp_r14_upsert_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text,p_data jsonb,p_expected_version bigint default null
) returns jsonb
language sql security definer set search_path=public as $$
  select public.erp_r9_upsert_cloud_master_record($1,$2,$3,$4,$5)
$$;

create or replace function public.erp_r14_soft_delete_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text,p_expected_version bigint default null
) returns jsonb
language sql security definer set search_path=public as $$
  select public.erp_r9_soft_delete_cloud_master_record($1,$2,$3,$4)
$$;

create or replace function public.erp_r14_list_deleted_master_ids(
  p_company_id uuid,p_table text
) returns setof text
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_id text;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  for v_id in execute format(
    'select id::text from public.%I where company_id=$1 and coalesce(is_deleted,false)',p_table
  ) using p_company_id loop
    return next v_id;
  end loop;
  return;
end;
$$;

-- Stable facade exposed after an explicit schema reload. Keeping R9 as the
-- implementation preserves granular permission behavior while R14 becomes the
-- browser contract used by the current application.
create or replace function public.erp_r14_phase26_cloud_command(
  p_area text,
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language sql
security definer
set search_path=public
as $$
  select public.erp_r9_phase26_cloud_command($1,$2,coalesce($3,'{}'::jsonb))
$$;

-- One authoritative approval surface for sales/purchases. V23.0.2 already
-- guarantees: sales revenue follows invoice currency; sales FIFO/COGS follows
-- each definition currency; purchase remains single-definition-currency.
create or replace function public.erp_r14_approve_workflow_invoice(
  p_company_id uuid,
  p_invoice_id uuid,
  p_module text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_preflight jsonb;
  v_result jsonb;
  v_required_permission text;
begin
  if p_module not in ('sales','purchases') then
    return jsonb_build_object('ok',false,'code','R14_MODULE','error','invalid_workflow_module','module',p_module);
  end if;
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    return jsonb_build_object('ok',false,'code','42501','error','company_membership_required');
  end if;
  v_required_permission:=case when p_module='sales' then 'sales.approve' else 'purchases.approve' end;
  if not public.erp_cloud_user_has_permission(p_company_id,v_required_permission)
     and not public.is_company_admin(p_company_id) then
    return jsonb_build_object('ok',false,'code','42501','error','permission_denied:'||v_required_permission);
  end if;

  begin
    v_preflight:=public.erp_v767_invoice_policy_preflight(p_company_id,p_invoice_id,p_module);
  exception when others then
    return jsonb_build_object(
      'ok',false,'stage','preflight','code',sqlstate,'error',sqlerrm,
      'details',jsonb_build_object('module',p_module,'invoiceId',p_invoice_id)::text,
      'hint','Check partner account for invoice currency and definition inventory/COGS/revenue accounts.'
    );
  end;

  begin
    v_result:=public.erp_v762_approve_workflow_invoice(p_company_id,p_invoice_id,p_module);
  exception when others then
    return jsonb_build_object(
      'ok',false,'stage','posting','code',sqlstate,'error',sqlerrm,
      'details',jsonb_build_object('module',p_module,'invoiceId',p_invoice_id,'preflight',v_preflight)::text,
      'hint','Posting failed after preflight. Inspect the returned database error; no silent fallback is accepted.'
    );
  end;

  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'version','r14','preflight',v_preflight
  );
end;
$$;

create or replace function public.erp_r14_approve_sales_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language sql security definer set search_path=public as $$
  select public.erp_r14_approve_workflow_invoice($1,$2,'sales')
$$;

create or replace function public.erp_r14_approve_purchase_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language sql security definer set search_path=public as $$
  select public.erp_r14_approve_workflow_invoice($1,$2,'purchases')
$$;

-- Runtime probe used for production diagnostics without exposing secrets/data.
create or replace function public.erp_r14_runtime_contract_probe()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'ok',auth.uid() is not null,
    'r9MasterList',to_regprocedure('public.erp_r9_list_cloud_master_records(uuid,text)') is not null,
    'r14MasterList',to_regprocedure('public.erp_r14_list_cloud_master_records(uuid,text)') is not null,
    'r14MasterGet',to_regprocedure('public.erp_r14_get_cloud_master_record(uuid,text,text)') is not null,
    'r14MasterUpsert',to_regprocedure('public.erp_r14_upsert_cloud_master_record(uuid,text,text,jsonb,bigint)') is not null,
    'r14MasterDelete',to_regprocedure('public.erp_r14_soft_delete_cloud_master_record(uuid,text,text,bigint)') is not null,
    'masterContractIssues',public.erp_r14_master_contract_issues(),
    'masterContractsOk',jsonb_array_length(public.erp_r14_master_contract_issues())=0,
    'r9Phase26',to_regprocedure('public.erp_r9_phase26_cloud_command(text,text,jsonb)') is not null,
    'r14Phase26',to_regprocedure('public.erp_r14_phase26_cloud_command(text,text,jsonb)') is not null,
    'r14SalesApprove',to_regprocedure('public.erp_r14_approve_sales_invoice(uuid,uuid)') is not null,
    'r14PurchaseApprove',to_regprocedure('public.erp_r14_approve_purchase_invoice(uuid,uuid)') is not null,
    'checkedAt',timezone('utc',now())
  )
$$;

revoke all on function public.erp_r14_master_table_contract_ok(text) from public,anon;
revoke all on function public.erp_r14_master_contract_issues() from public,anon;
revoke all on function public.erp_r14_list_cloud_master_records(uuid,text) from public,anon;
revoke all on function public.erp_r14_get_cloud_master_record(uuid,text,text) from public,anon;
revoke all on function public.erp_r14_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) from public,anon;
revoke all on function public.erp_r14_soft_delete_cloud_master_record(uuid,text,text,bigint) from public,anon;
revoke all on function public.erp_r14_list_deleted_master_ids(uuid,text) from public,anon;
revoke all on function public.erp_r14_try_boolean(text,boolean) from public,anon;
revoke all on function public.erp_r14_phase26_cloud_command(text,text,jsonb) from public,anon;
revoke all on function public.erp_r14_approve_workflow_invoice(uuid,uuid,text) from public,anon;
revoke all on function public.erp_r14_approve_sales_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_r14_approve_purchase_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_r14_runtime_contract_probe() from public,anon;
grant execute on function public.erp_r14_master_table_contract_ok(text) to authenticated,service_role;
grant execute on function public.erp_r14_master_contract_issues() to authenticated,service_role;
grant execute on function public.erp_r14_list_cloud_master_records(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r14_get_cloud_master_record(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r14_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) to authenticated,service_role;
grant execute on function public.erp_r14_soft_delete_cloud_master_record(uuid,text,text,bigint) to authenticated,service_role;
grant execute on function public.erp_r14_list_deleted_master_ids(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r14_try_boolean(text,boolean) to authenticated,service_role;
grant execute on function public.erp_r14_phase26_cloud_command(text,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_r14_approve_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_r14_approve_sales_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r14_approve_purchase_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r14_runtime_contract_probe() to authenticated,service_role;
grant execute on function public.erp_r9_list_cloud_master_records(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_get_cloud_master_record(uuid,text,text) to authenticated,service_role;

-- The missing explicit reload after the R9 Phase-26 facade was the source of
-- PGRST404/PGRST202-style runtime exposure failures after production db push.
notify pgrst,'reload schema';
commit;
