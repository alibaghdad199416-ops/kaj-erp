begin;

-- R60 / Final cross-stage security closure.
--
-- R59 correctly binds direct Storage objects to a real document version, but
-- its SECURITY DEFINER identity helper was still directly executable by an
-- authenticated caller without first proving membership in the company
-- encoded by the object path. The policy path was safe, but the exposed RPC
-- surface could still be used as a cross-tenant existence oracle.
--
-- Keep the helper available to authenticated callers because the Storage RLS
-- policies invoke it, but make its direct result tenant-scoped as well.

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
  if auth.uid() is null then
    return false;
  end if;

  v_company := public.erp_r54_document_storage_company_id(p_name);
  v_document := public.erp_r54_document_storage_id(p_name);
  v_version := public.erp_r59_document_storage_version_id(p_name);

  if v_company is null or v_document is null or v_version is null then
    return false;
  end if;

  if not public.erp_is_active_company_member(v_company) then
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

revoke all on function public.erp_r59_document_storage_identity_valid(text) from public,anon;
grant execute on function public.erp_r59_document_storage_identity_valid(text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
