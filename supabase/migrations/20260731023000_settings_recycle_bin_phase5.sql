-- Phase 5: centralized recycle bin, safe restore and permissioned purge.

create or replace function public.erp_recycle_bin_list(
  p_company_id uuid,
  p_query text default '',
  p_entity_type text default ''
)
returns table(
  entity_type text,
  record_id text,
  payload jsonb,
  deleted_at timestamptz,
  deleted_by text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.entity_type,
         r.record_id,
         r.payload,
         r.deleted_at,
         coalesce(r.payload->>'deletedByUserName', r.payload->>'deletedBy', '')
  from public.erp_records r
  where r.company_id = p_company_id::text
    and public.is_company_member(p_company_id)
    and r.deleted_at is not null
    and (coalesce(trim(p_entity_type), '') = '' or r.entity_type = trim(p_entity_type))
    and (
      coalesce(trim(p_query), '') = ''
      or r.record_id ilike '%' || trim(p_query) || '%'
      or r.entity_type ilike '%' || trim(p_query) || '%'
      or r.payload::text ilike '%' || trim(p_query) || '%'
    )
  order by r.deleted_at desc;
$$;

create or replace function public.erp_recycle_bin_restore(
  p_company_id uuid,
  p_entity_type text,
  p_record_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.erp_records%rowtype;
  v_now timestamptz := now();
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;
  if not public.erp_has_permission(p_company_id, 'settings.recycle_bin.restore')
     and not public.erp_has_permission(p_company_id, 'settings.restore') then
    raise exception 'restore_permission_required';
  end if;

  select * into v_row
  from public.erp_records
  where company_id = p_company_id::text
    and entity_type = trim(p_entity_type)
    and record_id = trim(p_record_id)
  for update;

  if not found then raise exception 'deleted_record_not_found'; end if;
  if v_row.deleted_at is null then raise exception 'record_is_already_active'; end if;

  -- The compatibility store uses a tenant/entity/id primary key, therefore an
  -- active record cannot silently replace this tombstone. Normalized-table
  -- restores remain blocked when the payload explicitly records a conflict.
  if coalesce(v_row.payload->>'restoreConflict', '') <> '' then
    raise exception 'restore_conflict: %', v_row.payload->>'restoreConflict';
  end if;

  update public.erp_records
  set deleted_at = null,
      updated_at = v_now,
      payload = (v_row.payload
        - 'deletedAt' - 'deleted_at' - 'deletedBy' - 'deletedByUserName'
        - 'deleteReason' - 'restoreConflict')
        || jsonb_build_object(
          'isDeleted', false,
          'is_deleted', false,
          'restoredAt', v_now,
          'restoredBy', auth.uid()::text
        )
  where company_id = p_company_id::text
    and entity_type = trim(p_entity_type)
    and record_id = trim(p_record_id);

  -- Restore soft-deleted compatibility children that explicitly point to the
  -- parent. This is intentionally conservative and never guesses relations.
  update public.erp_records child
  set deleted_at = null,
      updated_at = v_now,
      payload = (child.payload - 'deletedAt' - 'deleted_at')
        || jsonb_build_object('isDeleted', false, 'is_deleted', false, 'restoredAt', v_now)
  where child.company_id = p_company_id::text
    and child.deleted_at is not null
    and coalesce(child.payload->>'deletedWithParent', 'false') = 'true'
    and (
      child.payload->>'parentId' = trim(p_record_id)
      or child.payload->>'sourceId' = trim(p_record_id)
      or child.payload->>'documentId' = trim(p_record_id)
    );

  return jsonb_build_object('restored', true, 'entityType', p_entity_type, 'recordId', p_record_id);
end;
$$;

create or replace function public.erp_recycle_bin_purge(
  p_company_id uuid,
  p_entity_type text,
  p_record_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  if not public.is_company_member(p_company_id) then raise exception 'access_denied'; end if;
  if not public.erp_has_permission(p_company_id, 'settings.recycle_bin.purge') then
    raise exception 'permanent_delete_permission_required';
  end if;

  delete from public.erp_records
  where company_id = p_company_id::text
    and entity_type = trim(p_entity_type)
    and record_id = trim(p_record_id)
    and deleted_at is not null;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then raise exception 'deleted_record_not_found'; end if;
  return jsonb_build_object('purged', true, 'entityType', p_entity_type, 'recordId', p_record_id);
end;
$$;

revoke all on function public.erp_recycle_bin_list(uuid,text,text) from public, anon;
revoke all on function public.erp_recycle_bin_restore(uuid,text,text) from public, anon;
revoke all on function public.erp_recycle_bin_purge(uuid,text,text) from public, anon;
grant execute on function public.erp_recycle_bin_list(uuid,text,text) to authenticated;
grant execute on function public.erp_recycle_bin_restore(uuid,text,text) to authenticated;
grant execute on function public.erp_recycle_bin_purge(uuid,text,text) to authenticated;

-- Register permissions in the enterprise catalog when that table is available.
do $$
begin
  if to_regclass('public.erp_permissions') is not null then
    insert into public.erp_permissions(code, module, action, description)
    values
      ('settings.recycle_bin.view','settings','view','View recycle bin'),
      ('settings.recycle_bin.restore','settings','restore','Restore deleted records'),
      ('settings.recycle_bin.purge','settings','purge','Permanently delete records')
    on conflict (code) do nothing;
  end if;
end $$;
