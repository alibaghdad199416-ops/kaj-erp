-- Phase 6: final quality, RLS hardening and release-readiness indexes.

-- Recycle-bin reads must require their dedicated permission, not membership only.
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
  if not public.erp_has_permission(p_company_id, 'settings.recycle_bin.view')
     and not public.erp_has_permission(p_company_id, 'settings.view') then
    raise exception 'recycle_bin_view_permission_required';
  end if;

  return query
  select r.entity_type,
         r.record_id,
         r.payload,
         r.deleted_at,
         coalesce(r.payload->>'deletedByUserName', r.payload->>'deletedBy', '')
  from public.erp_records r
  where r.company_id = p_company_id::text
    and r.deleted_at is not null
    and (coalesce(trim(p_entity_type), '') = '' or r.entity_type = trim(p_entity_type))
    and (
      coalesce(trim(p_query), '') = ''
      or r.record_id ilike '%' || trim(p_query) || '%'
      or r.entity_type ilike '%' || trim(p_query) || '%'
      or r.payload::text ilike '%' || trim(p_query) || '%'
    )
  order by r.deleted_at desc, r.entity_type, r.record_id;
end;
$$;

-- Speed up the central recycle bin and tenant/entity active-record lookups.
create index if not exists erp_records_recycle_bin_idx
  on public.erp_records(company_id, deleted_at desc)
  where deleted_at is not null;
create index if not exists erp_records_active_entity_idx
  on public.erp_records(company_id, entity_type, updated_at desc)
  where deleted_at is null;

-- Explicitly retain tenant RLS and remove obsolete bootstrap policies.
alter table public.erp_records enable row level security;
drop policy if exists erp_records_bootstrap_select on public.erp_records;
drop policy if exists erp_records_bootstrap_insert on public.erp_records;
drop policy if exists erp_records_bootstrap_update on public.erp_records;
drop policy if exists erp_records_bootstrap_delete on public.erp_records;

revoke all on function public.erp_recycle_bin_list(uuid,text,text) from public, anon;
grant execute on function public.erp_recycle_bin_list(uuid,text,text) to authenticated;

comment on function public.erp_recycle_bin_list(uuid,text,text)
is 'Phase 6 tenant-scoped recycle-bin listing with explicit view permission.';
