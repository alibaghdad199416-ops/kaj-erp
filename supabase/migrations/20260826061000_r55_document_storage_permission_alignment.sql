begin;

-- R55 corrects the R54 storage boundary so object-level access follows the
-- same document/module permissions as the database RPCs. This is additive and
-- data-preserving; existing objects are not moved or deleted.

create or replace function public.erp_r54_document_storage_company_id(p_name text)
returns uuid
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_part text;
begin
  v_part=(storage.foldername(p_name))[1];
  if v_part is null or v_part !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return null;
  end if;
  return v_part::uuid;
end;
$$;

create or replace function public.erp_r54_document_storage_id(p_name text)
returns uuid
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_part text;
begin
  v_part=(storage.foldername(p_name))[2];
  if v_part is null or v_part !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return null;
  end if;
  return v_part::uuid;
end;
$$;

create or replace function public.erp_r54_document_storage_can_read(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_company uuid; v_document uuid;
begin
  if auth.uid() is null then return false; end if;
  v_company:=public.erp_r54_document_storage_company_id(p_name);
  v_document:=public.erp_r54_document_storage_id(p_name);
  if v_company is null or v_document is null then return false; end if;
  return public.erp_r49_document_can_read(v_company,v_document);
end;
$$;

create or replace function public.erp_r54_document_storage_can_write(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_company uuid; v_document uuid;
begin
  if auth.uid() is null then return false; end if;
  v_company:=public.erp_r54_document_storage_company_id(p_name);
  v_document:=public.erp_r54_document_storage_id(p_name);
  if v_company is null or v_document is null then return false; end if;
  return public.erp_r49_document_can_write(v_company,v_document);
end;
$$;

revoke all on function public.erp_r54_document_storage_company_id(text) from public,anon;
revoke all on function public.erp_r54_document_storage_id(text) from public,anon;
revoke all on function public.erp_r54_document_storage_can_read(text) from public,anon;
revoke all on function public.erp_r54_document_storage_can_write(text) from public,anon;
grant execute on function public.erp_r54_document_storage_company_id(text) to authenticated,service_role;
grant execute on function public.erp_r54_document_storage_id(text) to authenticated,service_role;
grant execute on function public.erp_r54_document_storage_can_read(text) to authenticated,service_role;
grant execute on function public.erp_r54_document_storage_can_write(text) to authenticated,service_role;

drop policy if exists enterprise_documents_storage_select on storage.objects;
drop policy if exists enterprise_documents_storage_insert on storage.objects;
drop policy if exists enterprise_documents_storage_update on storage.objects;
drop policy if exists enterprise_documents_storage_delete on storage.objects;

create policy enterprise_documents_storage_select
on storage.objects
for select
using (
  bucket_id='enterprise-documents'
  and public.erp_r54_document_storage_can_read(name)
);

create policy enterprise_documents_storage_insert
on storage.objects
for insert
with check (
  bucket_id='enterprise-documents'
  and public.erp_r54_document_storage_can_write(name)
);

create policy enterprise_documents_storage_update
on storage.objects
for update
using (
  bucket_id='enterprise-documents'
  and public.erp_r54_document_storage_can_write(name)
)
with check (
  bucket_id='enterprise-documents'
  and public.erp_r54_document_storage_can_write(name)
);

create policy enterprise_documents_storage_delete
on storage.objects
for delete
using (
  bucket_id='enterprise-documents'
  and public.erp_r54_document_storage_can_write(name)
);

-- Preserve the R49 document/module authorization contract while adding the
-- storage-path and document-version integrity checks introduced by R54.
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
  if p_storage_path is null
     or p_storage_path not like p_company_id::text || '/%'
     or p_storage_path like '%..%'
     or p_storage_path like '%//%' then
    raise exception 'invalid_document_storage_path' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.erp_document_records d
    where d.company_id=p_company_id and d.id=p_document_id and not d.is_deleted
  ) then
    raise exception 'document_not_found' using errcode='P0002';
  end if;
  if not exists (
    select 1 from public.erp_document_versions v
    where v.company_id=p_company_id and v.id=p_version_id and not v.is_deleted
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
  where company_id=p_company_id and id=p_version_id and not is_deleted;

  if not found then
    raise exception 'document_version_not_found' using errcode='P0002';
  end if;
end;
$$;

revoke all on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) from public,anon;
grant execute on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
