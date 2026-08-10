begin;

-- R49 product-identity/accounting integrity closure.
-- Paid maintenance must remain traceable to the customer ledger.  Older
-- engines could silently fall back to a generic receivable account (code 1400)
-- when customer_id was absent.  Preserve the proven posting engine, but place
-- a strict customer/partner-account boundary in front of it.
do $$
begin
  if to_regprocedure('public.erp_v736_post_maintenance_invoice_pre_r49_identity(uuid,uuid)') is null
     and to_regprocedure('public.erp_v736_post_maintenance_invoice(uuid,uuid)') is not null then
    alter function public.erp_v736_post_maintenance_invoice(uuid,uuid)
      rename to erp_v736_post_maintenance_invoice_pre_r49_identity;
  end if;
end $$;

create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_currency text;
  v_partner_account text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    array['maintenance.approve']
  );

  select * into v_order
    from public.erp_maintenance_orders
   where company_id=p_company_id
     and id=p_order_id
     and not is_deleted
   for update;
  if not found then
    raise exception 'maintenance_order_not_found';
  end if;

  if v_order.pricing_type='paid' then
    if v_order.customer_id is null then
      raise exception 'paid_maintenance_customer_required';
    end if;
    v_currency:=upper(coalesce(v_order.currency_code,''));
    if v_currency not in ('USD','IQD') then
      raise exception 'maintenance_currency_invalid:%',v_currency;
    end if;
    perform public.erp_v764_assert_partner_dual_ledgers(
      p_company_id,
      v_order.customer_id::text,
      'customer'
    );
    v_partner_account:=public.erp_workflow_partner_account(
      p_company_id,
      'customer',
      v_order.customer_id::text,
      v_currency
    );
    perform public.erp_phase2_account_guard(
      p_company_id,
      v_partner_account,
      'asset',
      v_currency
    );
  end if;

  return public.erp_v736_post_maintenance_invoice_pre_r49_identity(
    p_company_id,
    p_order_id
  );
end;
$$;

revoke all on function public.erp_v736_post_maintenance_invoice(uuid,uuid)
  from public,anon;
grant execute on function public.erp_v736_post_maintenance_invoice(uuid,uuid)
  to authenticated,service_role;



-- Document/attachment security follows the business document that owns it.
-- Sales attachments require sales.view/update; purchase attachments require
-- purchases.view/update. Generic document writes are admin-only so a company
-- member cannot mutate another module merely by calling a SECURITY DEFINER RPC.
create or replace function public.erp_r49_document_source_module(
  p_company_id uuid,p_document_id uuid
) returns text
language plpgsql stable security definer set search_path=public
as $$
declare v_type text; v_table text;
begin
  select lower(coalesce(d.data->'metadata'->>'sourceType','')),
         lower(coalesce(d.data->'metadata'->>'sourceTable',''))
    into v_type,v_table
  from public.erp_document_records d
  where d.company_id=p_company_id and d.id=p_document_id and not d.is_deleted;

  if v_type='sales_order' or v_table in ('sales_orders_cloud','erp_sales_orders_cloud') then return 'sales'; end if;
  if v_type='purchase_order' or v_table in ('purchase_orders_cloud','erp_purchase_orders_cloud') then return 'purchases'; end if;

  select lower(coalesce(l.data->>'entityType','')) into v_table
  from public.erp_document_links l
  where l.company_id=p_company_id and l.data->>'documentId'=p_document_id::text and not l.is_deleted
  order by l.created_at asc limit 1;
  if v_table in ('sales_orders_cloud','erp_sales_orders_cloud') then return 'sales'; end if;
  if v_table in ('purchase_orders_cloud','erp_purchase_orders_cloud') then return 'purchases'; end if;
  return null;
end $$;

create or replace function public.erp_r49_document_can_read(
  p_company_id uuid,p_document_id uuid
) returns boolean
language plpgsql stable security definer set search_path=public
as $$
declare v_module text;
begin
  if not public.erp_is_company_member(p_company_id) then return false; end if;
  if public.is_company_admin(p_company_id) then return true; end if;
  v_module:=public.erp_r49_document_source_module(p_company_id,p_document_id);
  if v_module='sales' then return public.erp_cloud_user_has_permission(p_company_id,'sales.view'); end if;
  if v_module='purchases' then return public.erp_cloud_user_has_permission(p_company_id,'purchases.view'); end if;
  -- Preserve legacy generic-document read compatibility for authenticated
  -- company members; generic mutations remain admin-only below.
  return true;
end $$;

create or replace function public.erp_r49_document_can_write(
  p_company_id uuid,p_document_id uuid
) returns boolean
language plpgsql stable security definer set search_path=public
as $$
declare v_module text;
begin
  if not public.erp_is_company_member(p_company_id) then return false; end if;
  if public.is_company_admin(p_company_id) then return true; end if;
  v_module:=public.erp_r49_document_source_module(p_company_id,p_document_id);
  if v_module='sales' then return public.erp_cloud_user_has_permission(p_company_id,'sales.update'); end if;
  if v_module='purchases' then return public.erp_cloud_user_has_permission(p_company_id,'purchases.update'); end if;
  return false;
end $$;

do $$
begin
  if to_regprocedure('public.erp_create_cloud_document_pre_r49_identity(uuid,jsonb,jsonb)') is null
     and to_regprocedure('public.erp_create_cloud_document(uuid,jsonb,jsonb)') is not null then
    alter function public.erp_create_cloud_document(uuid,jsonb,jsonb) rename to erp_create_cloud_document_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_add_cloud_document_version_pre_r49_identity(uuid,uuid,jsonb)') is null
     and to_regprocedure('public.erp_add_cloud_document_version(uuid,uuid,jsonb)') is not null then
    alter function public.erp_add_cloud_document_version(uuid,uuid,jsonb) rename to erp_add_cloud_document_version_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_link_cloud_document_pre_r49_identity(uuid,uuid,jsonb)') is null
     and to_regprocedure('public.erp_link_cloud_document(uuid,uuid,jsonb)') is not null then
    alter function public.erp_link_cloud_document(uuid,uuid,jsonb) rename to erp_link_cloud_document_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_grant_cloud_document_permission_pre_r49_identity(uuid,uuid,jsonb)') is null
     and to_regprocedure('public.erp_grant_cloud_document_permission(uuid,uuid,jsonb)') is not null then
    alter function public.erp_grant_cloud_document_permission(uuid,uuid,jsonb) rename to erp_grant_cloud_document_permission_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_transition_cloud_document_pre_r49_identity(uuid,uuid,text,text,text)') is null
     and to_regprocedure('public.erp_transition_cloud_document(uuid,uuid,text,text,text)') is not null then
    alter function public.erp_transition_cloud_document(uuid,uuid,text,text,text) rename to erp_transition_cloud_document_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_sign_cloud_document_version_pre_r49_identity(uuid,uuid,jsonb)') is null
     and to_regprocedure('public.erp_sign_cloud_document_version(uuid,uuid,jsonb)') is not null then
    alter function public.erp_sign_cloud_document_version(uuid,uuid,jsonb) rename to erp_sign_cloud_document_version_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_set_cloud_document_legal_hold_pre_r49_identity(uuid,uuid,boolean,text)') is null
     and to_regprocedure('public.erp_set_cloud_document_legal_hold(uuid,uuid,boolean,text)') is not null then
    alter function public.erp_set_cloud_document_legal_hold(uuid,uuid,boolean,text) rename to erp_set_cloud_document_legal_hold_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_register_cloud_document_blob_pre_r49_identity(uuid,uuid,uuid,text,bigint)') is null
     and to_regprocedure('public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint)') is not null then
    alter function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) rename to erp_register_cloud_document_blob_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_get_cloud_current_document_blob_pre_r49_identity(uuid,uuid)') is null
     and to_regprocedure('public.erp_get_cloud_current_document_blob(uuid,uuid)') is not null then
    alter function public.erp_get_cloud_current_document_blob(uuid,uuid) rename to erp_get_cloud_current_document_blob_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_get_cloud_document_pre_r49_identity(uuid,uuid)') is null
     and to_regprocedure('public.erp_get_cloud_document(uuid,uuid)') is not null then
    alter function public.erp_get_cloud_document(uuid,uuid) rename to erp_get_cloud_document_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_list_cloud_document_versions_pre_r49_identity(uuid,uuid)') is null
     and to_regprocedure('public.erp_list_cloud_document_versions(uuid,uuid)') is not null then
    alter function public.erp_list_cloud_document_versions(uuid,uuid) rename to erp_list_cloud_document_versions_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_list_cloud_document_permissions_pre_r49_identity(uuid,uuid)') is null
     and to_regprocedure('public.erp_list_cloud_document_permissions(uuid,uuid)') is not null then
    alter function public.erp_list_cloud_document_permissions(uuid,uuid) rename to erp_list_cloud_document_permissions_pre_r49_identity;
  end if;
  if to_regprocedure('public.erp_search_cloud_documents_pre_r49_identity(uuid,text,text,text,text,text,integer)') is null
     and to_regprocedure('public.erp_search_cloud_documents(uuid,text,text,text,text,text,integer)') is not null then
    alter function public.erp_search_cloud_documents(uuid,text,text,text,text,text,integer) rename to erp_search_cloud_documents_pre_r49_identity;
  end if;
end $$;

create or replace function public.erp_create_cloud_document(p_company_id uuid,p_document jsonb,p_version jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_source text:=lower(coalesce(p_document->'metadata'->>'sourceType','')); v_table text:=lower(coalesce(p_document->'metadata'->>'sourceTable',''));
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'company access denied' using errcode='42501'; end if;
  if v_source='sales_order' or v_table in ('sales_orders_cloud','erp_sales_orders_cloud') then
    if not public.erp_cloud_user_has_permission(p_company_id,'sales.update') and not public.is_company_admin(p_company_id) then raise exception 'permission_denied:sales.update' using errcode='42501'; end if;
  elsif v_source='purchase_order' or v_table in ('purchase_orders_cloud','erp_purchase_orders_cloud') then
    if not public.erp_cloud_user_has_permission(p_company_id,'purchases.update') and not public.is_company_admin(p_company_id) then raise exception 'permission_denied:purchases.update' using errcode='42501'; end if;
  elsif not public.is_company_admin(p_company_id) then
    raise exception 'permission_denied:document_admin' using errcode='42501';
  end if;
  return public.erp_create_cloud_document_pre_r49_identity(p_company_id,p_document,p_version);
end $$;

create or replace function public.erp_add_cloud_document_version(p_company_id uuid,p_document_id uuid,p_version jsonb)
returns int language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) then raise exception 'permission_denied:document_write' using errcode='42501'; end if;
  return public.erp_add_cloud_document_version_pre_r49_identity(p_company_id,p_document_id,p_version);
end $$;

create or replace function public.erp_link_cloud_document(p_company_id uuid,p_document_id uuid,p_link jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_entity text:=lower(coalesce(p_link->>'entityType',''));
begin
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) then raise exception 'permission_denied:document_write' using errcode='42501'; end if;
  if v_entity in ('sales_orders_cloud','erp_sales_orders_cloud') then
    if not public.erp_cloud_user_has_permission(p_company_id,'sales.update') and not public.is_company_admin(p_company_id) then raise exception 'permission_denied:sales.update' using errcode='42501'; end if;
  elsif v_entity in ('purchase_orders_cloud','erp_purchase_orders_cloud') then
    if not public.erp_cloud_user_has_permission(p_company_id,'purchases.update') and not public.is_company_admin(p_company_id) then raise exception 'permission_denied:purchases.update' using errcode='42501'; end if;
  elsif not public.is_company_admin(p_company_id) then raise exception 'permission_denied:document_admin' using errcode='42501';
  end if;
  perform public.erp_link_cloud_document_pre_r49_identity(p_company_id,p_document_id,p_link);
end $$;

create or replace function public.erp_grant_cloud_document_permission(p_company_id uuid,p_document_id uuid,p_permission jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_company_admin(p_company_id) then raise exception 'permission_denied:document_admin' using errcode='42501'; end if;
  perform public.erp_grant_cloud_document_permission_pre_r49_identity(p_company_id,p_document_id,p_permission);
end $$;

create or replace function public.erp_transition_cloud_document(p_company_id uuid,p_document_id uuid,p_to_status text,p_actor_id text,p_description text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) then raise exception 'permission_denied:document_write' using errcode='42501'; end if;
  perform public.erp_transition_cloud_document_pre_r49_identity(p_company_id,p_document_id,p_to_status,p_actor_id,p_description);
end $$;

create or replace function public.erp_sign_cloud_document_version(p_company_id uuid,p_document_id uuid,p_signature jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) then raise exception 'permission_denied:document_write' using errcode='42501'; end if;
  perform public.erp_sign_cloud_document_version_pre_r49_identity(p_company_id,p_document_id,p_signature);
end $$;

create or replace function public.erp_set_cloud_document_legal_hold(p_company_id uuid,p_document_id uuid,p_enabled boolean,p_actor_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_company_admin(p_company_id) then raise exception 'permission_denied:document_admin' using errcode='42501'; end if;
  perform public.erp_set_cloud_document_legal_hold_pre_r49_identity(p_company_id,p_document_id,p_enabled,p_actor_id);
end $$;

create or replace function public.erp_register_cloud_document_blob(p_company_id uuid,p_document_id uuid,p_version_id uuid,p_storage_path text,p_size_bytes bigint)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) then raise exception 'permission_denied:document_write' using errcode='42501'; end if;
  perform public.erp_register_cloud_document_blob_pre_r49_identity(p_company_id,p_document_id,p_version_id,p_storage_path,p_size_bytes);
end $$;

create or replace function public.erp_get_cloud_current_document_blob(p_company_id uuid,p_document_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_read(p_company_id,p_document_id) then raise exception 'permission_denied:document_view' using errcode='42501'; end if;
  return public.erp_get_cloud_current_document_blob_pre_r49_identity(p_company_id,p_document_id);
end $$;

create or replace function public.erp_get_cloud_document(p_company_id uuid,p_document_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_read(p_company_id,p_document_id) then raise exception 'permission_denied:document_view' using errcode='42501'; end if;
  return public.erp_get_cloud_document_pre_r49_identity(p_company_id,p_document_id);
end $$;

create or replace function public.erp_list_cloud_document_versions(p_company_id uuid,p_document_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_read(p_company_id,p_document_id) then raise exception 'permission_denied:document_view' using errcode='42501'; end if;
  return query select * from public.erp_list_cloud_document_versions_pre_r49_identity(p_company_id,p_document_id);
end $$;

create or replace function public.erp_list_cloud_document_permissions(p_company_id uuid,p_document_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_r49_document_can_write(p_company_id,p_document_id) and not public.is_company_admin(p_company_id) then raise exception 'permission_denied:document_permissions' using errcode='42501'; end if;
  return query select * from public.erp_list_cloud_document_permissions_pre_r49_identity(p_company_id,p_document_id);
end $$;

create or replace function public.erp_search_cloud_documents(p_company_id uuid,p_query text,p_category_id text,p_status text,p_entity_type text,p_entity_id text,p_limit integer)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'company access denied' using errcode='42501'; end if;
  return query
    select r
    from public.erp_search_cloud_documents_pre_r49_identity(p_company_id,p_query,p_category_id,p_status,p_entity_type,p_entity_id,p_limit) r
    where public.erp_r49_document_can_read(p_company_id,nullif(r->>'id','')::uuid);
end $$;

-- Remove direct access to renamed legacy implementations. The canonical names
-- above are the only authenticated mutation/read boundary from this release.
revoke all on function public.erp_create_cloud_document_pre_r49_identity(uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.erp_add_cloud_document_version_pre_r49_identity(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_link_cloud_document_pre_r49_identity(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_grant_cloud_document_permission_pre_r49_identity(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_transition_cloud_document_pre_r49_identity(uuid,uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.erp_sign_cloud_document_version_pre_r49_identity(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_set_cloud_document_legal_hold_pre_r49_identity(uuid,uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.erp_register_cloud_document_blob_pre_r49_identity(uuid,uuid,uuid,text,bigint) from public,anon,authenticated;
revoke all on function public.erp_get_cloud_current_document_blob_pre_r49_identity(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_get_cloud_document_pre_r49_identity(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_list_cloud_document_versions_pre_r49_identity(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_list_cloud_document_permissions_pre_r49_identity(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_search_cloud_documents_pre_r49_identity(uuid,text,text,text,text,text,integer) from public,anon,authenticated;

revoke all on function public.erp_r49_document_source_module(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_r49_document_can_read(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_document_can_write(uuid,uuid) from public,anon;
grant execute on function public.erp_r49_document_source_module(uuid,uuid) to service_role;
grant execute on function public.erp_r49_document_can_read(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_document_can_write(uuid,uuid) to authenticated,service_role;

revoke all on function public.erp_create_cloud_document(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_add_cloud_document_version(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_link_cloud_document(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_grant_cloud_document_permission(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_transition_cloud_document(uuid,uuid,text,text,text) from public,anon;
revoke all on function public.erp_sign_cloud_document_version(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_set_cloud_document_legal_hold(uuid,uuid,boolean,text) from public,anon;
revoke all on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) from public,anon;
revoke all on function public.erp_get_cloud_current_document_blob(uuid,uuid) from public,anon;
revoke all on function public.erp_get_cloud_document(uuid,uuid) from public,anon;
revoke all on function public.erp_list_cloud_document_versions(uuid,uuid) from public,anon;
revoke all on function public.erp_list_cloud_document_permissions(uuid,uuid) from public,anon;
revoke all on function public.erp_search_cloud_documents(uuid,text,text,text,text,text,integer) from public,anon;

grant execute on function public.erp_create_cloud_document(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_add_cloud_document_version(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_link_cloud_document(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_grant_cloud_document_permission(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_transition_cloud_document(uuid,uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_sign_cloud_document_version(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_set_cloud_document_legal_hold(uuid,uuid,boolean,text) to authenticated,service_role;
grant execute on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) to authenticated,service_role;
grant execute on function public.erp_get_cloud_current_document_blob(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_get_cloud_document(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_list_cloud_document_versions(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_list_cloud_document_permissions(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_search_cloud_documents(uuid,text,text,text,text,text,integer) to authenticated,service_role;

-- Safe path parsing: malformed object names are denied instead of throwing a cast error.
create or replace function public.erp_r49_try_uuid(p_value text) returns uuid
language plpgsql immutable security invoker set search_path=public as $$
begin
  if nullif(btrim(coalesce(p_value,'')),'') is null then return null; end if;
  return btrim(p_value)::uuid;
exception when invalid_text_representation then
  return null;
end $$;
revoke all on function public.erp_r49_try_uuid(text) from public,anon;
grant execute on function public.erp_r49_try_uuid(text) to authenticated,service_role;

-- Storage access now follows document visibility/editability instead of mere
-- company membership. Folder layout is company/document/version.bin.
drop policy if exists enterprise_documents_select on storage.objects;
create policy enterprise_documents_select on storage.objects for select to authenticated
using (
  bucket_id='enterprise-documents'
  and public.erp_r49_document_can_read(
    public.erp_r49_try_uuid((storage.foldername(name))[1]),
    public.erp_r49_try_uuid((storage.foldername(name))[2])
  )
);
drop policy if exists enterprise_documents_insert on storage.objects;
create policy enterprise_documents_insert on storage.objects for insert to authenticated
with check (
  bucket_id='enterprise-documents'
  and public.erp_r49_document_can_write(
    public.erp_r49_try_uuid((storage.foldername(name))[1]),
    public.erp_r49_try_uuid((storage.foldername(name))[2])
  )
);
drop policy if exists enterprise_documents_update on storage.objects;
create policy enterprise_documents_update on storage.objects for update to authenticated
using (
  bucket_id='enterprise-documents'
  and public.erp_r49_document_can_write(
    public.erp_r49_try_uuid((storage.foldername(name))[1]),
    public.erp_r49_try_uuid((storage.foldername(name))[2])
  )
)
with check (
  bucket_id='enterprise-documents'
  and public.erp_r49_document_can_write(
    public.erp_r49_try_uuid((storage.foldername(name))[1]),
    public.erp_r49_try_uuid((storage.foldername(name))[2])
  )
);

notify pgrst,'reload schema';
commit;
