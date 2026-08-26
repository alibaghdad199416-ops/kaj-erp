begin;

-- R58 / Stage 12: full-program document/storage integrity closure.
--
-- R55 correctly tied storage access to the company and document permissions,
-- but its registration RPC accepted any path rooted at the company. The
-- canonical Flutter writer uses company/document/version.bin. Without this
-- exact binding, a caller with permission to document A could register A's
-- version against an object path belonging to document B, causing database
-- metadata and storage authorization to describe different documents.
--
-- This is forward-only and data-preserving. Existing objects are not moved or
-- deleted; only future registrations are prevented from creating new drift.

create or replace function public.erp_register_cloud_document_blob(
  p_company_id uuid,
  p_document_id uuid,
  p_version_id uuid,
  p_storage_path text,
  p_size_bytes bigint
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_expected_path text;
begin
  if auth.uid() is null or not public.erp_is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) then
    raise exception 'document_write_permission_required' using errcode='42501';
  end if;
  if p_size_bytes is null or p_size_bytes <= 0 then
    raise exception 'invalid_document_size' using errcode='22023';
  end if;

  v_expected_path := p_company_id::text || '/' || p_document_id::text || '/' || p_version_id::text || '.bin';
  if p_storage_path is distinct from v_expected_path then
    raise exception 'invalid_document_storage_path' using errcode='22023',
      hint='Storage path must be company/document/version.bin and must match the registered document and version.';
  end if;

  if not exists (
    select 1
    from public.erp_document_records d
    where d.company_id=p_company_id
      and d.id=p_document_id
      and not d.is_deleted
  ) then
    raise exception 'document_not_found' using errcode='P0002';
  end if;

  if not exists (
    select 1
    from public.erp_document_versions v
    where v.company_id=p_company_id
      and v.id=p_version_id
      and not v.is_deleted
      and v.data->>'documentId'=p_document_id::text
  ) then
    raise exception 'document_version_not_found' using errcode='P0002';
  end if;

  update public.erp_document_versions
  set data=data||jsonb_build_object(
        'storagePath',p_storage_path,
        'sizeBytes',p_size_bytes,
        'storedAt',now()
      ),
      updated_at=now()
  where company_id=p_company_id
    and id=p_version_id
    and not is_deleted;

  if not found then
    raise exception 'document_version_not_found' using errcode='P0002';
  end if;
end;
$$;

revoke all on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) from public,anon;
grant execute on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
