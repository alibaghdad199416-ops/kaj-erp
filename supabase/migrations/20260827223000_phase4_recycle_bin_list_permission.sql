-- Phase 4: enforce the recycle-bin view permission on the final universal list RPC.
-- The UI gate is not a security boundary; the security-definer RPC must enforce it too.

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
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;
  if not public.erp_has_permission(p_company_id, 'settings.recycleBin.view')
     and not public.erp_has_permission(p_company_id, 'settings.recycle_bin.view')
     and not public.erp_has_permission(p_company_id, 'settings.view') then
    raise exception 'recycle_bin_view_permission_required';
  end if;

  return query
  select x.entity_type, x.record_id, x.payload, x.deleted_at, x.deleted_by
  from (
    select r.entity_type, r.record_id, r.payload, r.deleted_at,
      coalesce(r.payload->>'deletedByUserName', r.payload->>'deletedBy', '') as deleted_by
    from public.erp_records r
    where r.company_id = p_company_id::text and r.deleted_at is not null
    union all
    select u.source_table, u.record_id, u.payload, u.deleted_at,
      coalesce(u.deleted_by::text, '')
    from public.erp_universal_recycle_bin u
    where (u.company_id = p_company_id or u.company_id is null)
      and u.restored_at is null and u.purged_at is null
  ) x
  where (coalesce(trim(p_entity_type), '') = '' or x.entity_type = trim(p_entity_type))
    and (
      coalesce(trim(p_query), '') = ''
      or x.record_id ilike '%' || trim(p_query) || '%'
      or x.entity_type ilike '%' || trim(p_query) || '%'
      or x.payload::text ilike '%' || trim(p_query) || '%'
    )
  order by x.deleted_at desc;
end;
$$;

revoke all on function public.erp_recycle_bin_list(uuid,text,text) from public, anon;
grant execute on function public.erp_recycle_bin_list(uuid,text,text) to authenticated, service_role;
