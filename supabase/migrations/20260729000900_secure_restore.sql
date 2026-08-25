-- Quality Line ERP 17.73.0
-- Tenant-scoped logical backups with checksum validation, admin-only restore,
-- automatic pre-restore safety snapshots and immutable audit metadata.

create table if not exists public.erp_backup_snapshots (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  backup_name text not null,
  schema_version text not null default '17.73.0',
  backup_kind text not null default 'manual'
    check (backup_kind in ('manual', 'scheduled', 'pre_restore')),
  payload jsonb not null,
  manifest jsonb not null default '[]'::jsonb,
  checksum text not null,
  row_count bigint not null default 0,
  size_bytes bigint not null default 0,
  created_by text,
  created_at timestamptz not null default now(),
  restored_at timestamptz,
  restored_by text,
  restore_count integer not null default 0,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  deleted_by text
);

create index if not exists erp_backup_snapshots_company_created_idx
  on public.erp_backup_snapshots(company_id, created_at desc)
  where not is_deleted;

alter table public.erp_backup_snapshots enable row level security;

drop policy if exists erp_backup_snapshots_admin_select on public.erp_backup_snapshots;
create policy erp_backup_snapshots_admin_select
on public.erp_backup_snapshots for select to authenticated
using (public.is_company_admin(company_id));

revoke all on public.erp_backup_snapshots from anon, authenticated;
grant select on public.erp_backup_snapshots to authenticated;

create or replace function public.erp_backup_table_manifest()
returns table(table_name text, dependency_depth integer)
language sql
stable
security definer
set search_path = public
as $$
  with recursive tenant_tables as (
    select c.oid, c.relname::text as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relname <> 'erp_backup_snapshots'
      and exists (
        select 1 from pg_attribute a
        where a.attrelid = c.oid and a.attname = 'company_id' and not a.attisdropped
      )
  ), edges as (
    select child.oid as child_oid, parent.oid as parent_oid
    from pg_constraint fk
    join tenant_tables child on child.oid = fk.conrelid
    join tenant_tables parent on parent.oid = fk.confrelid
    where fk.contype = 'f' and child.oid <> parent.oid
  ), walk(root_oid, node_oid, depth, path) as (
    select t.oid, t.oid, 0, array[t.oid]
    from tenant_tables t
    union all
    select w.root_oid, e.parent_oid, w.depth + 1, w.path || e.parent_oid
    from walk w
    join edges e on e.child_oid = w.node_oid
    where not e.parent_oid = any(w.path) and w.depth < 32
  )
  select t.table_name, coalesce(max(w.depth), 0)::integer as dependency_depth
  from tenant_tables t
  left join walk w on w.root_oid = t.oid
  group by t.table_name
  order by dependency_depth asc, t.table_name asc;
$$;

create or replace function public.erp_build_tenant_backup_payload(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb := '{}'::jsonb;
  v_rows jsonb;
  v_table record;
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'backup_admin_required' using errcode = '42501';
  end if;

  for v_table in select * from public.erp_backup_table_manifest() loop
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(t) order by t.ctid), ''[]''::jsonb) from public.%I t where company_id = $1',
      v_table.table_name
    ) into v_rows using p_company_id;
    v_payload := v_payload || jsonb_build_object(v_table.table_name, v_rows);
  end loop;

  return v_payload;
end;
$$;

create or replace function public.erp_create_backup_snapshot(
  p_company_id uuid,
  p_backup_name text default null,
  p_backup_kind text default 'manual'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_payload jsonb;
  v_manifest jsonb;
  v_checksum text;
  v_row_count bigint := 0;
  v_size bigint := 0;
  v_user text := coalesce(auth.uid()::text, public.current_external_uid(), 'unknown');
  v_item record;
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'backup_admin_required' using errcode = '42501';
  end if;
  if p_backup_kind not in ('manual', 'scheduled', 'pre_restore') then
    raise exception 'invalid_backup_kind';
  end if;

  v_payload := public.erp_build_tenant_backup_payload(p_company_id);
  select coalesce(jsonb_agg(jsonb_build_object(
    'table', table_name,
    'dependency_depth', dependency_depth,
    'rows', jsonb_array_length(coalesce(v_payload -> table_name, '[]'::jsonb))
  ) order by dependency_depth, table_name), '[]'::jsonb)
  into v_manifest
  from public.erp_backup_table_manifest();

  for v_item in select value from jsonb_each(v_payload) loop
    v_row_count := v_row_count + jsonb_array_length(v_item.value);
  end loop;

  v_checksum := md5(v_payload::text || '|17.73.0|' || p_company_id::text);
  v_size := octet_length(convert_to(v_payload::text, 'UTF8'));

  insert into public.erp_backup_snapshots(
    id, company_id, backup_name, backup_kind, payload, manifest,
    checksum, row_count, size_bytes, created_by
  ) values (
    v_id, p_company_id,
    coalesce(nullif(trim(p_backup_name), ''), 'Backup ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS')),
    p_backup_kind, v_payload, v_manifest, v_checksum, v_row_count, v_size, v_user
  );

  return jsonb_build_object(
    'ok', true, 'backup_id', v_id, 'company_id', p_company_id,
    'schema_version', '17.73.0', 'checksum', v_checksum,
    'row_count', v_row_count, 'size_bytes', v_size, 'created_at', now()
  );
end;
$$;

create or replace function public.erp_validate_backup_snapshot(p_company_id uuid, p_backup_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_backup public.erp_backup_snapshots%rowtype;
  v_expected text;
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'backup_admin_required' using errcode = '42501';
  end if;
  select * into v_backup from public.erp_backup_snapshots
   where id = p_backup_id and company_id = p_company_id and not is_deleted;
  if not found then raise exception 'backup_not_found'; end if;

  v_expected := md5(v_backup.payload::text || '|' || v_backup.schema_version || '|' || p_company_id::text);
  return jsonb_build_object(
    'ok', v_expected = v_backup.checksum,
    'backup_id', v_backup.id,
    'checksum_valid', v_expected = v_backup.checksum,
    'schema_supported', v_backup.schema_version = '17.73.0',
    'row_count', v_backup.row_count,
    'size_bytes', v_backup.size_bytes,
    'checked_at', now()
  );
end;
$$;

create or replace function public.erp_list_backup_snapshots(p_company_id uuid)
returns table(
  id uuid, backup_name text, backup_kind text, schema_version text,
  checksum text, row_count bigint, size_bytes bigint,
  created_by text, created_at timestamptz, restore_count integer, restored_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'backup_admin_required' using errcode = '42501';
  end if;
  return query
  select b.id, b.backup_name, b.backup_kind, b.schema_version,
         b.checksum, b.row_count, b.size_bytes,
         b.created_by, b.created_at, b.restore_count, b.restored_at
  from public.erp_backup_snapshots b
  where b.company_id = p_company_id and not b.is_deleted
  order by b.created_at desc;
end;
$$;

create or replace function public.erp_restore_backup_snapshot(
  p_company_id uuid,
  p_backup_id uuid,
  p_create_safety_backup boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_backup public.erp_backup_snapshots%rowtype;
  v_validation jsonb;
  v_table record;
  v_rows jsonb;
  v_safety jsonb;
  v_user text := coalesce(auth.uid()::text, public.current_external_uid(), 'unknown');
  v_restored bigint := 0;
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'restore_admin_required' using errcode = '42501';
  end if;

  select * into v_backup from public.erp_backup_snapshots
  where id = p_backup_id and company_id = p_company_id and not is_deleted
  for update;
  if not found then raise exception 'backup_not_found'; end if;

  v_validation := public.erp_validate_backup_snapshot(p_company_id, p_backup_id);
  if not coalesce((v_validation ->> 'ok')::boolean, false) then
    raise exception 'backup_validation_failed';
  end if;
  if v_backup.schema_version <> '17.73.0' then
    raise exception 'unsupported_backup_schema_version';
  end if;

  if p_create_safety_backup then
    v_safety := public.erp_create_backup_snapshot(
      p_company_id,
      'Pre-restore safety backup ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS'),
      'pre_restore'
    );
  end if;

  -- Delete children before parents.
  for v_table in
    select * from public.erp_backup_table_manifest()
    order by dependency_depth desc, table_name desc
  loop
    execute format('delete from public.%I where company_id = $1', v_table.table_name)
    using p_company_id;
  end loop;

  -- Insert parents before children. Any failure aborts the entire transaction.
  for v_table in
    select * from public.erp_backup_table_manifest()
    order by dependency_depth asc, table_name asc
  loop
    v_rows := coalesce(v_backup.payload -> v_table.table_name, '[]'::jsonb);
    if jsonb_array_length(v_rows) > 0 then
      execute format(
        'insert into public.%I select * from jsonb_populate_recordset(null::public.%I, $1)',
        v_table.table_name, v_table.table_name
      ) using v_rows;
      v_restored := v_restored + jsonb_array_length(v_rows);
    end if;
  end loop;

  update public.erp_backup_snapshots
  set restored_at = now(), restored_by = v_user, restore_count = restore_count + 1
  where id = p_backup_id;

  return jsonb_build_object(
    'ok', true, 'backup_id', p_backup_id, 'company_id', p_company_id,
    'restored_rows', v_restored, 'restored_at', now(),
    'safety_backup_id', v_safety ->> 'backup_id'
  );
end;
$$;

create or replace function public.erp_delete_backup_snapshot(p_company_id uuid, p_backup_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'backup_admin_required' using errcode = '42501';
  end if;
  update public.erp_backup_snapshots
  set is_deleted = true, deleted_at = now(),
      deleted_by = coalesce(auth.uid()::text, public.current_external_uid(), 'unknown'),
      payload = '{}'::jsonb
  where id = p_backup_id and company_id = p_company_id and not is_deleted;
  return found;
end;
$$;

create or replace function public.erp_backup_restore_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count bigint;
  v_invalid bigint;
begin
  if not public.is_company_admin(p_company_id) then
    raise exception 'backup_admin_required' using errcode = '42501';
  end if;
  select count(*), count(*) filter (
    where checksum <> md5(payload::text || '|' || schema_version || '|' || company_id::text)
  ) into v_count, v_invalid
  from public.erp_backup_snapshots
  where company_id = p_company_id and not is_deleted;

  return jsonb_build_object(
    'ok', v_invalid = 0,
    'company_id', p_company_id,
    'snapshot_count', v_count,
    'invalid_checksum_count', v_invalid,
    'supported_schema_version', '17.73.0',
    'checked_at', now()
  );
end;
$$;

revoke all on function public.erp_backup_table_manifest() from public;
revoke all on function public.erp_build_tenant_backup_payload(uuid) from public;
revoke all on function public.erp_create_backup_snapshot(uuid,text,text) from public;
revoke all on function public.erp_validate_backup_snapshot(uuid,uuid) from public;
revoke all on function public.erp_list_backup_snapshots(uuid) from public;
revoke all on function public.erp_restore_backup_snapshot(uuid,uuid,boolean) from public;
revoke all on function public.erp_delete_backup_snapshot(uuid,uuid) from public;
revoke all on function public.erp_backup_restore_health(uuid) from public;

grant execute on function public.erp_create_backup_snapshot(uuid,text,text) to authenticated;
grant execute on function public.erp_validate_backup_snapshot(uuid,uuid) to authenticated;
grant execute on function public.erp_list_backup_snapshots(uuid) to authenticated;
grant execute on function public.erp_restore_backup_snapshot(uuid,uuid,boolean) to authenticated;
grant execute on function public.erp_delete_backup_snapshot(uuid,uuid) to authenticated;
grant execute on function public.erp_backup_restore_health(uuid) to authenticated;
