begin;

-- R59 / Stage 12 completion: close the remaining direct Storage-object gap.
--
-- R58 bound the registration RPC to company/document/version.bin, but the
-- Storage object policies still authorized any object whose first two path
-- segments belonged to a writable document. That allowed creation of an
-- otherwise-unregistered version filename under an authorized document.
--
-- The Storage policy is part of the data-integrity boundary, so it must enforce
-- the same canonical identity as the database registration RPC. This change is
-- forward-only: no existing object is deleted or moved.

create or replace function public.erp_r59_document_storage_version_id(p_name text)
returns uuid
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_file text;
  v_version text;
begin
  v_file := storage.filename(p_name);
  if v_file is null or v_file !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.bin$' then
    return null;
  end if;
  v_version := regexp_replace(v_file, '\\.bin$', '', 'i');
  return v_version::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

create or replace function public.erp_r59_document_storage_identity_valid(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_document uuid;
  v_version uuid;
begin
  v_company := public.erp_r54_document_storage_company_id(p_name);
  v_document := public.erp_r54_document_storage_id(p_name);
  v_version := public.erp_r59_document_storage_version_id(p_name);
  if v_company is null or v_document is null or v_version is null then
    return false;
  end if;

  return exists (
    select 1
    from public.erp_document_records d
    join public.erp_document_versions v
      on v.company_id=d.company_id
     and v.id=v_version
     and not v.is_deleted
     and v.data->>'documentId'=d.id::text
    where d.company_id=v_company
      and d.id=v_document
      and not d.is_deleted
  );
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
  if not public.erp_r59_document_storage_identity_valid(p_name) then return false; end if;
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
  if not public.erp_r59_document_storage_identity_valid(p_name) then return false; end if;
  return public.erp_r49_document_can_write(v_company,v_document);
end;
$$;

revoke all on function public.erp_r59_document_storage_version_id(text) from public,anon;
revoke all on function public.erp_r59_document_storage_identity_valid(text) from public,anon;
grant execute on function public.erp_r59_document_storage_version_id(text) to authenticated,service_role;
grant execute on function public.erp_r59_document_storage_identity_valid(text) to authenticated,service_role;

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

notify pgrst,'reload schema';
commit;
