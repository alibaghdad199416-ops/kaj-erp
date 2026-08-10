-- Quality Line ERP 17.15.5 - cloud-only company settings and currencies.
begin;

create or replace function public.erp_get_cloud_company_settings()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v_slug text; v_payload jsonb;
begin
  select company_slug into v_slug from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  select payload into v_payload
    from public.erp_records
   where company_id=v_slug and entity_type='app_settings'
     and record_id='company' and deleted_at is null
   limit 1;
  return coalesce(v_payload, jsonb_build_object(
    'company_name','شركة خط الجودة','company_name_en','Quality Line',
    'company_phone','','company_email','','company_address','',
    'company_tax_number','','default_currency','USD','app_language','ar'));
end $$;
revoke all on function public.erp_get_cloud_company_settings() from public, anon;
grant execute on function public.erp_get_cloud_company_settings() to authenticated;

create or replace function public.erp_save_cloud_company_settings(p_settings jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare v_slug text; v_admin boolean;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  if coalesce(btrim(p_settings->>'company_name'),'')='' then raise exception 'company_name_required'; end if;
  insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
  values(v_slug,'app_settings','company',p_settings,false,null,now())
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
end $$;
revoke all on function public.erp_save_cloud_company_settings(jsonb) from public, anon;
grant execute on function public.erp_save_cloud_company_settings(jsonb) to authenticated;

create or replace function public.erp_list_cloud_currencies()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v_slug text; v_rows jsonb;
begin
  select company_slug into v_slug from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  select coalesce(jsonb_agg(payload order by
    case when coalesce((payload->>'isBase')::boolean,false) then 0 else 1 end,
    payload->>'code'), '[]'::jsonb)
    into v_rows
    from public.erp_records
   where company_id=v_slug and entity_type='currencies' and deleted_at is null;
  if jsonb_array_length(v_rows)=0 then
    v_rows := jsonb_build_array(
      jsonb_build_object('code','USD','name','US Dollar','symbol','$','exchangeRate',1,'isBase',true,'isActive',true),
      jsonb_build_object('code','IQD','name','Iraqi Dinar','symbol','د.ع','exchangeRate',1,'isBase',false,'isActive',true));
  end if;
  return v_rows;
end $$;
revoke all on function public.erp_list_cloud_currencies() from public, anon;
grant execute on function public.erp_list_cloud_currencies() to authenticated;

create or replace function public.erp_save_cloud_currency(
  p_code text,p_name text,p_symbol text,p_exchange_rate numeric,
  p_is_base boolean,p_is_active boolean)
returns void language plpgsql security definer set search_path = public
as $$
declare v_slug text; v_admin boolean; v_code text; v_payload jsonb;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  v_code := upper(btrim(p_code));
  if v_code='' then raise exception 'currency_code_required'; end if;
  if p_exchange_rate is null or p_exchange_rate<=0 then raise exception 'invalid_exchange_rate'; end if;
  if p_is_base then
    update public.erp_records
       set payload=jsonb_set(payload,'{isBase}','false'::jsonb,true),updated_at=now()
     where company_id=v_slug and entity_type='currencies' and deleted_at is null;
  end if;
  v_payload := jsonb_build_object(
    'code',v_code,'name',btrim(p_name),'symbol',btrim(p_symbol),
    'exchangeRate',p_exchange_rate,'isBase',p_is_base,'isActive',p_is_active);
  insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
  values(v_slug,'currencies',v_code,v_payload,false,null,now())
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
end $$;
revoke all on function public.erp_save_cloud_currency(text,text,text,numeric,boolean,boolean) from public, anon;
grant execute on function public.erp_save_cloud_currency(text,text,text,numeric,boolean,boolean) to authenticated;

create or replace function public.erp_delete_cloud_currency(p_code text)
returns void language plpgsql security definer set search_path = public
as $$
declare v_slug text; v_admin boolean; v_base boolean;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  select coalesce((payload->>'isBase')::boolean,false) into v_base
    from public.erp_records
   where company_id=v_slug and entity_type='currencies'
     and record_id=upper(btrim(p_code)) and deleted_at is null;
  if v_base is null then raise exception 'currency_not_found'; end if;
  if v_base then raise exception 'cannot_delete_base_currency'; end if;
  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug and entity_type='currencies'
     and record_id=upper(btrim(p_code)) and deleted_at is null;
end $$;
revoke all on function public.erp_delete_cloud_currency(text) from public, anon;
grant execute on function public.erp_delete_cloud_currency(text) to authenticated;

commit;
