-- Quality Line ERP 17.75.0
-- Tenant-scoped RBAC + ABAC permissions with branch/owner/department data scopes.

create table if not exists public.erp_permission_roles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  description text,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_by text not null default public.current_external_uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, code)
);

create table if not exists public.erp_permission_catalog (
  code text primary key,
  module_code text not null,
  action_code text not null,
  name_ar text not null,
  name_en text not null,
  risk_level text not null default 'normal' check (risk_level in ('normal','sensitive','critical')),
  unique(module_code, action_code)
);

create table if not exists public.erp_role_permission_grants (
  company_id uuid not null references public.companies(id) on delete cascade,
  role_id uuid not null references public.erp_permission_roles(id) on delete cascade,
  permission_code text not null references public.erp_permission_catalog(code) on delete cascade,
  effect text not null default 'allow' check (effect in ('allow','deny')),
  conditions jsonb not null default '{}'::jsonb,
  granted_by text not null default public.current_external_uid(),
  granted_at timestamptz not null default now(),
  primary key(role_id, permission_code)
);

create table if not exists public.erp_user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_uid text not null,
  role_id uuid not null references public.erp_permission_roles(id) on delete cascade,
  branch_id text,
  department_id text,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  is_active boolean not null default true,
  assigned_by text not null default public.current_external_uid(),
  assigned_at timestamptz not null default now(),
  unique(company_id, user_uid, role_id, branch_id, department_id)
);

create table if not exists public.erp_role_record_scopes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  role_id uuid not null references public.erp_permission_roles(id) on delete cascade,
  module_code text not null,
  scope_type text not null check (scope_type in ('all','branch','department','own')),
  scope_value text,
  actions text[] not null default array['read'],
  created_by text not null default public.current_external_uid(),
  created_at timestamptz not null default now(),
  unique(company_id, role_id, module_code, scope_type, scope_value)
);

create index if not exists erp_permission_roles_company_idx on public.erp_permission_roles(company_id, is_active, code);
create index if not exists erp_role_permission_grants_lookup_idx on public.erp_role_permission_grants(company_id, permission_code, role_id);
create index if not exists erp_user_role_assignments_lookup_idx on public.erp_user_role_assignments(company_id, user_uid, is_active);
create index if not exists erp_role_record_scopes_lookup_idx on public.erp_role_record_scopes(company_id, role_id, module_code);

alter table public.erp_permission_roles enable row level security;
alter table public.erp_role_permission_grants enable row level security;
alter table public.erp_user_role_assignments enable row level security;
alter table public.erp_role_record_scopes enable row level security;
alter table public.erp_permission_catalog enable row level security;

revoke all on public.erp_permission_roles, public.erp_role_permission_grants,
  public.erp_user_role_assignments, public.erp_role_record_scopes from anon;
grant select on public.erp_permission_catalog to authenticated;

drop policy if exists erp_permission_catalog_authenticated_read on public.erp_permission_catalog;
create policy erp_permission_catalog_authenticated_read on public.erp_permission_catalog
for select to authenticated using (true);

-- Administrative data is visible and mutable only to company administrators.
do $$
declare t text;
begin
  foreach t in array array['erp_permission_roles','erp_role_permission_grants','erp_user_role_assignments','erp_role_record_scopes'] loop
    execute format('drop policy if exists erp_permissions_admin_all on public.%I', t);
    execute format('create policy erp_permissions_admin_all on public.%I for all to authenticated using (public.is_company_admin(company_id)) with check (public.is_company_admin(company_id))', t);
  end loop;
end $$;

grant select, insert, update, delete on public.erp_permission_roles,
  public.erp_role_permission_grants, public.erp_user_role_assignments,
  public.erp_role_record_scopes to authenticated;

insert into public.erp_permission_catalog(code,module_code,action_code,name_ar,name_en,risk_level) values
('cars.read','cars','read','عرض السيارات','Read cars','normal'),
('cars.create','cars','create','إضافة السيارات','Create cars','normal'),
('cars.update','cars','update','تعديل السيارات','Update cars','sensitive'),
('cars.delete','cars','delete','حذف السيارات','Delete cars','critical'),
('cars.export','cars','export','تصدير السيارات','Export cars','sensitive'),
('customers.read','customers','read','عرض العملاء','Read customers','normal'),
('customers.create','customers','create','إضافة العملاء','Create customers','normal'),
('customers.update','customers','update','تعديل العملاء','Update customers','sensitive'),
('customers.delete','customers','delete','حذف العملاء','Delete customers','critical'),
('suppliers.read','suppliers','read','عرض الموردين','Read suppliers','normal'),
('suppliers.create','suppliers','create','إضافة الموردين','Create suppliers','normal'),
('suppliers.update','suppliers','update','تعديل الموردين','Update suppliers','sensitive'),
('suppliers.delete','suppliers','delete','حذف الموردين','Delete suppliers','critical'),
('sales.read','sales','read','عرض المبيعات','Read sales','normal'),
('sales.create','sales','create','إنشاء المبيعات','Create sales','normal'),
('sales.update','sales','update','تعديل المبيعات','Update sales','sensitive'),
('sales.delete','sales','delete','حذف المبيعات','Delete sales','critical'),
('sales.approve','sales','approve','اعتماد المبيعات','Approve sales','critical'),
('sales.cancel','sales','cancel','إلغاء اعتماد المبيعات','Cancel sales','critical'),
('sales.print','sales','print','طباعة المبيعات','Print sales','normal'),
('sales.export','sales','export','تصدير المبيعات','Export sales','sensitive'),
('purchases.read','purchases','read','عرض المشتريات','Read purchases','normal'),
('purchases.create','purchases','create','إنشاء المشتريات','Create purchases','normal'),
('purchases.update','purchases','update','تعديل المشتريات','Update purchases','sensitive'),
('purchases.delete','purchases','delete','حذف المشتريات','Delete purchases','critical'),
('purchases.approve','purchases','approve','اعتماد المشتريات','Approve purchases','critical'),
('inventory.read','inventory','read','عرض المخزون','Read inventory','normal'),
('inventory.adjust','inventory','adjust','تسوية المخزون','Adjust inventory','critical'),
('inventory.transfer','inventory','transfer','نقل المخزون','Transfer inventory','sensitive'),
('accounting.read','accounting','read','عرض المحاسبة','Read accounting','sensitive'),
('accounting.post','accounting','post','ترحيل القيود','Post entries','critical'),
('accounting.reverse','accounting','reverse','عكس القيود','Reverse entries','critical'),
('installments.read','installments','read','عرض الأقساط','Read installments','normal'),
('installments.collect','installments','collect','تحصيل الأقساط','Collect installments','sensitive'),
('reports.read','reports','read','عرض التقارير','Read reports','normal'),
('reports.export','reports','export','تصدير التقارير','Export reports','sensitive'),
('backup.create','backup','create','إنشاء نسخة احتياطية','Create backup','critical'),
('backup.restore','backup','restore','استعادة نسخة احتياطية','Restore backup','critical'),
('audit.read','audit','read','عرض سجل التدقيق','Read audit log','sensitive'),
('roles.manage','roles','manage','إدارة الأدوار والصلاحيات','Manage roles and permissions','critical'),
('settings.manage','settings','manage','إدارة الإعدادات','Manage settings','critical')
on conflict(code) do update set name_ar=excluded.name_ar,name_en=excluded.name_en,risk_level=excluded.risk_level;

create or replace function public.erp_permission_actor_uid()
returns text language sql stable security definer set search_path=public as $$
  select coalesce(auth.uid()::text, public.current_external_uid(), 'unknown');
$$;

create or replace function public.erp_has_permission(p_company_id uuid, p_permission_code text)
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_company_admin(p_company_id) or exists(
    select 1
    from public.erp_user_role_assignments a
    join public.erp_permission_roles r on r.id=a.role_id and r.company_id=a.company_id and r.is_active
    join public.erp_role_permission_grants g on g.role_id=r.id and g.company_id=r.company_id
    where a.company_id=p_company_id
      and a.user_uid=public.erp_permission_actor_uid()
      and a.is_active and a.valid_from<=now() and (a.valid_until is null or a.valid_until>now())
      and g.permission_code=p_permission_code and g.effect='allow'
      and not exists(
        select 1 from public.erp_role_permission_grants d
        where d.company_id=g.company_id and d.role_id=g.role_id
          and d.permission_code=p_permission_code and d.effect='deny'
      )
  );
$$;

create or replace function public.erp_assert_permission(p_company_id uuid, p_permission_code text)
returns void language plpgsql stable security definer set search_path=public as $$
begin
  if not public.erp_has_permission(p_company_id,p_permission_code) then
    raise exception 'permission_denied:%',p_permission_code using errcode='42501';
  end if;
end $$;

create or replace function public.erp_can_access_record(
  p_company_id uuid, p_module_code text, p_action text,
  p_branch_id text default null, p_department_id text default null, p_owner_uid text default null
) returns boolean language sql stable security definer set search_path=public as $$
  select public.is_company_admin(p_company_id) or exists(
    select 1
    from public.erp_user_role_assignments a
    join public.erp_permission_roles r on r.id=a.role_id and r.is_active
    join public.erp_role_record_scopes s on s.role_id=r.id and s.company_id=a.company_id
    where a.company_id=p_company_id and a.user_uid=public.erp_permission_actor_uid()
      and a.is_active and a.valid_from<=now() and (a.valid_until is null or a.valid_until>now())
      and s.module_code=p_module_code and p_action=any(s.actions)
      and (
        s.scope_type='all'
        or (s.scope_type='branch' and coalesce(s.scope_value,a.branch_id)=p_branch_id)
        or (s.scope_type='department' and coalesce(s.scope_value,a.department_id)=p_department_id)
        or (s.scope_type='own' and p_owner_uid=public.erp_permission_actor_uid())
      )
  );
$$;

create or replace function public.erp_seed_default_roles(p_company_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  if not public.is_company_admin(p_company_id) then raise exception 'roles_admin_required' using errcode='42501'; end if;
  insert into public.erp_permission_roles(company_id,code,name_ar,name_en,is_system)
  values
   (p_company_id,'owner','مالك الشركة','Company Owner',true),
   (p_company_id,'admin','المدير العام','Administrator',true),
   (p_company_id,'finance_manager','المدير المالي','Finance Manager',true),
   (p_company_id,'sales_manager','مدير المبيعات','Sales Manager',true),
   (p_company_id,'purchase_manager','مدير المشتريات','Purchase Manager',true),
   (p_company_id,'inventory_manager','مدير المخزون','Inventory Manager',true),
   (p_company_id,'accountant','المحاسب','Accountant',true),
   (p_company_id,'sales_agent','موظف المبيعات','Sales Agent',true),
   (p_company_id,'warehouse_keeper','أمين المخزن','Warehouse Keeper',true),
   (p_company_id,'auditor','مدقق الحسابات','Auditor',true)
  on conflict(company_id,code) do update set name_ar=excluded.name_ar,name_en=excluded.name_en,is_active=true;
  get diagnostics v_count=row_count;
  insert into public.erp_role_permission_grants(company_id,role_id,permission_code,effect)
  select p_company_id,r.id,p.code,'allow'
  from public.erp_permission_roles r cross join public.erp_permission_catalog p
  where r.company_id=p_company_id and r.code in ('owner','admin')
  on conflict(role_id,permission_code) do update set effect='allow';
  return v_count;
end $$;

create or replace function public.erp_permission_matrix(p_company_id uuid)
returns table(role_id uuid,role_code text,role_name_ar text,permission_code text,module_code text,action_code text,effect text)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_company_admin(p_company_id) then raise exception 'roles_admin_required' using errcode='42501'; end if;
  return query
  select r.id,r.code,r.name_ar,p.code,p.module_code,p.action_code,coalesce(g.effect,'none')
  from public.erp_permission_roles r cross join public.erp_permission_catalog p
  left join public.erp_role_permission_grants g on g.role_id=r.id and g.permission_code=p.code
  where r.company_id=p_company_id and r.is_active order by r.code,p.module_code,p.action_code;
end $$;

create or replace function public.erp_permissions_health(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare vr int; vp int; va int; vs int; vorphans int;
begin
  if not public.is_company_admin(p_company_id) then raise exception 'roles_admin_required' using errcode='42501'; end if;
  select count(*) into vr from public.erp_permission_roles where company_id=p_company_id and is_active;
  select count(*) into vp from public.erp_permission_catalog;
  select count(*) into va from public.erp_user_role_assignments where company_id=p_company_id and is_active;
  select count(*) into vs from public.erp_role_record_scopes where company_id=p_company_id;
  select count(*) into vorphans from public.erp_user_role_assignments a left join public.erp_permission_roles r on r.id=a.role_id where a.company_id=p_company_id and r.id is null;
  return jsonb_build_object('ok',vp>0 and vorphans=0,'company_id',p_company_id,'roles',vr,'permissions',vp,'active_assignments',va,'record_scopes',vs,'orphan_assignments',vorphans,'checked_at',now());
end $$;

grant execute on function public.erp_has_permission(uuid,text) to authenticated;
grant execute on function public.erp_assert_permission(uuid,text) to authenticated;
grant execute on function public.erp_can_access_record(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.erp_seed_default_roles(uuid) to authenticated;
grant execute on function public.erp_permission_matrix(uuid) to authenticated;
grant execute on function public.erp_permissions_health(uuid) to authenticated;
