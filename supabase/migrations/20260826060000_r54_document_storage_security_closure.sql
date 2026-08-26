begin;

-- R54: document storage closure. The Flutter document repository uses the
-- enterprise-documents bucket, but the historical governance migration only
-- created enterprise-governance. Create the missing private bucket and bind
-- every object operation to the company UUID encoded in the first path segment.
-- No existing business data is modified or deleted.

insert into storage.buckets(id,name,public)
values('enterprise-documents','enterprise-documents',false)
on conflict(id) do update set name=excluded.name,public=false;

drop policy if exists enterprise_documents_storage_select on storage.objects;
drop policy if exists enterprise_documents_storage_insert on storage.objects;
drop policy if exists enterprise_documents_storage_update on storage.objects;
drop policy if exists enterprise_documents_storage_delete on storage.objects;

create policy enterprise_documents_storage_select
on storage.objects
for select
using (
  bucket_id='enterprise-documents'
  and auth.uid() is not null
  and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid)
);

create policy enterprise_documents_storage_insert
on storage.objects
for insert
with check (
  bucket_id='enterprise-documents'
  and auth.uid() is not null
  and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid)
);

create policy enterprise_documents_storage_update
on storage.objects
for update
using (
  bucket_id='enterprise-documents'
  and auth.uid() is not null
  and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid)
)
with check (
  bucket_id='enterprise-documents'
  and auth.uid() is not null
  and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid)
);

create policy enterprise_documents_storage_delete
on storage.objects
for delete
using (
  bucket_id='enterprise-documents'
  and auth.uid() is not null
  and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid)
);

-- Keep the database registration path tenant-safe as well. A blob may only be
-- registered when its storage path is rooted at the same company UUID and the
-- referenced document/version belongs to that company.
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
