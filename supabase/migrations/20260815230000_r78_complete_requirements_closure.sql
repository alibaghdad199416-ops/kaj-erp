-- Quality Line ERP R78 complete requirements closure.
-- Forward-only closure for granular media/credential permissions and sensitive
-- report sections. Browser checks are backed by PostgreSQL/Edge enforcement.
begin;

insert into public.permissions(code, name_ar, name_en)
values
  ('users.image.update','تعديل صورة المستخدم','Update user image'),
  ('users.credentials.update','تعديل بيانات دخول المستخدم','Update user credentials'),
  ('customers.image.update','تعديل صورة العميل','Update customer image'),
  ('suppliers.image.update','تعديل صورة المورد','Update supplier image'),
  ('cars.images.manage','إدارة صور السيارات','Manage vehicle images'),
  ('inventory.images.manage','إدارة صور المنتجات','Manage inventory images'),
  ('reports.audit.view','عرض تفاصيل تدقيق التقارير','View report audit details'),
  ('reports.contextual.view','عرض التفاصيل السياقية للتقارير','View contextual report details'),
  ('reports.financial_details.view','عرض التفاصيل المالية للتقارير','View financial report details')
on conflict (code) do update
set name_ar=excluded.name_ar,
    name_en=excluded.name_en;

-- System administrators keep their existing full-access contract. Other roles
-- receive the new permissions only when explicitly assigned through the ERP.
insert into public.role_permissions(role_code, permission_code)
select role_code, permission_code
from (values ('owner'),('admin')) roles(role_code)
cross join (values
  ('users.image.update'),
  ('users.credentials.update'),
  ('customers.image.update'),
  ('suppliers.image.update'),
  ('cars.images.manage'),
  ('inventory.images.manage'),
  ('reports.audit.view'),
  ('reports.contextual.view'),
  ('reports.financial_details.view')
) permissions(permission_code)
on conflict do nothing;

-- Re-seed every existing tenant so the generic access snapshot immediately
-- contains the new permission records and administrator bindings.
do $$
declare v_company record;
begin
  for v_company in select id from public.companies loop
    perform public.erp_seed_access_catalog(v_company.id);
  end loop;
end $$;

-- Auth-context-safe helper for Edge Functions and browser repositories. The
-- caller identity comes from auth.uid(); a service-role client cannot forge the
-- end-user decision by supplying a user id in parameters.
create or replace function public.erp_cloud_current_user_has_permission(
  p_company_id uuid,
  p_permission_code text
) returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then return false; end if;
  if not public.is_active_company_member(p_company_id) then return false; end if;
  return public.erp_cloud_user_has_permission(
    p_company_id,
    btrim(coalesce(p_permission_code,''))
  );
end;
$$;
revoke all on function public.erp_cloud_current_user_has_permission(uuid,text)
  from public,anon;
grant execute on function public.erp_cloud_current_user_has_permission(uuid,text)
  to authenticated,service_role;

-- Extra server-side barrier for media. Existing R9 field guards still enforce
-- the module CRUD/field permission; this trigger only adds the dedicated image
-- permission and therefore cannot broaden access.
create or replace function public.erp_r78_media_permission_guard()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_permission text;
  v_changed boolean:=true;
  v_old_media text:='';
  v_new_media text:='';
begin
  -- Trusted migrations/service jobs run without an end-user JWT. User-facing
  -- Edge Functions perform their own caller permission check before service-role
  -- writes, so they intentionally bypass this trigger-level auth.uid check.
  if auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  if tg_op='DELETE' then v_company_id:=old.company_id;
  else v_company_id:=new.company_id;
  end if;

  case tg_table_name
    when 'erp_customers' then
      v_permission:='customers.image.update';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'photoBase64',old.data->>'photo_base64',old.data->>'photo','');
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_suppliers' then
      v_permission:='suppliers.image.update';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'photoBase64',old.data->>'photo_base64',old.data->>'photo','');
        v_new_media:=coalesce(new.data->>'photoBase64',new.data->>'photo_base64',new.data->>'photo','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_cars' then
      v_permission:='cars.images.manage';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'photoBase64','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'imageBase64',old.data->>'image_base64',old.data->>'photoBase64','');
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'photoBase64','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_inventory' then
      v_permission:='inventory.images.manage';
      if tg_op='INSERT' then
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'image','');
        v_changed:=btrim(v_new_media)<>'';
      elsif tg_op='UPDATE' then
        v_old_media:=coalesce(old.data->>'imageBase64',old.data->>'image_base64',old.data->>'image','');
        v_new_media:=coalesce(new.data->>'imageBase64',new.data->>'image_base64',new.data->>'image','');
        v_changed:=v_new_media is distinct from v_old_media;
      else
        v_changed:=false;
      end if;
    when 'erp_car_images' then
      v_permission:='cars.images.manage';
    when 'erp_product_images' then
      v_permission:='inventory.images.manage';
    else
      if tg_op='DELETE' then return old; else return new; end if;
  end case;

  if v_changed and not public.erp_cloud_user_has_permission(v_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;

  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.erp_r78_media_permission_guard() from public,anon,authenticated;

-- Trigger creation is conditional to keep fresh-project and upgraded-project
-- migration chains idempotent even when optional image tables are introduced by
-- an earlier feature migration.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'erp_customers','erp_suppliers','erp_cars','erp_inventory',
    'erp_car_images','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop trigger if exists zz_r78_media_permission_guard on public.%I',v_table);
      execute format(
        'create trigger zz_r78_media_permission_guard before insert or update or delete on public.%I '
        'for each row execute function public.erp_r78_media_permission_guard()',
        v_table
      );
    end if;
  end loop;
end $$;

-- Sensitive report detail permissions are independent from the ordinary
-- reports.view permission. Field-level restrictions remain an additional layer.
create or replace function public.erp_r9_can_view_report_module(
  p_company_id uuid,p_module text
) returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  m text:=lower(trim(coalesce(p_module,'overview'));
  p text;
begin
  p:=case m
    when 'cars' then 'cars.view'
    when 'products' then 'inventory.view'
    when 'inventory' then 'inventory.view'
    when 'warehouses' then 'warehouses.view'
    when 'customers' then 'customers.view'
    when 'suppliers' then 'suppliers.view'
    when 'sales' then 'sales.view'
    when 'purchases' then 'purchases.view'
    when 'maintenance' then 'maintenance.view'
    when 'customer_service' then 'customer_service.view'
    when 'opportunities' then 'customer_service.view'
    when 'payments' then 'accounting.view'
    when 'accounting' then 'accounting.view'
    when 'finance' then 'accounting.view'
    when 'partners' then 'accounting.view'
    when 'operations' then 'reports.view'
    when 'overview' then 'reports.view'
    else 'reports.view' end;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.view')
     or not public.erp_cloud_user_has_permission(p_company_id,p) then
    return false;
  end if;
  if m in ('payments','accounting','finance','partners')
     and not public.erp_cloud_user_has_permission(p_company_id,'reports.financial_details.view') then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.erp_r9_cloud_contextual_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.contextual.view') then
    raise exception 'permission_denied:reports.contextual.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'reports','contextualDetails','reports.view') then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  return public.erp_cloud_contextual_report(p_company_id,p_module,p_start_date,p_end_date);
end;
$$;

create or replace function public.erp_r9_cloud_model_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.contextual.view') then
    raise exception 'permission_denied:reports.contextual.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'reports','contextualDetails','reports.view') then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  return public.erp_cloud_model_report(p_company_id,p_module,p_start_date,p_end_date);
end;
$$;

create or replace function public.erp_r9_cloud_customer_service_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.erp_r9_can_view_report_module(p_company_id,p_module) then
    raise exception 'permission_denied:report_module:%',p_module using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'reports.contextual.view') then
    raise exception 'permission_denied:reports.contextual.view' using errcode='42501';
  end if;
  if not public.erp_cloud_user_can_view_field(p_company_id,'reports','contextualDetails','reports.view') then
    raise exception 'field_permission_denied:reports.contextualDetails' using errcode='42501';
  end if;
  return query
    select x from public.erp_cloud_customer_service_report(
      p_company_id,p_module,p_start_date,p_end_date
    ) x;
end;
$$;

create or replace function public.erp_r9_cloud_report_audit(
  p_company_id uuid,p_module text,p_start_date timestamptz default null,
  p_end_date timestamptz default null,p_limit int default 10000
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.erp_cloud_user_has_permission(p_company_id,'audit.view')
     or not public.erp_cloud_user_has_permission(p_company_id,'reports.audit.view')
     or not public.erp_cloud_user_can_view_field(p_company_id,'reports','auditDetails','reports.view') then
    raise exception 'permission_denied:reports.audit.view' using errcode='42501';
  end if;
  return public.erp_cloud_report_audit(
    p_company_id,p_module,p_start_date,p_end_date,p_limit
  );
end;
$$;

revoke all on function public.erp_r9_can_view_report_module(uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r9_cloud_contextual_report(uuid,text,date,date)
  to authenticated,service_role;
grant execute on function public.erp_r9_cloud_model_report(uuid,text,date,date)
  to authenticated,service_role;
grant execute on function public.erp_r9_cloud_customer_service_report(uuid,text,date,date)
  to authenticated,service_role;
grant execute on function public.erp_r9_cloud_report_audit(uuid,text,timestamptz,timestamptz,integer)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
