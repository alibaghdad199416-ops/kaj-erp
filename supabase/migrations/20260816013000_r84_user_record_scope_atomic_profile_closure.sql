-- Quality Line ERP R84
-- Per-user record scope is PostgreSQL-authoritative. Each record-scoped module
-- supports either the current user's entries or all company entries while old
-- role assignments remain backward compatible until deliberately customized.
begin;

-- ---------------------------------------------------------------------------
-- 1. Canonical permission catalog.
-- ---------------------------------------------------------------------------
insert into public.permissions(code,name_ar,name_en) values
  ('users.image.update','تعديل صورة المستخدم','Update user image'),
  ('users.credentials.update','تعديل بيانات دخول المستخدم','Update user credentials'),
  ('customers.image.update','تعديل صورة العميل','Update customer image'),
  ('suppliers.image.update','تعديل صورة المورد','Update supplier image'),
  ('cars.images.manage','إدارة صور السيارات','Manage vehicle images'),
  ('inventory.images.manage','إدارة صور المنتجات','Manage product images'),
  ('reports.audit.view','عرض تدقيق التقارير','View report audit details'),
  ('reports.contextual.view','عرض تفاصيل التقارير السياقية','View contextual report details'),
  ('reports.financial_details.view','عرض التفاصيل المالية للتقارير','View financial report details'),
  ('customers.records.own','عرض إدخالات المستخدم نفسه - العملاء','View own customer records'),
  ('customers.records.all','عرض إدخالات جميع المستخدمين - العملاء','View all customer records'),
  ('suppliers.records.own','عرض إدخالات المستخدم نفسه - الموردون','View own supplier records'),
  ('suppliers.records.all','عرض إدخالات جميع المستخدمين - الموردون','View all supplier records'),
  ('cars.records.own','عرض إدخالات المستخدم نفسه - السيارات','View own vehicle records'),
  ('cars.records.all','عرض إدخالات جميع المستخدمين - السيارات','View all vehicle records'),
  ('inventory.records.own','عرض إدخالات المستخدم نفسه - المخزون','View own inventory records'),
  ('inventory.records.all','عرض إدخالات جميع المستخدمين - المخزون','View all inventory records'),
  ('warehouses.records.own','عرض إدخالات المستخدم نفسه - المخازن','View own warehouse records'),
  ('warehouses.records.all','عرض إدخالات جميع المستخدمين - المخازن','View all warehouse records'),
  ('customer_service.records.own','عرض إدخالات المستخدم نفسه - خدمة العملاء','View own customer service records'),
  ('customer_service.records.all','عرض إدخالات جميع المستخدمين - خدمة العملاء','View all customer service records'),
  ('sales.records.own','عرض إدخالات المستخدم نفسه - المبيعات','View own sales records'),
  ('sales.records.all','عرض إدخالات جميع المستخدمين - المبيعات','View all sales records'),
  ('purchases.records.own','عرض إدخالات المستخدم نفسه - المشتريات','View own purchase records'),
  ('purchases.records.all','عرض إدخالات جميع المستخدمين - المشتريات','View all purchase records'),
  ('maintenance.records.own','عرض إدخالات المستخدم نفسه - الصيانة','View own maintenance records'),
  ('maintenance.records.all','عرض إدخالات جميع المستخدمين - الصيانة','View all maintenance records'),
  ('accounting.records.own','عرض إدخالات المستخدم نفسه - المحاسبة','View own accounting records'),
  ('accounting.records.all','عرض إدخالات جميع المستخدمين - المحاسبة','View all accounting records'),
  ('cashbox.records.own','عرض إدخالات المستخدم نفسه - الصناديق','View own cashbox records'),
  ('cashbox.records.all','عرض إدخالات جميع المستخدمين - الصناديق','View all cashbox records'),
  ('expenses.records.own','عرض إدخالات المستخدم نفسه - المصروفات','View own expense records'),
  ('expenses.records.all','عرض إدخالات جميع المستخدمين - المصروفات','View all expense records'),
  ('installments.records.own','عرض إدخالات المستخدم نفسه - الأقساط','View own installment records'),
  ('installments.records.all','عرض إدخالات جميع المستخدمين - الأقساط','View all installment records')
on conflict(code) do update set
  name_ar=excluded.name_ar,
  name_en=excluded.name_en;

insert into public.role_permissions(role_code,permission_code)
select r.role_code,p.code
from (values('owner'),('admin')) as r(role_code)
join public.permissions p on p.code like '%.records.all'
on conflict do nothing;

-- Mirror the canonical permission catalog into every tenant access snapshot.
do $$
declare c record;
begin
  if to_regprocedure('public.erp_seed_access_catalog(uuid)') is not null then
    for c in select id from public.companies where is_active loop
      perform public.erp_seed_access_catalog(c.id);
    end loop;
  end if;
end $$;

-- Existing explicit user overrides historically implied company-wide rows.
-- Preserve that behavior during migration by adding every records.all scope.
with override_users as (
  select distinct company_id,record_id as user_id
  from public.erp_records
  where entity_type='user_permission_overrides'
    and deleted_at is null and not is_deleted
    and coalesce((payload->>'enabled')::boolean,true)
), scope_permissions as (
  select company_id,record_id
  from public.erp_records
  where entity_type='permissions'
    and deleted_at is null and not is_deleted
    and payload->>'code' like '%.records.all'
)
insert into public.erp_records(
  company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
)
select
  u.company_id,'user_permissions',u.user_id||'::'||p.record_id,
  jsonb_build_object('userId',u.user_id,'permissionId',p.record_id),
  false,null,now()
from override_users u
join scope_permissions p on p.company_id=u.company_id
on conflict(company_id,entity_type,record_id) do update set
  payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

-- ---------------------------------------------------------------------------
-- 2. Shared record-scope helpers.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r84_user_has_permission_override(p_company_id uuid)
returns boolean
language plpgsql stable security definer set search_path=public as $$
declare
  v_slug text;
  v_user_id text;
begin
  if p_company_id is null or auth.uid() is null then return false; end if;
  select slug into v_slug from public.companies where id=p_company_id and is_active limit 1;
  v_user_id:=public.erp_current_cloud_erp_user_id(p_company_id);
  if v_slug is null or v_user_id is null then return false; end if;
  return exists(
    select 1 from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='user_permission_overrides'
      and r.record_id=v_user_id
      and r.deleted_at is null and not r.is_deleted
      and coalesce((r.payload->>'enabled')::boolean,true)
  );
end;
$$;

create or replace function public.erp_r84_record_scope_mode(
  p_company_id uuid,p_resource text
) returns text
language plpgsql stable security definer set search_path=public as $$
declare v_resource text:=btrim(coalesce(p_resource,''));
begin
  if p_company_id is null or v_resource='' then return 'none'; end if;
  if auth.uid() is null or public.is_company_admin(p_company_id) then return 'all'; end if;
  if public.erp_cloud_user_has_permission(p_company_id,v_resource||'.records.all') then
    return 'all';
  end if;
  if public.erp_cloud_user_has_permission(p_company_id,v_resource||'.records.own') then
    return 'own';
  end if;
  -- Explicit per-user overrides are fail-closed when a newly customized user
  -- omits a record scope. Existing overrides were backfilled to records.all.
  if public.erp_r84_user_has_permission_override(p_company_id) then return 'own'; end if;
  return 'all';
end;
$$;

create or replace function public.erp_r84_record_visible(
  p_company_id uuid,
  p_resource text,
  p_created_by uuid default null,
  p_created_by_text text default null
) returns boolean
language plpgsql stable security definer set search_path=public as $$
declare
  v_mode text;
  v_auth text:=coalesce(auth.uid()::text,'');
  v_erp_user text;
  v_creator text:=btrim(coalesce(p_created_by_text,''));
begin
  if auth.uid() is null then return true; end if;
  if not public.is_active_company_member(p_company_id) then return false; end if;
  v_mode:=public.erp_r84_record_scope_mode(p_company_id,p_resource);
  if v_mode='all' then return true; end if;
  if v_mode<>'own' then return false; end if;
  if p_created_by is not null and p_created_by=auth.uid() then return true; end if;
  v_erp_user:=coalesce(public.erp_current_cloud_erp_user_id(p_company_id),'');
  if v_creator<>'' and v_creator in (v_auth,v_erp_user) then return true; end if;
  -- Historical rows created before attribution existed stay visible. Every new
  -- record after this migration is attributed and therefore strictly scoped.
  return p_created_by is null and v_creator='';
end;
$$;

revoke all on function public.erp_r84_user_has_permission_override(uuid) from public,anon;
revoke all on function public.erp_r84_record_scope_mode(uuid,text) from public,anon;
revoke all on function public.erp_r84_record_visible(uuid,text,uuid,text) from public,anon;
grant execute on function public.erp_r84_user_has_permission_override(uuid) to authenticated,service_role;
grant execute on function public.erp_r84_record_scope_mode(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r84_record_visible(uuid,text,uuid,text) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 3. Creator attribution for operational tables that did not originally have it.
-- ---------------------------------------------------------------------------
alter table if exists public.erp_sales_orders_cloud
  add column if not exists created_by uuid default auth.uid();
alter table if exists public.erp_purchase_orders_cloud
  add column if not exists created_by uuid default auth.uid();
alter table if exists public.erp_maintenance_orders
  add column if not exists created_by uuid default auth.uid();
alter table if exists public.erp_reservations
  add column if not exists created_by uuid default auth.uid();

update public.erp_sales_orders_cloud o
set created_by=(
  select a.performed_by from public.erp_commercial_workflow_audit a
  where a.company_id=o.company_id and a.module='sales'
    and a.parent_id=o.id and a.performed_by is not null
  order by a.performed_at,a.id limit 1
)
where o.created_by is null and exists(
  select 1 from public.erp_commercial_workflow_audit a
  where a.company_id=o.company_id and a.module='sales'
    and a.parent_id=o.id and a.performed_by is not null
);

update public.erp_purchase_orders_cloud o
set created_by=(
  select a.performed_by from public.erp_commercial_workflow_audit a
  where a.company_id=o.company_id and a.module='purchases'
    and a.parent_id=o.id and a.performed_by is not null
  order by a.performed_at,a.id limit 1
)
where o.created_by is null and exists(
  select 1 from public.erp_commercial_workflow_audit a
  where a.company_id=o.company_id and a.module='purchases'
    and a.parent_id=o.id and a.performed_by is not null
);

create index if not exists erp_sales_orders_cloud_creator_idx
  on public.erp_sales_orders_cloud(company_id,created_by,updated_at desc) where not is_deleted;
create index if not exists erp_purchase_orders_cloud_creator_idx
  on public.erp_purchase_orders_cloud(company_id,created_by,updated_at desc) where not is_deleted;
create index if not exists erp_maintenance_orders_creator_idx
  on public.erp_maintenance_orders(company_id,created_by,updated_at desc) where not is_deleted;

-- ---------------------------------------------------------------------------
-- 4. Writes are scoped too; hidden records cannot be modified by direct RPC.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r84_scoped_write_guard()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_resource text:=case tg_table_name
    when 'erp_customers' then 'customers'
    when 'erp_suppliers' then 'suppliers'
    when 'erp_cars' then 'cars'
    when 'erp_car_images' then 'cars'
    when 'erp_warehouses' then 'warehouses'
    when 'erp_inventory' then 'inventory'
    when 'erp_inventory_groups' then 'inventory'
    when 'erp_product_images' then 'inventory'
    when 'erp_warehouse_stock' then 'inventory'
    when 'erp_inventory_movements' then 'inventory'
    when 'erp_warehouse_transfers' then 'inventory'
    when 'erp_warehouse_transfer_items' then 'inventory'
    when 'erp_sales' then 'sales'
    when 'erp_purchases' then 'purchases'
    when 'erp_installments' then 'installments'
    when 'erp_cash_accounts' then 'cashbox'
    when 'erp_cash_transactions' then 'cashbox'
    when 'erp_expenses' then 'expenses'
    when 'erp_journal_entries' then 'accounting'
    when 'erp_sales_orders_cloud' then 'sales'
    when 'erp_purchase_orders_cloud' then 'purchases'
    when 'erp_maintenance_orders' then 'maintenance'
    when 'erp_reservations' then 'customer_service'
    else null end;
begin
  if v_resource is null or auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if tg_op='INSERT' then
    if new.created_by is null then new.created_by:=auth.uid(); end if;
    return new;
  end if;
  if not public.erp_r84_record_visible(old.company_id,v_resource,old.created_by,null) then
    raise exception 'record_scope_denied:%.records.own',v_resource using errcode='42501';
  end if;
  if tg_op='UPDATE' then
    new.created_by:=old.created_by;
    return new;
  end if;
  return old;
end;
$$;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'erp_customers','erp_suppliers','erp_cars','erp_car_images','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images','erp_warehouse_stock',
    'erp_inventory_movements','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_sales','erp_purchases','erp_installments','erp_cash_accounts',
    'erp_cash_transactions','erp_expenses','erp_journal_entries',
    'erp_sales_orders_cloud','erp_purchase_orders_cloud','erp_maintenance_orders','erp_reservations'
  ] loop
    if to_regclass('public.'||v_table) is not null and exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table and column_name='created_by'
    ) then
      execute format('drop trigger if exists aa_r84_record_scope_guard on public.%I',v_table);
      execute format(
        'create trigger aa_r84_record_scope_guard before insert or update or delete on public.%I '
        ||'for each row execute function public.erp_r84_scoped_write_guard()',v_table
      );
    end if;
  end loop;
end $$;

create or replace function public.erp_r84_opportunity_scope_guard()
returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_company uuid;
  v_creator text;
  v_current_erp text;
  v_entity text;
begin
  v_entity:=case when tg_op='DELETE' then old.entity_type else new.entity_type end;
  if v_entity<>'opportunities' or auth.uid() is null then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  select id into v_company from public.companies
  where slug=case when tg_op='DELETE' then old.company_id else new.company_id end
    and is_active limit 1;
  if v_company is null then raise exception 'company_membership_required' using errcode='42501'; end if;
  v_current_erp:=public.erp_current_cloud_erp_user_id(v_company);
  if tg_op='INSERT' then
    if coalesce(btrim(new.payload->>'createdByUserId'),'')='' then
      new.payload:=new.payload||jsonb_build_object(
        'createdByUserId',coalesce(v_current_erp,auth.uid()::text)
      );
    end if;
    return new;
  end if;
  v_creator:=coalesce(old.payload->>'createdByUserId',old.payload->>'createdBy','');
  if not public.erp_r84_record_visible(v_company,'customer_service',null,v_creator) then
    raise exception 'record_scope_denied:customer_service.records.own' using errcode='42501';
  end if;
  if tg_op='UPDATE' then
    if coalesce(btrim(old.payload->>'createdByUserId'),'')<>'' then
      new.payload:=new.payload||jsonb_build_object(
        'createdByUserId',old.payload->>'createdByUserId'
      );
    end if;
    if coalesce(btrim(old.payload->>'createdByUserName'),'')<>'' then
      new.payload:=new.payload||jsonb_build_object(
        'createdByUserName',old.payload->>'createdByUserName'
      );
    end if;
    return new;
  end if;
  return old;
end;
$$;
drop trigger if exists aa_r84_opportunity_scope_guard on public.erp_records;
create trigger aa_r84_opportunity_scope_guard
before insert or update or delete on public.erp_records
for each row execute function public.erp_r84_opportunity_scope_guard();

-- ---------------------------------------------------------------------------
-- 5. Master readers enforce record scope before field masking.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,p_table text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_resource text;
  v_row record;
  v_rel regclass;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_resource:=public.erp_r9_master_resource_for_table(p_table);
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table using errcode='22023'; end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  for v_row in execute format(
    'select id::text id,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end data,'
    ||'version,updated_at,created_by from public.%I r where company_id=$1 '
    ||'and not coalesce(is_deleted,false) '
    ||'and not public.erp_r15_pending_delete_exists($1,%L,r.id) '
    ||'and public.erp_r84_record_visible($1,%L,r.created_by,null) order by updated_at desc',
    p_table,p_table,v_resource
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
      ||jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
  end loop;
  return;
end;
$$;

create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,p_table text,p_record_id text
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_permission text;
  v_resource text;
  v_row record;
  v_rel regclass;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_resource:=public.erp_r9_master_resource_for_table(p_table);
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table using errcode='22023'; end if;
  v_rel:=to_regclass(format('public.%I',p_table));
  if v_rel is null then raise exception 'master_table_not_found:%',p_table using errcode='42P01'; end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  if public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id) then return null; end if;
  execute format(
    'select id::text id,case when jsonb_typeof(data)=''object'' then data else ''{}''::jsonb end data,'
    ||'version,updated_at,created_by from public.%I where company_id=$1 and id=$2 '
    ||'and not coalesce(is_deleted,false) and public.erp_r84_record_visible($1,%L,created_by,null)',
    p_table,v_resource
  ) into v_row using p_company_id,p_record_id;
  if v_row.id is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
    ||jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Sales, purchases, maintenance and CRM operational reads.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'sales',x,'sales.view')
  from public.erp_list_cloud_sales_workflow_orders(p_company_id) x
  join public.erp_sales_orders_cloud o
    on o.company_id=p_company_id and o.id::text=x->>'id' and not o.is_deleted
  where public.erp_r84_record_visible(p_company_id,'sales',o.created_by,null);
$$;

create or replace function public.erp_r9_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'purchases',x,'purchases.view')
  from public.erp_list_cloud_purchase_workflow_orders(p_company_id) x
  join public.erp_purchase_orders_cloud o
    on o.company_id=p_company_id and o.id::text=x->>'id' and not o.is_deleted
  where public.erp_r84_record_visible(p_company_id,'purchases',o.created_by,null);
$$;

create or replace function public.erp_r9_find_sales_order_by_opportunity(
  p_company_id uuid,p_opportunity_id text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'sales',jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'status',o.status,'opportunityId',o.opportunity_id,
    'customerId',o.customer_id,'updatedAt',o.updated_at),'sales.view')
  from public.erp_sales_orders_cloud o
  where o.company_id=p_company_id and o.opportunity_id=p_opportunity_id and not o.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_r84_record_visible(p_company_id,'sales',o.created_by,null)
  order by o.updated_at desc limit 2;
$$;

create or replace function public.erp_r9_find_purchase_order_by_opportunity(
  p_company_id uuid,p_opportunity_id text
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'purchases',jsonb_build_object(
    'id',o.id,'orderNumber',o.order_number,'status',o.status,'opportunityId',o.opportunity_id,
    'supplierId',o.supplier_id,'updatedAt',o.updated_at),'purchases.view')
  from public.erp_purchase_orders_cloud o
  where o.company_id=p_company_id and o.opportunity_id=p_opportunity_id and not o.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_r84_record_visible(p_company_id,'purchases',o.created_by,null)
  order by o.updated_at desc limit 2;
$$;

create or replace function public.erp_r9_list_cloud_maintenance_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',to_jsonb(x),'maintenance.view')
  from public.erp_list_cloud_maintenance_orders(p_company_id) x
  join public.erp_maintenance_orders o
    on o.company_id=p_company_id and o.id::text=to_jsonb(x)->>'id' and not o.is_deleted
  where public.erp_r84_record_visible(p_company_id,'maintenance',o.created_by,null);
$$;

create or replace function public.erp_r9_get_cloud_maintenance_order_lines(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(p_company_id,'maintenance',to_jsonb(x),'maintenance.view')
  from public.erp_get_cloud_maintenance_order_lines(p_company_id,p_order_id) x
  where exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
      and public.erp_r84_record_visible(p_company_id,'maintenance',o.created_by,null)
  );
$$;

create or replace function public.erp_r49_get_sales_order_draft(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb; v_updated timestamptz; v_creator uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.view') then
    raise exception 'permission_denied:sales.view' using errcode='42501';
  end if;
  select updated_at,created_by into v_updated,v_creator from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found or not public.erp_r84_record_visible(p_company_id,'sales',v_creator,null) then return null; end if;
  v_result:=public.erp_get_cloud_sales_order_draft(p_company_id,p_order_id);
  if v_result is null then return null; end if;
  return jsonb_set(v_result,'{order,updatedAt}',to_jsonb(v_updated),true);
end $$;

create or replace function public.erp_r49_get_purchase_order_draft(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb; v_updated timestamptz; v_creator uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.view') then
    raise exception 'permission_denied:purchases.view' using errcode='42501';
  end if;
  select updated_at,created_by into v_updated,v_creator from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found or not public.erp_r84_record_visible(p_company_id,'purchases',v_creator,null) then return null; end if;
  v_result:=public.erp_get_cloud_purchase_order_draft(p_company_id,p_order_id);
  if v_result is null then return null; end if;
  return jsonb_set(v_result,'{order,updatedAt}',to_jsonb(v_updated),true);
end $$;

create or replace function public.erp_r84_list_opportunities(p_company_id uuid)
returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_slug text;
begin
  perform public.erp_active_company_context(p_company_id);
  select slug into v_slug from public.companies where id=p_company_id and is_active limit 1;
  if v_slug is null then raise exception 'membership_not_found' using errcode='42501'; end if;
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'customer_service.view') then
    raise exception 'permission_denied:customer_service.view' using errcode='42501';
  end if;
  return query
  select public.erp_r9_filter_readable_json(
      p_company_id,'opportunities',
      r.payload||jsonb_build_object('updatedAt',r.updated_at,'_cloudUpdatedAt',r.updated_at)
    )
  from public.erp_records r
  where r.company_id=v_slug and r.entity_type='opportunities'
    and r.deleted_at is null and not r.is_deleted
    and public.erp_r84_record_visible(
      p_company_id,'customer_service',null,
      coalesce(r.payload->>'createdByUserId',r.payload->>'createdBy','')
    )
  order by r.updated_at desc
  limit 500;
end;
$$;
revoke all on function public.erp_r84_list_opportunities(uuid) from public,anon;
grant execute on function public.erp_r84_list_opportunities(uuid) to authenticated,service_role;

-- ---------------------------------------------------------------------------
-- 7. Restrictive RLS scope is ANDed with every existing permissive policy.
-- This closes direct/realtime reads without disturbing existing write policies.
-- ---------------------------------------------------------------------------
do $$
declare v_table text; v_resource text;
begin
  for v_table,v_resource in values
    ('erp_cars','cars'),('erp_car_images','cars'),('erp_customers','customers'),
    ('erp_suppliers','suppliers'),('erp_warehouses','warehouses'),
    ('erp_inventory','inventory'),('erp_inventory_groups','inventory'),
    ('erp_product_images','inventory'),('erp_warehouse_stock','inventory'),
    ('erp_inventory_movements','inventory'),('erp_warehouse_transfers','inventory'),
    ('erp_sales','sales'),('erp_purchases','purchases'),('erp_installments','installments'),
    ('erp_cash_accounts','cashbox'),('erp_cash_transactions','cashbox'),
    ('erp_expenses','expenses'),('erp_journal_entries','accounting'),
    ('erp_sales_orders_cloud','sales'),('erp_purchase_orders_cloud','purchases'),
    ('erp_maintenance_orders','maintenance'),('erp_reservations','customer_service')
  loop
    if to_regclass('public.'||v_table) is null or not exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name=v_table and column_name='created_by'
    ) then continue; end if;
    execute format('drop policy if exists %I on public.%I',left(v_table||'_r84_record_scope',63),v_table);
    execute format(
      'create policy %I on public.%I as restrictive for select to authenticated using ('
      ||'public.is_active_company_member(company_id) '
      ||'and public.erp_r84_record_visible(company_id,%L,created_by,null))',
      left(v_table||'_r84_record_scope',63),v_table,v_resource
    );
  end loop;
end $$;

-- Compatibility-record opportunities also get restrictive direct-read scope.
drop policy if exists erp_records_r84_opportunity_scope on public.erp_records;
create policy erp_records_r84_opportunity_scope
on public.erp_records as restrictive for select to authenticated using (
  entity_type<>'opportunities'
  or exists(
    select 1 from public.companies c
    where c.slug=erp_records.company_id and c.is_active
      and public.erp_r84_record_visible(
        c.id,'customer_service',null,
        coalesce(erp_records.payload->>'createdByUserId',erp_records.payload->>'createdBy','')
      )
  )
);

-- Child tables inherit scope from their parent record.
drop policy if exists erp_sales_order_items_cloud_r84_record_scope on public.erp_sales_order_items_cloud;
create policy erp_sales_order_items_cloud_r84_record_scope
on public.erp_sales_order_items_cloud as restrictive for select to authenticated using (
  exists(
    select 1 from public.erp_sales_orders_cloud o
    where o.company_id=erp_sales_order_items_cloud.company_id
      and o.id=erp_sales_order_items_cloud.order_id and not o.is_deleted
      and public.erp_r84_record_visible(o.company_id,'sales',o.created_by,null)
  )
);

drop policy if exists erp_purchase_order_items_cloud_r84_record_scope on public.erp_purchase_order_items_cloud;
create policy erp_purchase_order_items_cloud_r84_record_scope
on public.erp_purchase_order_items_cloud as restrictive for select to authenticated using (
  exists(
    select 1 from public.erp_purchase_orders_cloud o
    where o.company_id=erp_purchase_order_items_cloud.company_id
      and o.id=erp_purchase_order_items_cloud.order_id and not o.is_deleted
      and public.erp_r84_record_visible(o.company_id,'purchases',o.created_by,null)
  )
);

drop policy if exists erp_maintenance_parts_r84_record_scope on public.erp_maintenance_parts;
create policy erp_maintenance_parts_r84_record_scope
on public.erp_maintenance_parts as restrictive for select to authenticated using (
  exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=erp_maintenance_parts.company_id
      and o.id=erp_maintenance_parts.maintenance_order_id and not o.is_deleted
      and public.erp_r84_record_visible(o.company_id,'maintenance',o.created_by,null)
  )
);

drop policy if exists erp_maintenance_payments_r84_record_scope on public.erp_maintenance_payments;
create policy erp_maintenance_payments_r84_record_scope
on public.erp_maintenance_payments as restrictive for select to authenticated using (
  exists(
    select 1 from public.erp_maintenance_orders o
    where o.company_id=erp_maintenance_payments.company_id
      and o.id=erp_maintenance_payments.maintenance_order_id and not o.is_deleted
      and public.erp_r84_record_visible(o.company_id,'maintenance',o.created_by,null)
  )
);

notify pgrst,'reload schema';
commit;
