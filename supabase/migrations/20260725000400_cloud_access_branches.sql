-- Quality Line ERP 17.15.5 - cloud-only branches, users and permissions.
begin;

create or replace function public.erp_active_company_context()
returns table(company_uuid uuid, company_slug text, role_code text, is_admin boolean)
language sql stable security definer set search_path = public
as $$
  select c.id, c.slug, m.role_code,
         (m.is_system_admin or m.role_code in ('owner','admin'))
  from public.company_memberships m
  join public.companies c on c.id = m.company_id
  where m.user_uid = auth.uid()::text
    and m.is_active and c.is_active
  order by m.is_system_admin desc, m.created_at
  limit 1
$$;

grant execute on function public.erp_active_company_context() to authenticated;

create or replace function public.erp_access_cloud_snapshot()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v_slug text;
begin
  select company_slug into v_slug from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  return jsonb_build_object(
    'users', coalesce((select jsonb_agg(payload order by updated_at desc) from public.erp_records where company_id=v_slug and entity_type='users' and deleted_at is null), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(payload order by record_id) from public.erp_records where company_id=v_slug and entity_type='roles' and deleted_at is null), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(payload order by record_id) from public.erp_records where company_id=v_slug and entity_type='permissions' and deleted_at is null), '[]'::jsonb),
    'role_permissions', coalesce((select jsonb_agg(payload order by record_id) from public.erp_records where company_id=v_slug and entity_type='role_permissions' and deleted_at is null), '[]'::jsonb),
    'audit_logs', coalesce((select jsonb_agg(payload order by updated_at desc) from (select payload, updated_at from public.erp_records where company_id=v_slug and entity_type='audit_logs' and deleted_at is null order by updated_at desc limit 1000) q), '[]'::jsonb)
  );
end $$;
revoke all on function public.erp_access_cloud_snapshot() from public, anon;
grant execute on function public.erp_access_cloud_snapshot() to authenticated;

create or replace function public.erp_upsert_cloud_access_record(p_entity_type text, p_record_id text, p_payload jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare v_slug text; v_admin boolean;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if p_entity_type not in ('users','roles','permissions','role_permissions','audit_logs') then raise exception 'unsupported_entity'; end if;
  if p_entity_type <> 'audit_logs' and not v_admin then raise exception 'permission_denied'; end if;
  insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
  values(v_slug,p_entity_type,p_record_id,p_payload,false,null,now())
  on conflict(company_id,entity_type,record_id) do update set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
end $$;
revoke all on function public.erp_upsert_cloud_access_record(text,text,jsonb) from public, anon;
grant execute on function public.erp_upsert_cloud_access_record(text,text,jsonb) to authenticated;

create or replace function public.erp_delete_cloud_access_record(p_entity_type text, p_record_id text)
returns void language plpgsql security definer set search_path = public
as $$
declare v_slug text; v_admin boolean;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  if p_entity_type not in ('users','roles','permissions','role_permissions') then raise exception 'unsupported_entity'; end if;
  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug and entity_type=p_entity_type and record_id=p_record_id and deleted_at is null;
  if not found then raise exception 'record_not_found'; end if;
end $$;
revoke all on function public.erp_delete_cloud_access_record(text,text) from public, anon;
grant execute on function public.erp_delete_cloud_access_record(text,text) to authenticated;

create or replace function public.erp_set_cloud_role_permissions(p_role_id text,p_permission_codes text[])
returns void language plpgsql security definer set search_path = public
as $$
declare v_slug text; v_admin boolean; v_code text; v_permission_id text;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug and entity_type='role_permissions' and payload->>'roleId'=p_role_id and deleted_at is null;
  foreach v_code in array coalesce(p_permission_codes,array[]::text[]) loop
    select record_id into v_permission_id from public.erp_records
     where company_id=v_slug and entity_type='permissions' and payload->>'code'=v_code and deleted_at is null limit 1;
    if v_permission_id is null then raise exception 'permission_code_not_found:%',v_code; end if;
    insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
    values(v_slug,'role_permissions',p_role_id||'::'||v_permission_id,jsonb_build_object('roleId',p_role_id,'permissionId',v_permission_id),false,null,now())
    on conflict(company_id,entity_type,record_id) do update set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;
end $$;
revoke all on function public.erp_set_cloud_role_permissions(text,text[]) from public, anon;
grant execute on function public.erp_set_cloud_role_permissions(text,text[]) to authenticated;

create or replace function public.erp_list_cloud_branches()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v_company uuid;
begin
  select company_uuid into v_company from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',id::text,'name',coalesce(nullif(name_ar,''),name_en),'code',code,'phone',coalesce(phone,''),'address',coalesce(address,''),
    'isMain',case when is_main then 1 else 0 end,'isActive',case when is_active then 1 else 0 end,
    'createdAt',created_at,'updatedAt',updated_at) order by is_main desc,name_ar)
    from public.branches where company_id=v_company), '[]'::jsonb);
end $$;
revoke all on function public.erp_list_cloud_branches() from public, anon;
grant execute on function public.erp_list_cloud_branches() to authenticated;

create or replace function public.erp_save_cloud_branch(p_id text,p_name text,p_code text,p_phone text,p_address text,p_is_main boolean,p_is_active boolean,p_created_at timestamptz,p_updated_at timestamptz)
returns void language plpgsql security definer set search_path = public
as $$
declare v_company uuid; v_admin boolean; v_id uuid;
begin
  select company_uuid,is_admin into v_company,v_admin from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  v_id := p_id::uuid;
  if p_is_main then update public.branches set is_main=false,updated_at=now() where company_id=v_company and id<>v_id; end if;
  insert into public.branches(id,company_id,code,name_ar,name_en,phone,address,is_main,is_active,created_at,updated_at)
  values(v_id,v_company,btrim(p_code),btrim(p_name),btrim(p_name),nullif(btrim(p_phone),''),nullif(btrim(p_address),''),p_is_main,p_is_active,coalesce(p_created_at,now()),coalesce(p_updated_at,now()))
  on conflict(id) do update set code=excluded.code,name_ar=excluded.name_ar,name_en=excluded.name_en,phone=excluded.phone,address=excluded.address,is_main=excluded.is_main,is_active=excluded.is_active,updated_at=now()
  where branches.company_id=v_company;
end $$;
revoke all on function public.erp_save_cloud_branch(text,text,text,text,text,boolean,boolean,timestamptz,timestamptz) from public, anon;
grant execute on function public.erp_save_cloud_branch(text,text,text,text,text,boolean,boolean,timestamptz,timestamptz) to authenticated;

create or replace function public.erp_delete_cloud_branch(p_id text)
returns void language plpgsql security definer set search_path = public
as $$
declare v_company uuid; v_admin boolean; v_main boolean;
begin
 select company_uuid,is_admin into v_company,v_admin from public.erp_active_company_context();
 if v_company is null then raise exception 'membership_not_found'; end if;
 if not v_admin then raise exception 'permission_denied'; end if;
 select is_main into v_main from public.branches where id=p_id::uuid and company_id=v_company;
 if v_main is null then raise exception 'branch_not_found'; end if;
 if v_main then raise exception 'cannot_delete_main_branch'; end if;
 delete from public.branches where id=p_id::uuid and company_id=v_company;
end $$;
revoke all on function public.erp_delete_cloud_branch(text) from public, anon;
grant execute on function public.erp_delete_cloud_branch(text) to authenticated;

commit;
