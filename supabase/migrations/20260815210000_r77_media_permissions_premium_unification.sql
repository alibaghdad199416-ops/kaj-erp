-- R77: media persistence aliases + per-user record visibility scopes.
-- Forward-only. No historical migration is modified.
begin;

-- Preserve the complete strict R9 mapper and wrap it with media aliases emitted
-- by current normalized models. Existing mappings remain authoritative.
alter function public.erp_r9_master_field_for_table_key(text,text)
  rename to erp_r77_master_field_for_table_key_legacy;

create function public.erp_r9_master_field_for_table_key(
  p_table text,
  p_key text
) returns text
language plpgsql
immutable
as $$
declare
  v_table text := trim(coalesce(p_table,''));
  v_key text := trim(coalesce(p_key,''));
begin
  if v_table = 'erp_car_images' and v_key in ('thumbnailBase64','thumbnail_base64') then
    return 'images';
  end if;
  if v_table = 'erp_customers' and v_key in ('photoBase64','photo_base64') then
    return 'photo';
  end if;
  if v_table = 'erp_suppliers' and v_key in ('photoBase64','photo_base64') then
    return 'photo';
  end if;
  if v_table = 'erp_product_images' and v_key in ('thumbnailBase64','thumbnail_base64') then
    return 'image';
  end if;
  return public.erp_r77_master_field_for_table_key_legacy(v_table,v_key);
end;
$$;

-- Seed the two record-visibility choices into the same canonical permission
-- records consumed by the existing per-user override editor. Nothing is
-- auto-granted: an administrator explicitly selects own/all per user/module.
with scope_permissions(code,name_ar,module) as (
  values
    ('customers.records.own','عرض إدخالاته فقط','العملاء • نطاق السجلات'),
    ('customers.records.all','عرض إدخالات جميع المستخدمين','العملاء • نطاق السجلات'),
    ('suppliers.records.own','عرض إدخالاته فقط','الموردون • نطاق السجلات'),
    ('suppliers.records.all','عرض إدخالات جميع المستخدمين','الموردون • نطاق السجلات'),
    ('cars.records.own','عرض إدخالاته فقط','السيارات • نطاق السجلات'),
    ('cars.records.all','عرض إدخالات جميع المستخدمين','السيارات • نطاق السجلات'),
    ('inventory.records.own','عرض إدخالاته فقط','المخزون • نطاق السجلات'),
    ('inventory.records.all','عرض إدخالات جميع المستخدمين','المخزون • نطاق السجلات'),
    ('sales.records.own','عرض إدخالاته فقط','المبيعات • نطاق السجلات'),
    ('sales.records.all','عرض إدخالات جميع المستخدمين','المبيعات • نطاق السجلات'),
    ('purchases.records.own','عرض إدخالاته فقط','المشتريات • نطاق السجلات'),
    ('purchases.records.all','عرض إدخالات جميع المستخدمين','المشتريات • نطاق السجلات'),
    ('maintenance.records.own','عرض إدخالاته فقط','الصيانة • نطاق السجلات'),
    ('maintenance.records.all','عرض إدخالات جميع المستخدمين','الصيانة • نطاق السجلات'),
    ('accounting.records.own','عرض إدخالاته فقط','المحاسبة • نطاق السجلات'),
    ('accounting.records.all','عرض إدخالات جميع المستخدمين','المحاسبة • نطاق السجلات'),
    ('cashbox.records.own','عرض إدخالاته فقط','الصناديق • نطاق السجلات'),
    ('cashbox.records.all','عرض إدخالات جميع المستخدمين','الصناديق • نطاق السجلات'),
    ('expenses.records.own','عرض إدخالاته فقط','المصروفات • نطاق السجلات'),
    ('expenses.records.all','عرض إدخالات جميع المستخدمين','المصروفات • نطاق السجلات'),
    ('installments.records.own','عرض إدخالاته فقط','الأقساط • نطاق السجلات'),
    ('installments.records.all','عرض إدخالات جميع المستخدمين','الأقساط • نطاق السجلات'),
    ('warehouses.records.own','عرض إدخالاته فقط','المخازن • نطاق السجلات'),
    ('warehouses.records.all','عرض إدخالات جميع المستخدمين','المخازن • نطاق السجلات'),
    ('customer_service.records.own','عرض إدخالاته فقط','خدمة العملاء • نطاق السجلات'),
    ('customer_service.records.all','عرض إدخالات جميع المستخدمين','خدمة العملاء • نطاق السجلات'),
    ('users.records.own','عرض سجله فقط','المستخدمون • نطاق السجلات'),
    ('users.records.all','عرض سجلات جميع المستخدمين','المستخدمون • نطاق السجلات')
), company_scope as (
  select slug from public.companies where trim(coalesce(slug,'')) <> ''
)
insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
select
  c.slug,
  'permissions',
  'perm-'||substr(md5(p.code),1,24),
  jsonb_build_object(
    'id','perm-'||substr(md5(p.code),1,24),
    'code',p.code,
    'name',p.name_ar,
    'module',p.module,
    'description','تحديد ما إذا كان المستخدم يرى إدخالاته فقط أو إدخالات جميع المستخدمين داخل هذا المودل'
  ),
  false,null,now()
from company_scope c
cross join scope_permissions p
on conflict(company_id,entity_type,record_id) do update
set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

-- Reusable server-side scope rule for list/read RPCs. Backward compatibility is
-- intentional: until own/all is assigned, existing company-level visibility is
-- unchanged. Once either scope is assigned it becomes explicit and enforceable.
create or replace function public.erp_r77_user_can_view_record_owner(
  p_company_id uuid,
  p_module text,
  p_owner_user_id text
) returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_local_user_id text;
  v_permissions text[] := array[]::text[];
  v_module text := trim(coalesce(p_module,''));
begin
  if auth.uid() is null or v_module='' then return false; end if;
  if exists (
    select 1 from public.company_memberships m
    where m.company_id=p_company_id and m.user_uid=auth.uid()::text and m.is_active
      and (m.is_system_admin or m.role_code in ('owner','admin'))
  ) then return true; end if;

  select m.local_user_id into v_local_user_id
  from public.company_memberships m
  where m.company_id=p_company_id and m.user_uid=auth.uid()::text and m.is_active
  limit 1;
  if v_local_user_id is null then return false; end if;

  v_permissions := public.erp_get_cloud_user_permissions(v_local_user_id);
  if (v_module||'.records.all') = any(v_permissions) then return true; end if;
  if (v_module||'.records.own') = any(v_permissions) then
    return p_owner_user_id is not null and p_owner_user_id=v_local_user_id;
  end if;
  return true;
end;
$$;

revoke all on function public.erp_r77_user_can_view_record_owner(uuid,text,text) from public,anon;
grant execute on function public.erp_r77_user_can_view_record_owner(uuid,text,text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
