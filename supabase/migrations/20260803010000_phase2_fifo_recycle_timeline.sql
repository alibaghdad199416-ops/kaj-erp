begin;

-- Quality Line ERP 18.8.8 - phase 2 operational extension.
-- This migration unifies the recycle bin, adds transaction-linked deletion
-- batches, professional document sequences, operational effective dates,
-- automatic account coding, and FIFO inventory cost layers.

create extension if not exists pgcrypto;


-- Keep the normalized PostgreSQL catalog and the ERP access catalog in sync.
-- Guarantee that every permission exposed by the administrator UI exists
-- in the normalized catalog before tenant-specific access records are seeded.
insert into public.permissions(code,name_ar,name_en)
select code,code,code
from unnest(array[
  'accounting.create',
  'accounting.delete',
  'accounting.post',
  'accounting.reverse',
  'accounting.update',
  'accounting.view',
  'approvals.decide',
  'approvals.view',
  'audit.view',
  'cars.create',
  'cars.delete',
  'cars.update',
  'cars.view',
  'cashbox.payment',
  'cashbox.receipt',
  'customer_service.create',
  'customer_service.view',
  'customers.create',
  'customers.delete',
  'customers.update',
  'customers.view',
  'dashboard.view',
  'inventory.adjust',
  'inventory.create',
  'inventory.delete',
  'inventory.issue',
  'inventory.receive',
  'inventory.transfer',
  'inventory.update',
  'inventory.view',
  'maintenance.approve',
  'maintenance.cancel',
  'maintenance.create',
  'maintenance.delete',
  'maintenance.update',
  'maintenance.view',
  'periods.close',
  'periods.reopen',
  'periods.view',
  'permissions.scopes.manage',
  'purchases.approve',
  'purchases.cancel',
  'purchases.create',
  'purchases.delete',
  'purchases.update',
  'purchases.view',
  'reports.export',
  'reports.view',
  'sales.approve',
  'sales.cancel',
  'sales.create',
  'sales.delete',
  'sales.update',
  'sales.view',
  'settings.backup',
  'settings.recycle_bin.purge',
  'settings.recycle_bin.restore',
  'settings.recycle_bin.view',
  'settings.restore',
  'settings.view',
  'suppliers.create',
  'suppliers.delete',
  'suppliers.update',
  'suppliers.view',
  'users.create',
  'users.delete',
  'users.update',
  'users.view'
]::text[]) as catalog(code)
on conflict(code) do nothing;

insert into public.permissions(code,name_ar,name_en)
select x.code,x.name_ar,x.name_en
from (values
  ('sales.approve','تصديق مستندات البيع','Approve sales documents'),
  ('sales.cancel','إلغاء مستندات البيع','Cancel sales documents'),
  ('purchases.approve','تصديق مستندات الشراء','Approve purchase documents'),
  ('purchases.cancel','إلغاء مستندات الشراء','Cancel purchase documents'),
  ('maintenance.approve','تصديق مستندات الصيانة','Approve maintenance documents'),
  ('maintenance.cancel','إلغاء مستندات الصيانة','Cancel maintenance documents'),
  ('accounting.post','ترحيل القيود','Post journals'),
  ('accounting.reverse','عكس القيود','Reverse journals'),
  ('inventory.transfer','نقل المخزون','Transfer inventory'),
  ('inventory.adjust','تسوية المخزون','Adjust inventory'),
  ('inventory.receive','استلام مخزني','Receive inventory'),
  ('inventory.issue','تجهيز مخزني','Issue inventory'),
  ('inventory.delete','حذف المواد المخزنية','Delete inventory items'),
  ('cashbox.receipt','استلام دفعة مالية','Receive payment'),
  ('cashbox.payment','تسليم دفعة مالية','Make payment'),
  ('settings.recycle_bin.view','عرض سلة المحذوفات','View recycle bin'),
  ('settings.recycle_bin.restore','استعادة المحذوفات','Restore deleted data'),
  ('settings.recycle_bin.purge','الحذف النهائي','Permanently delete data'),
  ('periods.view','عرض الجدول الزمني','View operational timeline'),
  ('periods.close','إدارة الجدول الزمني','Manage operational timeline'),
  ('periods.reopen','إعادة فتح الفترات','Reopen operational periods')
) as x(code,name_ar,name_en)
on conflict(code) do update set name_ar=excluded.name_ar,name_en=excluded.name_en;

insert into public.role_permissions(role_code,permission_code)
select r.role_code,p.code
from (values('owner'),('admin')) as r(role_code)
cross join public.permissions p
on conflict do nothing;

do $$ declare c record; begin
  if to_regprocedure('public.erp_seed_access_catalog(uuid)') is not null then
    for c in select id from public.companies where is_active loop
      perform public.erp_seed_access_catalog(c.id);
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Universal recycle bin: one source of truth and one deletion batch.
-- ---------------------------------------------------------------------------
alter table public.erp_universal_recycle_bin
  add column if not exists deletion_batch_id uuid,
  add column if not exists root_source_table text,
  add column if not exists root_record_id text,
  add column if not exists delete_reason text,
  add column if not exists relation_context jsonb not null default '{}'::jsonb;

create index if not exists erp_universal_recycle_batch_idx
  on public.erp_universal_recycle_bin(company_id,deletion_batch_id,deleted_at)
  where restored_at is null and purged_at is null;

create or replace function public.erp_capture_deleted_record()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_payload jsonb:=to_jsonb(old);
  v_company uuid;
  v_record_id text;
  v_batch uuid;
  v_setting text;
begin
  if current_setting('qualityline.recycle_purge',true)='on' then return old; end if;
  if tg_table_name in ('erp_universal_recycle_bin','erp_records') then return old; end if;

  begin
    v_company:=nullif(coalesce(v_payload->>'company_id',v_payload->>'companyId'),'')::uuid;
  exception when others then v_company:=null; end;
  v_record_id:=coalesce(v_payload->>'id',v_payload->>'record_id',v_payload->>'recordId');
  if nullif(btrim(coalesce(v_record_id,'')),'') is null then
    v_record_id:=md5(v_payload::text||clock_timestamp()::text);
  end if;

  v_setting:=nullif(current_setting('qualityline.deletion_batch_id',true),'');
  begin v_batch:=v_setting::uuid; exception when others then v_batch:=gen_random_uuid(); end;
  if v_batch is null then v_batch:=gen_random_uuid(); end if;

  insert into public.erp_universal_recycle_bin(
    company_id,source_table,record_id,payload,deletion_mode,deleted_at,deleted_by,
    deletion_batch_id,root_source_table,root_record_id,delete_reason,relation_context
  ) values(
    v_company,tg_table_name,v_record_id,v_payload,'hard',now(),auth.uid(),v_batch,
    nullif(current_setting('qualityline.deletion_root_table',true),''),
    nullif(current_setting('qualityline.deletion_root_id',true),''),
    nullif(current_setting('qualityline.deletion_reason',true),''),
    jsonb_build_object('triggerTable',tg_table_name,'triggerOperation',tg_op)
  );
  return old;
end;
$$;

create or replace function public.erp_capture_soft_deleted_record()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=to_jsonb(old);
  v_company uuid;
  v_record_id text;
  v_became_deleted boolean;
  v_batch uuid;
  v_setting text;
begin
  if tg_table_name in ('erp_universal_recycle_bin','erp_records') then return new; end if;
  v_became_deleted:=
    (coalesce((v_new->>'is_deleted')::boolean,(v_new->>'isDeleted')::boolean,false)
      and not coalesce((v_old->>'is_deleted')::boolean,(v_old->>'isDeleted')::boolean,false))
    or (coalesce(v_new->>'deleted_at',v_new->>'deletedAt') is not null
      and coalesce(v_old->>'deleted_at',v_old->>'deletedAt') is null);
  if not v_became_deleted then return new; end if;

  begin
    v_company:=nullif(coalesce(v_new->>'company_id',v_new->>'companyId'),'')::uuid;
  exception when others then v_company:=null; end;
  v_record_id:=coalesce(v_new->>'id',v_new->>'record_id',v_new->>'recordId');
  if nullif(btrim(coalesce(v_record_id,'')),'') is null then
    v_record_id:=md5(v_new::text||clock_timestamp()::text);
  end if;

  v_setting:=nullif(current_setting('qualityline.deletion_batch_id',true),'');
  begin v_batch:=v_setting::uuid; exception when others then v_batch:=gen_random_uuid(); end;
  if v_batch is null then v_batch:=gen_random_uuid(); end if;

  if not exists(
    select 1 from public.erp_universal_recycle_bin
    where source_table=tg_table_name and record_id=v_record_id
      and restored_at is null and purged_at is null
  ) then
    insert into public.erp_universal_recycle_bin(
      company_id,source_table,record_id,payload,deletion_mode,deleted_at,deleted_by,
      deletion_batch_id,root_source_table,root_record_id,delete_reason,relation_context
    ) values(
      v_company,tg_table_name,v_record_id,v_new,'soft',
      coalesce(nullif(coalesce(v_new->>'deleted_at',v_new->>'deletedAt'),'')::timestamptz,now()),
      auth.uid(),v_batch,
      nullif(current_setting('qualityline.deletion_root_table',true),''),
      nullif(current_setting('qualityline.deletion_root_id',true),''),
      nullif(current_setting('qualityline.deletion_reason',true),''),
      jsonb_build_object('triggerTable',tg_table_name,'triggerOperation',tg_op)
    );
  end if;
  return new;
end;
$$;

-- The return shape is intentionally richer; existing Flutter callers ignore
-- unknown fields while the new recycle-bin page shows them.
drop function if exists public.erp_recycle_bin_list(uuid,text,text);
create function public.erp_recycle_bin_list(
  p_company_id uuid,p_query text default '',p_entity_type text default ''
) returns table(
  entity_type text,record_id text,payload jsonb,deleted_at timestamptz,
  deleted_by text,source_table text,deletion_mode text,deletion_batch_id text,
  root_source_table text,root_record_id text,delete_reason text,related_count bigint
)
language sql stable security definer set search_path=public as $$
  with universal as (
    select u.source_table entity_type,u.record_id,u.payload,u.deleted_at,
      coalesce(u.deleted_by::text,'') deleted_by,u.source_table,u.deletion_mode,
      u.deletion_batch_id::text,u.root_source_table,u.root_record_id,u.delete_reason,
      case when u.deletion_batch_id is null then 1 else count(*) over(partition by u.deletion_batch_id) end related_count
    from public.erp_universal_recycle_bin u
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null and u.purged_at is null
  ), legacy as (
    select r.entity_type,r.record_id,r.payload,r.deleted_at,
      coalesce(r.payload->>'deletedByUserName',r.payload->>'deletedBy','') deleted_by,
      'erp_records'::text source_table,'soft'::text deletion_mode,null::text deletion_batch_id,
      null::text root_source_table,null::text root_record_id,
      coalesce(r.payload->>'deleteReason','') delete_reason,1::bigint related_count
    from public.erp_records r
    where r.company_id=p_company_id::text and r.deleted_at is not null
  ), all_rows as (
    select * from universal union all select * from legacy
  )
  select x.* from all_rows x
  where public.is_company_member(p_company_id)
    and public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.view')
    and (coalesce(btrim(p_entity_type),'')='' or x.entity_type=btrim(p_entity_type))
    and (coalesce(btrim(p_query),'')='' or x.record_id ilike '%'||btrim(p_query)||'%'
      or x.entity_type ilike '%'||btrim(p_query)||'%'
      or coalesce(x.root_record_id,'') ilike '%'||btrim(p_query)||'%'
      or x.payload::text ilike '%'||btrim(p_query)||'%')
  order by x.deleted_at desc;
$$;

create or replace function public.erp_recycle_bin_restore(
  p_company_id uuid,p_entity_type text,p_record_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_archive public.erp_universal_recycle_bin%rowtype;
  v_row public.erp_universal_recycle_bin%rowtype;
  v_batch uuid;
  v_pk text;
  v_setters text;
  v_columns text;
  v_select_columns text;
  v_restored int:=0;
  v_legacy int:=0;
  v_has_company_id boolean;
  v_has_company_camel boolean;
  v_commercial_module text;
  v_commercial_snapshot jsonb;
  v_link_result jsonb;
begin
  if not public.is_company_member(p_company_id) then raise exception 'access_denied'; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.restore') then
    raise exception 'restore_permission_required';
  end if;

  update public.erp_records
  set deleted_at=null,updated_at=now(),
      payload=(payload-'deletedAt'-'deleted_at'-'deletedBy'-'deletedByUserName'-'deleteReason')
        ||jsonb_build_object('isDeleted',false,'is_deleted',false,'restoredAt',now(),'restoredBy',auth.uid()::text)
  where company_id=p_company_id::text and entity_type=btrim(p_entity_type)
    and record_id=btrim(p_record_id) and deleted_at is not null;
  get diagnostics v_legacy=row_count;
  if v_legacy>0 then
    return jsonb_build_object('restored',true,'records',v_legacy,'batch',null);
  end if;

  select * into v_archive from public.erp_universal_recycle_bin
  where source_table=btrim(p_entity_type) and record_id=btrim(p_record_id)
    and (company_id=p_company_id or company_id is null)
    and restored_at is null and purged_at is null
  order by deleted_at desc limit 1 for update;
  if not found then raise exception 'deleted_record_not_found'; end if;
  v_batch:=v_archive.deletion_batch_id;
  v_commercial_module:=case coalesce(v_archive.root_source_table,v_archive.source_table)
    when 'erp_sales_orders_cloud' then 'sales'
    when 'erp_purchase_orders_cloud' then 'purchases'
    else null end;
  v_commercial_snapshot:=v_archive.relation_context->'commercialSnapshot';
  if v_commercial_module is not null and v_commercial_snapshot is null and v_batch is not null then
    select u.relation_context->'commercialSnapshot' into v_commercial_snapshot
    from public.erp_universal_recycle_bin u
    where u.deletion_batch_id=v_batch and u.relation_context ? 'commercialSnapshot'
    order by u.deleted_at desc limit 1;
  end if;

  for v_row in
    select * from public.erp_universal_recycle_bin
    where (id=v_archive.id or (v_batch is not null and deletion_batch_id=v_batch))
      and (company_id=p_company_id or company_id is null)
      and restored_at is null and purged_at is null
    order by case when deletion_mode='hard' then 0 else 1 end,deleted_at desc
    for update
  loop
    -- A commercial deletion is restored as a business transaction, not by
    -- re-enabling cancelled journals/documents. Restore only the order and its
    -- lines, then rebuild inventory, invoices, payments and journals from the
    -- captured snapshot below.
    if v_commercial_module is not null and v_commercial_snapshot is not null and
       v_row.source_table not in (
         case when v_commercial_module='sales' then 'erp_sales_orders_cloud' else 'erp_purchase_orders_cloud' end,
         case when v_commercial_module='sales' then 'erp_sales_order_items_cloud' else 'erp_purchase_order_items_cloud' end
       ) then
      update public.erp_universal_recycle_bin
      set restored_at=now(),restored_by=auth.uid() where id=v_row.id;
      v_restored:=v_restored+1;
      continue;
    end if;
    if to_regclass(format('public.%I',v_row.source_table)) is null then
      update public.erp_universal_recycle_bin
      set restored_at=now(),restored_by=auth.uid() where id=v_row.id;
      v_restored:=v_restored+1;
      continue;
    end if;
    select case
      when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='id') then 'id'
      when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='record_id') then 'record_id'
      else null end into v_pk;
    if v_pk is null then continue; end if;
    select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='company_id') into v_has_company_id;
    select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='companyId') into v_has_company_camel;

    if v_row.deletion_mode='hard' then
      begin
        select string_agg(format('%I',c.column_name),',' order by c.ordinal_position),
               string_agg(format('x.%I',c.column_name),',' order by c.ordinal_position)
          into v_columns,v_select_columns
        from information_schema.columns c
        where c.table_schema='public' and c.table_name=v_row.source_table
          and coalesce(c.is_generated,'NEVER')='NEVER'
          and coalesce(c.is_identity,'NO')='NO';
        if coalesce(v_columns,'')='' then raise exception 'restorable_columns_not_found'; end if;
        execute format(
          'insert into public.%1$I(%2$s) select %3$s from jsonb_populate_record(null::public.%1$I,$1) x on conflict do nothing',
          v_row.source_table,v_columns,v_select_columns
        ) using v_row.payload;
      exception when others then
        raise exception 'restore_failed_for_%: %',v_row.source_table,sqlerrm;
      end;
    else
      v_setters:='';
      if exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='is_deleted') then
        v_setters:=v_setters||case when v_setters='' then '' else ',' end||'is_deleted=false';
      end if;
      if exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='deleted_at') then
        v_setters:=v_setters||case when v_setters='' then '' else ',' end||'deleted_at=null';
      end if;
      if exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='updated_at') then
        v_setters:=v_setters||case when v_setters='' then '' else ',' end||'updated_at=now()';
      end if;
      if exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='updated_by') then
        v_setters:=v_setters||case when v_setters='' then '' else ',' end||'updated_by=auth.uid()';
      end if;
      if v_setters<>'' then
        if v_has_company_id then
          execute format('update public.%I set %s where %I::text=$1 and company_id::text=$2',v_row.source_table,v_setters,v_pk)
            using v_row.record_id,p_company_id::text;
        elsif v_has_company_camel then
          execute format('update public.%I set %s where %I::text=$1 and "companyId"::text=$2',v_row.source_table,v_setters,v_pk)
            using v_row.record_id,p_company_id::text;
        else
          execute format('update public.%I set %s where %I::text=$1',v_row.source_table,v_setters,v_pk)
            using v_row.record_id;
        end if;
      end if;
    end if;
    update public.erp_universal_recycle_bin
      set restored_at=now(),restored_by=auth.uid() where id=v_row.id;
    v_restored:=v_restored+1;
  end loop;

  if v_commercial_module is not null and v_commercial_snapshot is not null then
    v_link_result:=public.erp_phase2_restore_commercial_order_links(
      p_company_id,coalesce(v_archive.root_record_id,v_archive.record_id)::uuid,v_commercial_module,v_commercial_snapshot
    );
  end if;

  return jsonb_build_object(
    'restored',v_restored>0,'records',v_restored,'batch',v_batch,
    'commercialLinks',v_link_result
  );
end;
$$;

create or replace function public.erp_recycle_bin_purge(
  p_company_id uuid,p_entity_type text,p_record_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_archive public.erp_universal_recycle_bin%rowtype;
  v_row public.erp_universal_recycle_bin%rowtype;
  v_batch uuid;
  v_pk text;
  v_deleted int:=0;
  v_has_company_id boolean;
  v_has_company_camel boolean;
begin
  if not public.is_company_member(p_company_id) then raise exception 'access_denied'; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,'settings.recycle_bin.purge') then
    raise exception 'permanent_delete_permission_required';
  end if;

  perform set_config('qualityline.recycle_purge','on',true);
  delete from public.erp_records
  where company_id=p_company_id::text and entity_type=btrim(p_entity_type)
    and record_id=btrim(p_record_id) and deleted_at is not null;
  get diagnostics v_deleted=row_count;
  if v_deleted>0 then return jsonb_build_object('purged',true,'deletedRows',v_deleted); end if;

  select * into v_archive from public.erp_universal_recycle_bin
  where source_table=btrim(p_entity_type) and record_id=btrim(p_record_id)
    and (company_id=p_company_id or company_id is null)
    and restored_at is null and purged_at is null
  order by deleted_at desc limit 1 for update;
  if not found then raise exception 'deleted_record_not_found'; end if;
  v_batch:=v_archive.deletion_batch_id;

  for v_row in
    select * from public.erp_universal_recycle_bin
    where (id=v_archive.id or (v_batch is not null and deletion_batch_id=v_batch))
      and (company_id=p_company_id or company_id is null)
      and restored_at is null and purged_at is null
    order by deleted_at
    for update
  loop
    if to_regclass(format('public.%I',v_row.source_table)) is not null then
      select case
        when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='id') then 'id'
        when exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='record_id') then 'record_id'
        else null end into v_pk;
      if v_pk is not null then
        select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='company_id') into v_has_company_id;
        select exists(select 1 from information_schema.columns where table_schema='public' and table_name=v_row.source_table and column_name='companyId') into v_has_company_camel;
        if v_has_company_id then
          execute format('delete from public.%I where %I::text=$1 and company_id::text=$2',v_row.source_table,v_pk)
            using v_row.record_id,p_company_id::text;
        elsif v_has_company_camel then
          execute format('delete from public.%I where %I::text=$1 and "companyId"::text=$2',v_row.source_table,v_pk)
            using v_row.record_id,p_company_id::text;
        else
          execute format('delete from public.%I where %I::text=$1',v_row.source_table,v_pk)
            using v_row.record_id;
        end if;
      end if;
    end if;
    delete from public.erp_universal_recycle_bin where id=v_row.id;
    v_deleted:=v_deleted+1;
  end loop;
  return jsonb_build_object('purged',v_deleted>0,'deletedRows',v_deleted,'batch',v_batch);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Professional document numbering.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_document_sequences(
  company_id uuid not null,
  document_key text not null,
  fiscal_year integer not null,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(company_id,document_key,fiscal_year)
);
alter table public.erp_document_sequences enable row level security;
drop policy if exists erp_document_sequences_tenant on public.erp_document_sequences;
create policy erp_document_sequences_tenant on public.erp_document_sequences
for all using(public.erp_is_company_member(company_id))
with check(public.erp_is_company_member(company_id));

create or replace function public.erp_next_document_number(
  p_company_id uuid,p_document_key text,p_prefix text,p_effective_at timestamptz default now()
) returns text language plpgsql security definer set search_path=public as $$
declare v_year int:=extract(year from coalesce(p_effective_at,now()))::int; v_next bigint;
begin
  if auth.uid() is not null and not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  insert into public.erp_document_sequences(company_id,document_key,fiscal_year,last_number)
  values(p_company_id,lower(btrim(p_document_key)),v_year,1)
  on conflict(company_id,document_key,fiscal_year) do update
    set last_number=public.erp_document_sequences.last_number+1,updated_at=now()
  returning last_number into v_next;
  return upper(btrim(p_prefix))||'-'||v_year::text||'-'||lpad(v_next::text,6,'0');
end;
$$;

create or replace function public.erp_assign_professional_document_number()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_prefix text;
  v_key text;
  v_effective timestamptz;
  v_parent_effective timestamptz;
  v_expected_year text;
begin
  if tg_table_name='erp_sales_orders_cloud' then
    v_effective:=coalesce(new.effective_at,new.created_at,now());
    v_expected_year:=extract(year from v_effective)::int::text;
    if new.order_number is null
       or new.order_number !~ '^SO-[0-9]{4}-[0-9]{6}$'
       or split_part(new.order_number,'-',2)<>v_expected_year then
      new.order_number:=public.erp_next_document_number(
        new.company_id,'sales_order','SO',v_effective);
    end if;
  elsif tg_table_name='erp_purchase_orders_cloud' then
    v_effective:=coalesce(new.effective_at,new.created_at,now());
    v_expected_year:=extract(year from v_effective)::int::text;
    if new.order_number is null
       or new.order_number !~ '^PO-[0-9]{4}-[0-9]{6}$'
       or split_part(new.order_number,'-',2)<>v_expected_year then
      new.order_number:=public.erp_next_document_number(
        new.company_id,'purchase_order','PO',v_effective);
    end if;
  elsif tg_table_name='erp_commercial_workflow_documents' then
    if tg_op='INSERT' then
      if new.module='sales' then
        select effective_at into v_parent_effective
        from public.erp_sales_orders_cloud
        where company_id=new.company_id and id=new.parent_id;
      elsif new.module='purchases' then
        select effective_at into v_parent_effective
        from public.erp_purchase_orders_cloud
        where company_id=new.company_id and id=new.parent_id;
      end if;
    end if;
    new.effective_at:=coalesce(v_parent_effective,new.effective_at,new.created_at,now());
    v_effective:=new.effective_at;
    v_expected_year:=extract(year from v_effective)::int::text;
    v_key:=lower(new.module||'_'||new.document_type);
    v_prefix:=case
      when new.module='sales' and new.document_type='delivery' then 'SDN'
      when new.module='purchases' and new.document_type='receipt' then 'GRN'
      when new.module='sales' and new.document_type='invoice' then 'SINV'
      when new.module='purchases' and new.document_type='invoice' then 'PINV'
      when new.module='maintenance' and new.document_type in ('issue','delivery') then 'MIS'
      when new.module='maintenance' and new.document_type='invoice' then 'MINV'
      else upper(left(new.module,2)||left(new.document_type,2)) end;
    if new.document_number is null
       or new.document_number !~ '^[A-Z]+-[0-9]{4}-[0-9]{6}$'
       or split_part(new.document_number,'-',2)<>v_expected_year then
      new.document_number:=public.erp_next_document_number(
        new.company_id,v_key,v_prefix,v_effective);
    end if;
  elsif tg_table_name='erp_maintenance_orders' then
    v_effective:=coalesce(new.maintenance_date,new.created_at,now());
    v_expected_year:=extract(year from v_effective)::int::text;
    if new.order_number is null
       or new.order_number !~ '^MO-[0-9]{4}-[0-9]{6}$'
       or split_part(new.order_number,'-',2)<>v_expected_year then
      new.order_number:=public.erp_next_document_number(
        new.company_id,'maintenance_order','MO',v_effective);
    end if;
    if new.stock_issue_number is not null and (
       new.stock_issue_number !~ '^MIS-[0-9]{4}-[0-9]{6}$'
       or split_part(new.stock_issue_number,'-',2)<>v_expected_year) then
      new.stock_issue_number:=public.erp_next_document_number(
        new.company_id,'maintenance_stock_issue','MIS',v_effective);
    end if;
    if new.invoice_number is not null and (
       new.invoice_number !~ '^MINV-[0-9]{4}-[0-9]{6}$'
       or split_part(new.invoice_number,'-',2)<>v_expected_year) then
      new.invoice_number:=public.erp_next_document_number(
        new.company_id,'maintenance_invoice','MINV',v_effective);
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Operational timeline and effective dates.
-- ---------------------------------------------------------------------------
alter table public.erp_sales_orders_cloud add column if not exists effective_at timestamptz;
alter table public.erp_purchase_orders_cloud add column if not exists effective_at timestamptz;
alter table public.erp_commercial_workflow_documents add column if not exists effective_at timestamptz;
update public.erp_sales_orders_cloud set effective_at=created_at where effective_at is null;
update public.erp_purchase_orders_cloud set effective_at=created_at where effective_at is null;
update public.erp_commercial_workflow_documents set effective_at=created_at where effective_at is null;
alter table public.erp_sales_orders_cloud alter column effective_at set default now();
alter table public.erp_purchase_orders_cloud alter column effective_at set default now();
alter table public.erp_commercial_workflow_documents alter column effective_at set default now();

create table if not exists public.erp_operational_periods(
  id uuid primary key default gen_random_uuid(),company_id uuid not null,
  module text not null default 'all',period_name text not null,
  starts_at timestamptz not null,ends_at timestamptz not null,
  status text not null default 'open' check(status in ('open','closed')),
  notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),updated_by uuid default auth.uid(),
  is_deleted boolean not null default false,deleted_at timestamptz,
  check(ends_at>=starts_at)
);
create index if not exists erp_operational_periods_lookup_idx
  on public.erp_operational_periods(company_id,module,starts_at,ends_at) where not is_deleted;
alter table public.erp_operational_periods enable row level security;
drop policy if exists erp_operational_periods_tenant on public.erp_operational_periods;
create policy erp_operational_periods_tenant on public.erp_operational_periods
for all using(public.erp_is_company_member(company_id)) with check(public.erp_is_company_member(company_id));

create or replace function public.erp_validate_operational_date(
  p_company_id uuid,p_module text,p_effective_at timestamptz
) returns void language plpgsql stable security definer set search_path=public as $$
begin
  if p_effective_at is null then raise exception 'effective_date_required'; end if;
  if exists(select 1 from public.erp_operational_periods
    where company_id=p_company_id and not is_deleted and module in ('all',lower(p_module)))
    and not exists(select 1 from public.erp_operational_periods
      where company_id=p_company_id and not is_deleted and status='open'
        and module in ('all',lower(p_module)) and p_effective_at between starts_at and ends_at) then
    raise exception 'التاريخ التشغيلي خارج الفترات المفتوحة';
  end if;
end;
$$;

create or replace function public.erp_list_operational_periods(p_company_id uuid)
returns table(id uuid,module text,period_name text,starts_at timestamptz,ends_at timestamptz,status text,notes text)
language sql stable security definer set search_path=public as $$
  select p.id,p.module,p.period_name,p.starts_at,p.ends_at,p.status,p.notes
  from public.erp_operational_periods p
  where p.company_id=p_company_id and not p.is_deleted
    and public.erp_cloud_user_has_permission(p_company_id,'periods.view')
  order by p.starts_at desc,p.period_name;
$$;

create or replace function public.erp_save_operational_period(
  p_company_id uuid,p_period_id uuid,p_module text,p_period_name text,
  p_starts_at timestamptz,p_ends_at timestamptz,p_status text,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=coalesce(p_period_id,gen_random_uuid());v_module text:=lower(btrim(coalesce(p_module,'all')));v_status text:=lower(btrim(coalesce(p_status,'open')));
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['periods.close','periods.reopen']);
  if exists(select 1 from public.erp_operational_periods where id=v_id and company_id<>p_company_id) then
    raise exception 'access_denied';
  end if;
  if btrim(coalesce(p_period_name,''))='' then raise exception 'اسم الفترة مطلوب'; end if;
  if v_module not in ('all','sales','purchases','accounting','inventory','maintenance') then raise exception 'وحدة الفترة غير صحيحة'; end if;
  if v_status not in ('open','closed') then raise exception 'حالة الفترة غير صحيحة'; end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at<p_starts_at then raise exception 'نطاق الفترة الزمنية غير صحيح'; end if;
  if exists(select 1 from public.erp_operational_periods p where p.company_id=p_company_id and p.id<>v_id and not p.is_deleted
    and (p.module='all' or v_module='all' or p.module=v_module) and tstzrange(p.starts_at,p.ends_at,'[]') && tstzrange(p_starts_at,p_ends_at,'[]')) then
    raise exception 'توجد فترة زمنية متداخلة لنفس الوحدة';
  end if;
  insert into public.erp_operational_periods(id,company_id,module,period_name,starts_at,ends_at,status,notes,created_by,updated_by)
  values(v_id,p_company_id,v_module,btrim(p_period_name),p_starts_at,p_ends_at,v_status,nullif(btrim(coalesce(p_notes,'')),''),auth.uid(),auth.uid())
  on conflict(id) do update set module=excluded.module,period_name=excluded.period_name,starts_at=excluded.starts_at,
    ends_at=excluded.ends_at,status=excluded.status,notes=excluded.notes,updated_at=now(),updated_by=auth.uid(),is_deleted=false,deleted_at=null
  where public.erp_operational_periods.company_id=p_company_id;
  return v_id;
end;
$$;

create or replace function public.erp_delete_operational_period(p_company_id uuid,p_period_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['periods.close']);
  update public.erp_operational_periods set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_period_id and not is_deleted;
end;
$$;

create or replace function public.erp_set_operational_effective_at(
  p_company_id uuid,p_module text,p_record_type text,p_record_id uuid,p_effective_at timestamptz
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_module text:=lower(btrim(p_module)); v_updated int:=0;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_module||'.update')
     and not public.erp_cloud_user_has_permission(p_company_id,v_module||'.create') then
    raise exception 'operation_permission_required';
  end if;
  perform public.erp_validate_operational_date(p_company_id,v_module,p_effective_at);
  if lower(coalesce(p_record_type,'order'))='document' then
    update public.erp_commercial_workflow_documents set effective_at=p_effective_at,updated_at=now()
    where company_id=p_company_id and id=p_record_id and module=v_module and not is_deleted;
    get diagnostics v_updated=row_count;
  elsif v_module='sales' then
    update public.erp_sales_orders_cloud set effective_at=p_effective_at,updated_at=now()
    where company_id=p_company_id and id=p_record_id and not is_deleted;
    get diagnostics v_updated=row_count;
    update public.erp_commercial_workflow_documents set effective_at=p_effective_at,updated_at=now()
    where company_id=p_company_id and parent_id=p_record_id and module='sales' and not is_deleted;
  elsif v_module='purchases' then
    update public.erp_purchase_orders_cloud set effective_at=p_effective_at,updated_at=now()
    where company_id=p_company_id and id=p_record_id and not is_deleted;
    get diagnostics v_updated=row_count;
    update public.erp_commercial_workflow_documents set effective_at=p_effective_at,updated_at=now()
    where company_id=p_company_id and parent_id=p_record_id and module='purchases' and not is_deleted;
  else raise exception 'unsupported_operational_module'; end if;
  if v_updated=0 then raise exception 'operational_record_not_found'; end if;

  update public.erp_journal_entries j
  set data=j.data||jsonb_build_object('entryDate',p_effective_at,'effectiveAt',p_effective_at),
      updated_at=now(),updated_by=auth.uid()
  where j.company_id=p_company_id and not j.is_deleted and (
    j.data->>'orderId'=p_record_id::text or j.data->>'referenceId'=p_record_id::text or
    j.data->>'referenceId' in (select d.id::text from public.erp_commercial_workflow_documents d
      where d.company_id=p_company_id and d.parent_id=p_record_id and d.module=v_module)
  );
  update public.erp_inventory_movements m
  set data=m.data||jsonb_build_object('movementDate',p_effective_at,'effectiveAt',p_effective_at),
      updated_at=now(),updated_by=auth.uid()
  where m.company_id=p_company_id and not m.is_deleted and m.data->>'referenceId' in (
    select d.id::text from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.parent_id=p_record_id and d.module=v_module
  );
  return jsonb_build_object('updated',true,'effectiveAt',p_effective_at,'module',v_module);
end;
$$;

create or replace function public.erp_get_cloud_sales_order_draft(p_company_id uuid,p_order_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'order',jsonb_build_object('id',o.id::text,'customerId',o.customer_id,'currency',o.currency,
    'exchangeRate',o.exchange_rate,'discount',o.discount,'notes',o.notes,'status',o.status,
    'orderNumber',o.order_number,'effectiveAt',o.effective_at),
  'items',coalesce((select jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,
    'description',x.description,'quantity',x.quantity,'unitPrice',x.unit_price) order by x.id)
    from public.erp_sales_order_items_cloud x where x.company_id=o.company_id and x.order_id=o.id and not x.is_deleted),'[]'::jsonb)
 ) from public.erp_sales_orders_cloud o
 where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
   and public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_get_cloud_purchase_order_draft(p_company_id uuid,p_order_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object(
  'order',jsonb_build_object('id',o.id::text,'supplierId',o.supplier_id,'currency',o.currency,
    'exchangeRate',o.exchange_rate,'discount',o.discount,'notes',o.notes,'status',o.status,
    'orderNumber',o.order_number,'effectiveAt',o.effective_at),
  'items',coalesce((select jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,
    'description',x.description,'quantity',x.quantity,'unitCost',x.unit_cost) order by x.id)
    from public.erp_purchase_order_items_cloud x where x.company_id=o.company_id and x.order_id=o.id and not x.is_deleted),'[]'::jsonb)
 ) from public.erp_purchase_orders_cloud o
 where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
   and public.erp_is_company_member(p_company_id);
$$;

-- Recreate numbering triggers only after effective_at exists.
drop trigger if exists erp_professional_sales_order_number on public.erp_sales_orders_cloud;
create trigger erp_professional_sales_order_number before insert or update of effective_at on public.erp_sales_orders_cloud
for each row execute function public.erp_assign_professional_document_number();
drop trigger if exists erp_professional_purchase_order_number on public.erp_purchase_orders_cloud;
create trigger erp_professional_purchase_order_number before insert or update of effective_at on public.erp_purchase_orders_cloud
for each row execute function public.erp_assign_professional_document_number();
drop trigger if exists erp_professional_workflow_document_number on public.erp_commercial_workflow_documents;
create trigger erp_professional_workflow_document_number before insert or update of effective_at on public.erp_commercial_workflow_documents
for each row execute function public.erp_assign_professional_document_number();
drop trigger if exists erp_professional_maintenance_number on public.erp_maintenance_orders;
create trigger erp_professional_maintenance_number before insert or update of maintenance_date,stock_issue_number,invoice_number on public.erp_maintenance_orders
for each row execute function public.erp_assign_professional_document_number();

-- Normalize active legacy numbers once; references use UUIDs and the existing
-- opportunity synchronization trigger follows sales-order number changes.
update public.erp_sales_orders_cloud
set effective_at=effective_at
where not is_deleted and (
  order_number !~ '^SO-[0-9]{4}-[0-9]{6}$'
  or split_part(order_number,'-',2)<>extract(year from effective_at)::int::text
);
update public.erp_purchase_orders_cloud
set effective_at=effective_at
where not is_deleted and (
  order_number !~ '^PO-[0-9]{4}-[0-9]{6}$'
  or split_part(order_number,'-',2)<>extract(year from effective_at)::int::text
);
update public.erp_commercial_workflow_documents
set effective_at=effective_at
where not is_deleted and (
  document_number !~ '^[A-Z]+-[0-9]{4}-[0-9]{6}$'
  or split_part(document_number,'-',2)<>extract(year from effective_at)::int::text
);
update public.erp_maintenance_orders
set maintenance_date=maintenance_date
where not is_deleted and (
  order_number !~ '^MO-[0-9]{4}-[0-9]{6}$'
  or split_part(order_number,'-',2)<>extract(year from maintenance_date)::int::text
  or (stock_issue_number is not null and stock_issue_number !~ '^MIS-[0-9]{4}-[0-9]{6}$')
  or (invoice_number is not null and invoice_number !~ '^MINV-[0-9]{4}-[0-9]{6}$')
);

-- ---------------------------------------------------------------------------
-- 4. Automatic chart-of-accounts coding from the selected parent.
-- ---------------------------------------------------------------------------
create or replace function public.erp_next_child_account_code(
  p_company_id uuid,p_parent_id text,p_account_type text
) returns text language plpgsql security definer set search_path=public as $$
declare
  v_parent_code text;
  v_prefix text;
  v_seq int:=0;
  v_candidate text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  perform pg_advisory_xact_lock(hashtext(p_company_id::text||':'||coalesce(p_parent_id,p_account_type,'')));
  if nullif(btrim(coalesce(p_parent_id,'')),'') is not null then
    select code into v_parent_code from public.erp_accounts
    where organization_id=p_company_id and account_id=p_parent_id and is_active;
    if v_parent_code is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    loop
      v_seq:=v_seq+1;
      v_candidate:=v_parent_code||'.'||lpad(v_seq::text,2,'0');
      exit when not exists(select 1 from public.erp_accounts
        where organization_id=p_company_id and lower(code)=lower(v_candidate));
    end loop;
    return v_candidate;
  end if;
  v_prefix:=case lower(btrim(p_account_type))
    when 'asset' then '1' when 'liability' then '2' when 'equity' then '3'
    when 'revenue' then '4' when 'expense' then '5' else null end;
  if v_prefix is null then raise exception 'نوع الحساب غير صحيح'; end if;
  loop
    v_candidate:=v_prefix||lpad(v_seq::text,3,'0');
    exit when not exists(select 1 from public.erp_accounts
      where organization_id=p_company_id and lower(code)=lower(v_candidate));
    v_seq:=v_seq+1;
  end loop;
  return v_candidate;
end;
$$;

create or replace function public.erp_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=btrim(coalesce(p_account->>'id',''));
  v_parent text:=nullif(btrim(coalesce(p_account->>'parentId',p_account->>'parent_id','')),'');
  v_code text:=btrim(coalesce(p_account->>'code',''));
  v_name text:=btrim(coalesce(p_account->>'name',''));
  v_currency text:=upper(coalesce(nullif(btrim(p_account->>'currency'),''),'USD'));
  v_type text:=lower(btrim(coalesce(p_account->>'type',p_account->>'account_type','')));
  v_parent_currency text;
  v_parent_type text;
  v_existing public.erp_accounts%rowtype;
  v_active boolean:=public.erp_try_boolean(coalesce(p_account->>'isActive',p_account->>'is_active'),'true');
  v_opening numeric:=public.erp_try_numeric(coalesce(p_account->>'openingBalance',p_account->>'opening_balance'),0);
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_id='' or v_name='' then raise exception 'بيانات الحساب غير مكتملة'; end if;
  if v_type not in ('asset','liability','equity','revenue','expense') then raise exception 'نوع الحساب غير صحيح'; end if;
  if v_currency not in ('USD','IQD','MULTI') then raise exception 'عملة الحساب غير صحيحة'; end if;

  select * into v_existing from public.erp_accounts
  where organization_id=p_company_id and account_id=v_id for update;
  if p_require_existing and not found then raise exception 'الحساب غير موجود'; end if;
  if v_existing.account_id is not null and v_code='' then v_code:=v_existing.code; end if;
  if v_existing.account_id is null then
    -- New account codes are always assigned by the database from the selected parent.
    v_code:=public.erp_next_child_account_code(p_company_id,v_parent,v_type);
  end if;

  if not v_active and exists(select 1 from public.erp_accounts
    where organization_id=p_company_id and parent_account_id=v_id and is_active) then
    raise exception 'لا يمكن تعطيل حساب يحتوي على حسابات فرعية فعالة';
  end if;
  if v_existing.account_id is not null and
     (upper(v_existing.currency)<>v_currency or v_existing.account_type<>v_type) and exists(
       select 1 from public.erp_journal_lines where company_id=p_company_id and not is_deleted and data->>'accountId'=v_id
     ) then raise exception 'لا يمكن تغيير نوع أو عملة حساب مرتبط بقيود'; end if;
  if exists(select 1 from public.erp_accounts
    where organization_id=p_company_id and lower(code)=lower(v_code)
      and account_id<>v_id and is_active) then raise exception 'رمز الحساب مستخدم مسبقًا'; end if;

  if v_parent=v_id then raise exception 'لا يمكن جعل الحساب أباً لنفسه'; end if;
  if v_parent is not null then
    select upper(currency),account_type into v_parent_currency,v_parent_type
    from public.erp_accounts where organization_id=p_company_id and account_id=v_parent and is_active;
    if v_parent_currency is null then raise exception 'الحساب الأب غير موجود أو غير فعال'; end if;
    if v_parent_type<>v_type then raise exception 'نوع الحساب الفرعي يجب أن يطابق نوع الحساب الأب'; end if;
    if exists(select 1 from public.erp_journal_lines
      where company_id=p_company_id and not is_deleted and data->>'accountId'=v_parent) then
      raise exception 'لا يمكن إضافة حساب فرعي تحت حساب مستخدم في قيود؛ أنشئ حساباً تجميعياً';
    end if;
    if exists(
      with recursive descendants as (
        select account_id from public.erp_accounts where organization_id=p_company_id and parent_account_id=v_id
        union all select a.account_id from public.erp_accounts a join descendants d on a.parent_account_id=d.account_id
        where a.organization_id=p_company_id
      ) select 1 from descendants where account_id=v_parent
    ) then raise exception 'لا يمكن نقل الحساب تحت أحد حساباته الفرعية'; end if;
  end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,currency,
    opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values(
    p_company_id,v_id,v_code,v_name,v_type,v_parent,v_currency,v_opening,v_active,now(),now(),auth.uid()
  ) on conflict(organization_id,account_id) do update set
    code=excluded.code,name=excluded.name,account_type=excluded.account_type,
    parent_account_id=excluded.parent_account_id,currency=excluded.currency,
    opening_balance=excluded.opening_balance,is_active=excluded.is_active,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. FIFO inventory cost layers and consumption detail.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_inventory_cost_layers(
  id uuid primary key default gen_random_uuid(),company_id uuid not null,
  item_type text not null check(item_type in ('product','car')),item_id text not null,
  warehouse_id text not null,receipt_id uuid,purchase_order_id uuid,source_line_id uuid,
  layer_number text not null,effective_at timestamptz not null,
  original_quantity numeric(20,4) not null check(original_quantity>0),
  remaining_quantity numeric(20,4) not null check(remaining_quantity>=0),
  unit_cost numeric(20,6) not null check(unit_cost>=0),currency text not null,
  asset_account_id text,cost_expense_account_id text,
  source_type text not null default 'purchase_receipt',status text not null default 'active'
    check(status in ('active','consumed','reversed')),
  created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
  created_by uuid default auth.uid(),updated_by uuid default auth.uid(),
  unique(company_id,receipt_id,item_type,item_id,warehouse_id)
);
create index if not exists erp_fifo_layers_available_idx
  on public.erp_inventory_cost_layers(company_id,item_type,item_id,warehouse_id,effective_at,created_at)
  where status in ('active','consumed') and remaining_quantity>0;

create table if not exists public.erp_inventory_fifo_consumptions(
  id uuid primary key default gen_random_uuid(),company_id uuid not null,
  delivery_id uuid not null,sales_order_id uuid not null,layer_id uuid not null references public.erp_inventory_cost_layers(id),
  item_type text not null,item_id text not null,warehouse_id text not null,
  quantity numeric(20,4) not null check(quantity>0),unit_cost numeric(20,6) not null,
  total_cost numeric(20,6) generated always as (quantity*unit_cost) stored,
  effective_at timestamptz not null,journal_entry_id text,status text not null default 'active'
    check(status in ('active','reversed')),
  created_at timestamptz not null default now(),reversed_at timestamptz,
  unique(company_id,delivery_id,layer_id)
);
create index if not exists erp_fifo_consumptions_delivery_idx
  on public.erp_inventory_fifo_consumptions(company_id,delivery_id,status);

alter table public.erp_inventory_cost_layers enable row level security;
alter table public.erp_inventory_fifo_consumptions enable row level security;
drop policy if exists erp_fifo_layers_tenant on public.erp_inventory_cost_layers;
create policy erp_fifo_layers_tenant on public.erp_inventory_cost_layers for all
using(public.erp_is_company_member(company_id)) with check(public.erp_is_company_member(company_id));
drop policy if exists erp_fifo_consumptions_tenant on public.erp_inventory_fifo_consumptions;
create policy erp_fifo_consumptions_tenant on public.erp_inventory_fifo_consumptions for all
using(public.erp_is_company_member(company_id)) with check(public.erp_is_company_member(company_id));

create or replace function public.erp_phase2_insert_journal_at(
  p_company_id uuid,p_reference_type text,p_reference_id text,p_number text,
  p_description text,p_currency text,p_lines jsonb,p_effective_at timestamptz
) returns text language plpgsql security definer set search_path=public as $$
declare eid text:=gen_random_uuid()::text; l jsonb; td numeric; tc numeric;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform public.erp_validate_operational_date(p_company_id,split_part(p_reference_type,'_',1),p_effective_at);
  select coalesce(sum(public.erp_try_numeric(value->>'debit',0)),0),
         coalesce(sum(public.erp_try_numeric(value->>'credit',0)),0)
    into td,tc from jsonb_array_elements(p_lines);
  if td<=0 or abs(td-tc)>0.01 then raise exception 'القيد غير متوازن'; end if;
  perform public.erp_phase2_void_reference_journals(p_company_id,p_reference_type,p_reference_id);
  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by) values(
    p_company_id,eid,jsonb_build_object('id',eid,'entryNumber',p_number,'entryDate',p_effective_at,
      'effectiveAt',p_effective_at,'description',p_description,'currency',upper(p_currency),
      'referenceType',p_reference_type,'referenceId',p_reference_id,'status','posted',
      'totalDebit',td,'totalCredit',tc,'createdAt',now()),auth.uid(),auth.uid());
  for l in select value from jsonb_array_elements(p_lines) loop
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by)
    values(p_company_id,gen_random_uuid()::text,l||jsonb_build_object('entryId',eid),auth.uid(),auth.uid());
  end loop;
  return eid;
end;
$$;

create or replace function public.erp_fifo_register_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_order public.erp_purchase_orders_cloud%rowtype;
  v_allocations jsonb;a record;v_line record;v_accounts jsonb;v_effective timestamptz;v_count int:=0;
begin
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_receipt_id and module='purchases'
    and document_type='receipt' and not is_deleted for update;
  if not found or v_doc.status<>'approved' then raise exception 'يجب تصديق إشعار الاستلام المخزني أولاً'; end if;
  select * into v_order from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
  if not found then raise exception 'أمر الشراء المرتبط غير موجود'; end if;
  v_effective:=coalesce(v_doc.effective_at,v_order.effective_at,v_doc.created_at,now());
  perform public.erp_validate_operational_date(p_company_id,'purchases',v_effective);
  v_allocations:=v_doc.payload->'allocations';
  if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
    select coalesce(jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,
      'description',x.description,'warehouseId',v_doc.warehouse_id,'quantity',x.quantity) order by x.id),'[]'::jsonb)
    into v_allocations from public.erp_purchase_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
  end if;
  for a in
    select x."itemType",x."itemId",max(x."description") as "description",
      x."warehouseId",sum(x.quantity) as quantity
    from jsonb_to_recordset(v_allocations) as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    select x.id,x.unit_cost into v_line from public.erp_purchase_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=v_order.id and not x.is_deleted
      and x.item_type=a."itemType" and x.item_id=a."itemId" limit 1;
    if v_line.id is null then raise exception 'بند الشراء غير موجود للوجبة %',a."description"; end if;
    v_accounts:=public.erp_phase2_item_accounts(p_company_id,a."itemType",a."itemId",v_order.currency);
    insert into public.erp_inventory_cost_layers(
      company_id,item_type,item_id,warehouse_id,receipt_id,purchase_order_id,source_line_id,
      layer_number,effective_at,original_quantity,remaining_quantity,unit_cost,currency,
      asset_account_id,cost_expense_account_id,source_type
    ) values(
      p_company_id,a."itemType",a."itemId",a."warehouseId",p_receipt_id,v_order.id,v_line.id,
      v_doc.document_number||'-'||lpad((v_count+1)::text,3,'0'),v_effective,a.quantity,a.quantity,
      v_line.unit_cost,v_order.currency,v_accounts->>'assetAccountId',v_accounts->>'costExpenseAccountId','purchase_receipt'
    ) on conflict(company_id,receipt_id,item_type,item_id,warehouse_id) do nothing;
    v_count:=v_count+1;
  end loop;
  update public.erp_commercial_workflow_documents set
    payload=payload||jsonb_build_object('fifoLayersRegisteredAt',now(),'costMethod','FIFO','effectiveAt',v_effective),
    effective_at=v_effective,updated_at=now() where id=p_receipt_id;
  return jsonb_build_object('registered',v_count,'effectiveAt',v_effective);
end;
$$;

create or replace function public.erp_fifo_prepare_opening_layers(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;v_order public.erp_sales_orders_cloud%rowtype;
  v_allocations jsonb;a record;v_stock public.erp_warehouse_stock%rowtype;
  v_stock_qty numeric;v_layer_qty numeric;v_cost numeric;v_accounts jsonb;v_effective timestamptz;
begin
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_delivery_id and module='sales' and document_type='delivery' and not is_deleted for update;
  if not found then raise exception 'إذن التجهيز المخزني غير موجود'; end if;
  select * into v_order from public.erp_sales_orders_cloud where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
  v_effective:=coalesce(v_doc.effective_at,v_order.effective_at,v_doc.created_at,now());
  v_allocations:=v_doc.payload->'allocations';
  if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
    select coalesce(jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,
      'description',x.description,'warehouseId',v_doc.warehouse_id,'quantity',x.quantity) order by x.id),'[]'::jsonb)
    into v_allocations from public.erp_sales_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
  end if;
  for a in
    select x."itemType",x."itemId",max(x."description") as "description",
      x."warehouseId",sum(x.quantity) as quantity
    from jsonb_to_recordset(v_allocations) as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    select coalesce(sum(remaining_quantity),0) into v_layer_qty from public.erp_inventory_cost_layers
    where company_id=p_company_id and item_type=a."itemType" and item_id=a."itemId"
      and warehouse_id=a."warehouseId" and status in ('active','consumed');
    if a."itemType"='product' then
      v_stock:=public.erp_inventory_ensure_stock(p_company_id,a."warehouseId",a."itemId");
      v_stock_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
      v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',
        public.erp_try_numeric(v_stock.data->>'unitCost',0));
    else
      v_stock_qty:=case when exists(select 1 from public.erp_cars c where c.company_id=p_company_id
        and c.id=a."itemId" and not c.is_deleted and coalesce(c.data->>'warehouseId',c.data->>'warehouse_id')=a."warehouseId") then 1 else 0 end;
      select coalesce(public.erp_try_numeric(c.data->>'purchasePrice',null),public.erp_try_numeric(c.data->>'costPrice',0),0)
        into v_cost from public.erp_cars c where c.company_id=p_company_id and c.id=a."itemId";
    end if;
    if v_stock_qty>v_layer_qty then
      v_accounts:=public.erp_phase2_item_accounts(p_company_id,a."itemType",a."itemId",v_order.currency);
      insert into public.erp_inventory_cost_layers(
        company_id,item_type,item_id,warehouse_id,layer_number,effective_at,
        original_quantity,remaining_quantity,unit_cost,currency,asset_account_id,
        cost_expense_account_id,source_type
      ) values(
        p_company_id,a."itemType",a."itemId",a."warehouseId",'OPEN-'||a."itemId"||'-'||to_char(now(),'YYYYMMDDHH24MISSMS'),
        least(v_effective,coalesce(v_order.created_at,v_effective)),v_stock_qty-v_layer_qty,v_stock_qty-v_layer_qty,
        coalesce(v_cost,0),v_order.currency,v_accounts->>'assetAccountId',v_accounts->>'costExpenseAccountId','opening_balance'
      );
    end if;
  end loop;
end;
$$;

create or replace function public.erp_fifo_apply_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns text language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_order public.erp_sales_orders_cloud%rowtype;
  v_allocations jsonb;
  a record;v_layer public.erp_inventory_cost_layers%rowtype;
  v_needed numeric;v_take numeric;v_amount numeric;v_total numeric:=0;
  v_lines jsonb:='[]'::jsonb;v_breakdown jsonb:='[]'::jsonb;
  v_effective timestamptz;v_entry text;v_old_entry text;v_existing text;
begin
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_delivery_id and module='sales'
    and document_type='delivery' and not is_deleted for update;
  if not found or v_doc.status<>'approved' then raise exception 'يجب تصديق إذن التجهيز المخزني أولاً'; end if;
  select * into v_order from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=v_doc.parent_id and not is_deleted;
  if not found then raise exception 'أمر البيع المرتبط غير موجود'; end if;
  v_existing:=nullif(v_doc.payload->>'fifoCostJournalEntryId','');
  if v_existing is not null and exists(select 1 from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and delivery_id=p_delivery_id and status='active') then
    return v_existing;
  end if;

  v_effective:=coalesce(v_doc.effective_at,v_order.effective_at,v_doc.created_at,now());
  perform public.erp_validate_operational_date(p_company_id,'sales',v_effective);
  v_allocations:=v_doc.payload->'allocations';
  if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
    select coalesce(jsonb_agg(jsonb_build_object('itemType',x.item_type,'itemId',x.item_id,
      'description',x.description,'warehouseId',v_doc.warehouse_id,'quantity',x.quantity) order by x.id),'[]'::jsonb)
    into v_allocations from public.erp_sales_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
  end if;

  for a in
    select x."itemType",x."itemId",max(x."description") as "description",
      x."warehouseId",sum(x.quantity) as quantity
    from jsonb_to_recordset(v_allocations) as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    v_needed:=a.quantity;
    for v_layer in
      select * from public.erp_inventory_cost_layers l
      where l.company_id=p_company_id and l.item_type=a."itemType" and l.item_id=a."itemId"
        and l.warehouse_id=a."warehouseId" and l.status in ('active','consumed')
        and l.remaining_quantity>0 and l.effective_at<=v_effective
      order by l.effective_at,l.created_at,l.id for update
    loop
      exit when v_needed<=0;
      v_take:=least(v_needed,v_layer.remaining_quantity);
      v_amount:=round(v_take*v_layer.unit_cost,6);
      update public.erp_inventory_cost_layers set
        remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid() where id=v_layer.id;
      insert into public.erp_inventory_fifo_consumptions(
        company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,warehouse_id,
        quantity,unit_cost,effective_at,status
      ) values(
        p_company_id,p_delivery_id,v_order.id,v_layer.id,a."itemType",a."itemId",a."warehouseId",
        v_take,v_layer.unit_cost,v_effective,'active'
      ) on conflict(company_id,delivery_id,layer_id) do update set
        quantity=excluded.quantity,unit_cost=excluded.unit_cost,effective_at=excluded.effective_at,status='active',reversed_at=null;
      v_lines:=v_lines||jsonb_build_array(
        jsonb_build_object('accountId',v_layer.cost_expense_account_id,'debit',v_amount,'credit',0,
          'description','تكلفة بيع '||a."description"||' من الوجبة '||v_layer.layer_number,
          'itemType',a."itemType",'itemId',a."itemId",'warehouseId',a."warehouseId",
          'layerId',v_layer.id,'layerNumber',v_layer.layer_number,'quantity',v_take,'unitCost',v_layer.unit_cost),
        jsonb_build_object('accountId',v_layer.asset_account_id,'debit',0,'credit',v_amount,
          'description','إخراج مخزون '||a."description"||' من الوجبة '||v_layer.layer_number,
          'itemType',a."itemType",'itemId',a."itemId",'warehouseId',a."warehouseId",
          'layerId',v_layer.id,'layerNumber',v_layer.layer_number,'quantity',v_take,'unitCost',v_layer.unit_cost)
      );
      v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object(
        'itemType',a."itemType",'itemId',a."itemId",'description',a."description",
        'warehouseId',a."warehouseId",'layerId',v_layer.id,'layerNumber',v_layer.layer_number,
        'quantity',v_take,'unitCost',v_layer.unit_cost,'totalCost',v_amount,'effectiveAt',v_layer.effective_at));
      v_total:=v_total+v_amount;
      v_needed:=v_needed-v_take;
    end loop;
    if v_needed>0 then
      raise exception 'لا توجد وجبات FIFO كافية للمنتج % في المخزن المحدد حتى التاريخ التشغيلي',a."description";
    end if;
  end loop;
  if jsonb_array_length(v_lines)=0 then return null; end if;

  v_old_entry:=nullif(v_doc.payload->>'costJournalEntryId','');
  if v_old_entry is not null then
    update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and not is_deleted and data->>'entryId'=v_old_entry;
    update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_old_entry and not is_deleted;
  end if;
  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,'sales_inventory_fifo',p_delivery_id::text,
    'FIFO-'||replace(p_delivery_id::text,'-',''),
    'تكلفة إذن تجهيز المبيعات '||v_doc.document_number||' وفق FIFO',v_order.currency,v_lines,v_effective);
  update public.erp_inventory_fifo_consumptions set journal_entry_id=v_entry
    where company_id=p_company_id and delivery_id=p_delivery_id and status='active';

  with costs as (
    select item_id,warehouse_id,sum(quantity*unit_cost)/nullif(sum(quantity),0) average_fifo_cost
    from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and delivery_id=p_delivery_id and status='active'
    group by item_id,warehouse_id
  )
  update public.erp_inventory_movements m
  set data=m.data||jsonb_build_object('unitCost',c.average_fifo_cost,'movementDate',v_effective,
      'effectiveAt',v_effective,'costMethod','FIFO','fifoDeliveryId',p_delivery_id::text),
      updated_at=now(),updated_by=auth.uid()
  from costs c
  where m.company_id=p_company_id and not m.is_deleted
    and m.data->>'referenceType'='sales_delivery' and m.data->>'referenceId'=p_delivery_id::text
    and m.data->>'productId'=c.item_id and m.data->>'warehouseId'=c.warehouse_id;

  update public.erp_commercial_workflow_documents set
    effective_at=v_effective,
    payload=(payload-'costJournalEntryId')||jsonb_build_object(
      'costJournalEntryId',v_entry,'fifoCostJournalEntryId',v_entry,'costMethod','FIFO',
      'fifoBreakdown',v_breakdown,'totalCost',round(v_total,6),'fifoPostedAt',now(),
      'accountingPostedAt',now(),'effectiveAt',v_effective),updated_at=now()
  where id=p_delivery_id;
  return v_entry;
end;
$$;

create or replace function public.erp_require_any_cloud_permission(
  p_company_id uuid,p_permissions text[]
) returns void language plpgsql stable security definer set search_path=public as $$
declare p text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  foreach p in array p_permissions loop
    if public.erp_cloud_user_has_permission(p_company_id,p) then return; end if;
  end loop;
  raise exception 'operation_permission_required';
end;
$$;

-- Keep the proven stock movement logic as an internal implementation and wrap
-- it with FIFO registration/consumption. The guarded rename keeps the migration
-- safe when applied to a database that was partially upgraded.
do $$
begin
  if to_regprocedure('public.erp_approve_cloud_purchase_receipt_pre_fifo_1890(uuid,uuid)') is null
     and to_regprocedure('public.erp_approve_cloud_purchase_receipt(uuid,uuid)') is not null then
    alter function public.erp_approve_cloud_purchase_receipt(uuid,uuid)
      rename to erp_approve_cloud_purchase_receipt_pre_fifo_1890;
  end if;
  if to_regprocedure('public.erp_approve_cloud_sales_delivery_pre_fifo_1890(uuid,uuid)') is null
     and to_regprocedure('public.erp_approve_cloud_sales_delivery(uuid,uuid)') is not null then
    alter function public.erp_approve_cloud_sales_delivery(uuid,uuid)
      rename to erp_approve_cloud_sales_delivery_pre_fifo_1890;
  end if;
  if to_regprocedure('public.erp_cancel_cloud_purchase_receipt_pre_fifo_1890(uuid,uuid)') is null
     and to_regprocedure('public.erp_cancel_cloud_purchase_receipt(uuid,uuid)') is not null then
    alter function public.erp_cancel_cloud_purchase_receipt(uuid,uuid)
      rename to erp_cancel_cloud_purchase_receipt_pre_fifo_1890;
  end if;
  if to_regprocedure('public.erp_cancel_cloud_sales_delivery_pre_fifo_1890(uuid,uuid)') is null
     and to_regprocedure('public.erp_cancel_cloud_sales_delivery(uuid,uuid)') is not null then
    alter function public.erp_cancel_cloud_sales_delivery(uuid,uuid)
      rename to erp_cancel_cloud_sales_delivery_pre_fifo_1890;
  end if;
end $$;

create or replace function public.erp_approve_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.approve','purchases.update','purchases.create']);
  perform public.erp_approve_cloud_purchase_receipt_pre_fifo_1890(p_company_id,p_receipt_id);
  perform public.erp_fifo_register_purchase_receipt(p_company_id,p_receipt_id);
end;
$$;

create or replace function public.erp_approve_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.approve','sales.update','sales.create']);
  perform public.erp_fifo_prepare_opening_layers(p_company_id,p_delivery_id);
  perform public.erp_approve_cloud_sales_delivery_pre_fifo_1890(p_company_id,p_delivery_id);
  perform public.erp_fifo_apply_sales_delivery(p_company_id,p_delivery_id);
end;
$$;

create or replace function public.erp_cancel_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.cancel','sales.update','sales.delete']);
  perform public.erp_cancel_cloud_sales_delivery_pre_fifo_1890(p_company_id,p_delivery_id);
  update public.erp_inventory_cost_layers l set
    remaining_quantity=least(l.original_quantity,l.remaining_quantity+c.quantity),
    status='active',updated_at=now(),updated_by=auth.uid()
  from public.erp_inventory_fifo_consumptions c
  where c.company_id=p_company_id and c.delivery_id=p_delivery_id and c.status='active' and l.id=c.layer_id;
  update public.erp_inventory_fifo_consumptions set status='reversed',reversed_at=now()
    where company_id=p_company_id and delivery_id=p_delivery_id and status='active';
  update public.erp_commercial_workflow_documents set
    payload=payload||jsonb_build_object('fifoReversedAt',now()),updated_at=now()
    where company_id=p_company_id and id=p_delivery_id;
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.cancel','purchases.update','purchases.delete']);
  if exists(select 1 from public.erp_inventory_fifo_consumptions c
    join public.erp_inventory_cost_layers l on l.id=c.layer_id
    where l.company_id=p_company_id and l.receipt_id=p_receipt_id and c.status='active') then
    raise exception 'لا يمكن إلغاء إشعار الاستلام لأن جزءاً من وجباته بيع فعلياً؛ ألغِ مستندات البيع المرتبطة أولاً';
  end if;
  perform public.erp_cancel_cloud_purchase_receipt_pre_fifo_1890(p_company_id,p_receipt_id);
  update public.erp_inventory_cost_layers set remaining_quantity=0,status='reversed',updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and receipt_id=p_receipt_id and status<>'reversed';
end;
$$;

create or replace function public.erp_phase2_post_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare
  doc public.erp_commercial_workflow_documents%rowtype;ord public.erp_purchase_orders_cloud%rowtype;
  a record;ac jsonb;supplier_account text;lines jsonb:='[]';total numeric:=0;amount numeric;eid text;v_effective timestamptz;
begin
  select * into doc from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_receipt_id
    and module='purchases' and document_type='receipt' and not is_deleted;
  if not found or doc.status<>'approved' then raise exception 'يجب تصديق إشعار الاستلام المخزني أولاً'; end if;
  select * into ord from public.erp_purchase_orders_cloud where company_id=p_company_id and id=doc.parent_id and not is_deleted;
  v_effective:=coalesce(doc.effective_at,ord.effective_at,doc.created_at,now());
  select coalesce(pa.usd_account_id,pa.iqd_account_id) into supplier_account from public.erp_partner_accounts pa
    where pa.organization_id=p_company_id and pa.partner_type='supplier' and pa.partner_id=ord.supplier_id and pa.is_active limit 1;
  perform public.erp_phase2_account_guard(p_company_id,supplier_account,'liability',ord.currency);
  for a in select x.item_type,x.item_id,x.description,x.quantity,x.unit_cost from public.erp_purchase_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=ord.id and not x.is_deleted
  loop
    ac:=public.erp_phase2_item_accounts(p_company_id,a.item_type,a.item_id,ord.currency);
    amount:=a.quantity*a.unit_cost;total:=total+amount;
    lines:=lines||jsonb_build_array(jsonb_build_object('accountId',ac->>'assetAccountId','debit',amount,'credit',0,
      'description','إثبات استلام '||a.description,'itemType',a.item_type,'itemId',a.item_id));
  end loop;
  lines:=lines||jsonb_build_array(jsonb_build_object('accountId',supplier_account,'debit',0,'credit',total,'description','ذمة المورد'));
  eid:=public.erp_phase2_insert_journal_at(p_company_id,'purchases_inventory',p_receipt_id::text,
    'PINV-'||replace(p_receipt_id::text,'-',''),'قيد إشعار استلام المشتريات '||doc.document_number,ord.currency,lines,v_effective);
  update public.erp_commercial_workflow_documents set effective_at=v_effective,
    payload=payload||jsonb_build_object('inventoryJournalEntryId',eid,'accountingPostedAt',now(),'effectiveAt',v_effective),updated_at=now()
    where id=p_receipt_id;
  return eid;
end;
$$;

create or replace function public.erp_phase2_post_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare v_id text;
begin
  select nullif(payload->>'fifoCostJournalEntryId','') into v_id
    from public.erp_commercial_workflow_documents
    where company_id=p_company_id and id=p_delivery_id and module='sales' and document_type='delivery' and not is_deleted;
  if v_id is not null then return v_id; end if;
  return public.erp_fifo_apply_sales_delivery(p_company_id,p_delivery_id);
end;
$$;

create or replace function public.erp_phase2_approve_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language plpgsql security definer set search_path=public as $$ begin
  perform public.erp_approve_cloud_purchase_receipt(p_company_id,p_receipt_id);
  perform public.erp_phase2_post_purchase_receipt(p_company_id,p_receipt_id);
end $$;
create or replace function public.erp_phase2_approve_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language plpgsql security definer set search_path=public as $$ begin
  perform public.erp_approve_cloud_sales_delivery(p_company_id,p_delivery_id);
  perform public.erp_phase2_post_sales_delivery(p_company_id,p_delivery_id);
end $$;

-- Rebuild a deleted commercial transaction from its captured business
-- snapshot. This intentionally creates fresh operational documents and
-- journals while retaining the cancelled originals for audit.
create or replace function public.erp_phase2_restore_commercial_order_links(
  p_company_id uuid,p_order_id uuid,p_module text,p_snapshot jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_logistics jsonb:=p_snapshot->'logistics';
  v_invoice jsonb:=p_snapshot->'invoice';
  v_payments jsonb:=case when jsonb_typeof(p_snapshot->'payments')='array'
    then p_snapshot->'payments' else '[]'::jsonb end;
  v_payment jsonb;
  v_normalized_payments jsonb:='[]'::jsonb;
  v_mode text;
  v_allocations jsonb;
  v_logistics_id uuid;
  v_invoice_id uuid;
  v_order_status text:=coalesce(p_snapshot->>'orderStatus','draft');
  v_effective timestamptz;
  v_module text:=lower(btrim(p_module));
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    case when v_module='sales'
      then array['settings.recycle_bin.restore','sales.create','sales.update']
      else array['settings.recycle_bin.restore','purchases.create','purchases.update'] end
  );
  if v_module='sales' then
    select effective_at into v_effective from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  elsif v_module='purchases' then
    select effective_at into v_effective from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  else
    raise exception 'invalid workflow module';
  end if;
  v_effective:=coalesce(nullif(p_snapshot->>'effectiveAt','')::timestamptz,v_effective,now());
  perform public.erp_validate_operational_date(p_company_id,v_module,v_effective);

  if v_order_status='approved' or jsonb_typeof(v_logistics)='object' or jsonb_typeof(v_invoice)='object' then
    if v_module='sales' then
      perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  end if;

  if jsonb_typeof(v_logistics)='object' then
    v_allocations:=v_logistics->'allocations';
    if v_module='sales' then
      if jsonb_typeof(v_allocations)='array' and jsonb_array_length(v_allocations)>0 then
        v_logistics_id:=public.erp_create_cloud_sales_delivery_multi(
          p_company_id,p_order_id,v_allocations,v_logistics->>'notes');
      else
        v_logistics_id:=public.erp_create_cloud_sales_delivery(
          p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
      end if;
    else
      if jsonb_typeof(v_allocations)='array' and jsonb_array_length(v_allocations)>0 then
        v_logistics_id:=public.erp_create_cloud_purchase_receipt_multi(
          p_company_id,p_order_id,v_allocations,v_logistics->>'notes');
      else
        v_logistics_id:=public.erp_create_cloud_purchase_receipt(
          p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
      end if;
    end if;
    update public.erp_commercial_workflow_documents
    set effective_at=v_effective,updated_at=now()
    where company_id=p_company_id and id=v_logistics_id;
    if v_logistics->>'status'='approved' then
      if v_module='sales' then
        perform public.erp_fifo_prepare_opening_layers(p_company_id,v_logistics_id);
        perform public.erp_approve_cloud_sales_delivery_pre_fifo_1890(p_company_id,v_logistics_id);
        perform public.erp_fifo_apply_sales_delivery(p_company_id,v_logistics_id);
      else
        perform public.erp_approve_cloud_purchase_receipt_pre_fifo_1890(p_company_id,v_logistics_id);
        perform public.erp_fifo_register_purchase_receipt(p_company_id,v_logistics_id);
        perform public.erp_phase2_post_purchase_receipt(p_company_id,v_logistics_id);
      end if;
    end if;
  end if;

  if jsonb_typeof(v_invoice)='object' then
    if v_module='sales' then
      v_invoice_id:=public.erp_create_cloud_sales_workflow_invoice(p_company_id,p_order_id);
    else
      v_invoice_id:=public.erp_create_cloud_purchase_workflow_invoice(p_company_id,p_order_id);
    end if;
    update public.erp_commercial_workflow_documents
    set effective_at=v_effective,updated_at=now()
    where company_id=p_company_id and id=v_invoice_id;
    if v_invoice->>'status'='approved' then
      if v_module='sales' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,v_invoice_id);
      else
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    end if;
    if jsonb_array_length(v_payments)>0 and v_invoice->>'status'<>'approved' then
      raise exception 'لا يمكن إعادة الدفعات إلى فاتورة غير مصدقة';
    end if;
    for v_payment in select value from jsonb_array_elements(v_payments) loop
      v_mode:=lower(btrim(coalesce(v_payment->>'settlementMode','partial')));
      v_mode:=case
        when v_mode in ('full','fullwithexchangedifference') then 'full'
        when v_mode in ('settlement','full_fx')
             and nullif(v_payment->>'settlementAccountId','') is not null then 'settlement'
        when v_mode in ('full_fx','fullwithexchangedifference') then 'full'
        else 'partial'
      end;
      v_normalized_payments:=v_normalized_payments||jsonb_build_array(
        (v_payment
          - 'paymentId' - 'paymentKey' - 'journalEntryId' - 'cashTransactionId'
          - 'previousRemainingAmount' - 'remainingAmount' - 'createdAt' - 'createdBy')
        ||jsonb_build_object('settlementMode',v_mode)
      );
    end loop;
    if jsonb_array_length(v_normalized_payments)>0 then
      perform public.erp_apply_cloud_workflow_invoice_payment_batch(
        p_company_id,v_invoice_id,v_module,v_normalized_payments);
    end if;
    update public.erp_journal_entries
    set data=data||jsonb_build_object('entryDate',v_effective,'effectiveAt',v_effective),
        updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'referenceId'=v_invoice_id::text;
  end if;

  return jsonb_build_object(
    'orderId',p_order_id,'logisticsId',v_logistics_id,'invoiceId',v_invoice_id,
    'effectiveAt',v_effective
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Permissioned cascade deletion with linked reversal and one recycle batch.
-- ---------------------------------------------------------------------------
create or replace function public.erp_delete_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb;v_number text;v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.delete']);
  select order_number into v_number from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;
  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_purchase_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر الشراء وعكس الاستلام والفاتورة والدفعات والقيود',true);
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'purchases','حذف أمر الشراء وعكس ارتباطاته');
  v_snapshot:=jsonb_set(v_snapshot,'{effectiveAt}',to_jsonb((select effective_at from public.erp_purchase_orders_cloud where id=p_order_id)),true);
  if jsonb_typeof(v_snapshot->'logistics')='object' then
    v_snapshot:=jsonb_set(v_snapshot,'{logistics,allocations}',coalesce((
      select payload->'allocations' from public.erp_commercial_workflow_documents
      where company_id=p_company_id and id=(v_snapshot#>>'{logistics,id}')::uuid
    ),'[]'::jsonb),true);
  end if;
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted',
    'حذف مترابط مع عكس إشعار الاستلام والفاتورة والدفعات والقيود ووجبات FIFO');
  update public.erp_commercial_workflow_documents set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and parent_id=p_order_id and module='purchases' and not is_deleted;
  update public.erp_purchase_order_items_cloud set is_deleted=true
    where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_purchase_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','purchases','commercialSnapshot',v_snapshot
  ) where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb;v_number text;v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.delete']);
  select order_number into v_number from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then return; end if;
  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_sales_orders_cloud',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason','حذف أمر البيع وعكس التجهيز والفاتورة والدفعات والقيود',true);
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','حذف أمر البيع وعكس ارتباطاته');
  v_snapshot:=jsonb_set(v_snapshot,'{effectiveAt}',to_jsonb((select effective_at from public.erp_sales_orders_cloud where id=p_order_id)),true);
  if jsonb_typeof(v_snapshot->'logistics')='object' then
    v_snapshot:=jsonb_set(v_snapshot,'{logistics,allocations}',coalesce((
      select payload->'allocations' from public.erp_commercial_workflow_documents
      where company_id=p_company_id and id=(v_snapshot#>>'{logistics,id}')::uuid
    ),'[]'::jsonb),true);
  end if;
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted',
    'حذف مترابط مع عكس إذن التجهيز والفاتورة والدفعات والقيود واستهلاك FIFO');
  update public.erp_commercial_workflow_documents set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted;
  update public.erp_sales_order_items_cloud set is_deleted=true
    where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_sales_orders_cloud set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'commercialModule','sales','commercialSnapshot',v_snapshot
  ) where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_inventory_product_delete_impact(
  p_company_id uuid,p_product_id text
) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'stockQuantity',coalesce((select sum(public.erp_try_numeric(data->>'quantity',0))
      from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id),0),
    'salesOrderLinks',(select count(*) from public.erp_sales_order_items_cloud i join public.erp_sales_orders_cloud o on o.id=i.order_id
      where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted),
    'purchaseOrderLinks',(select count(*) from public.erp_purchase_order_items_cloud i join public.erp_purchase_orders_cloud o on o.id=i.order_id
      where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted),
    'transferLinks',(select count(*) from public.erp_warehouse_transfer_items
      where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id),
    'activeFifoQuantity',coalesce((select sum(remaining_quantity) from public.erp_inventory_cost_layers
      where company_id=p_company_id and item_type='product' and item_id=p_product_id and status in ('active','consumed')),0),
    'activeFifoConsumptions',(select count(*) from public.erp_inventory_fifo_consumptions
      where company_id=p_company_id and item_type='product' and item_id=p_product_id and status='active')
  ) where public.erp_is_company_member(p_company_id);
$$;

create or replace function public.erp_delete_inventory_product(
  p_company_id uuid,p_product_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_batch uuid:=gen_random_uuid();v_stock numeric;v_sales bigint;v_purchases bigint;v_transfers bigint;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['inventory.delete']);
  perform 1 from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted for update;
  if not found then raise exception 'المنتج غير موجود'; end if;
  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0) into v_stock
    from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  if v_stock<>0 then raise exception 'لا يمكن حذف المادة قبل تصفير رصيدها في جميع المخازن؛ الرصيد الحالي %',v_stock; end if;
  select count(*) into v_sales from public.erp_sales_order_items_cloud i join public.erp_sales_orders_cloud o on o.id=i.order_id
    where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted;
  select count(*) into v_purchases from public.erp_purchase_order_items_cloud i join public.erp_purchase_orders_cloud o on o.id=i.order_id
    where i.company_id=p_company_id and i.item_type='product' and i.item_id=p_product_id and not i.is_deleted and not o.is_deleted;
  select count(*) into v_transfers from public.erp_warehouse_transfer_items
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  if v_sales+v_purchases+v_transfers>0 then
    raise exception 'يجب حذف أو إلغاء الارتباطات أولاً: مبيعات=%، مشتريات=%، نقل مخزني=%',v_sales,v_purchases,v_transfers;
  end if;
  if exists(select 1 from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and item_type='product' and item_id=p_product_id and status='active') then
    raise exception 'لا يمكن حذف المادة قبل إلغاء مستندات البيع التي استهلكت وجباتها';
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_inventory',true);
  perform set_config('qualityline.deletion_root_id',p_product_id,true);
  perform set_config('qualityline.deletion_reason','حذف مادة مخزنية بعد التحقق من الأرصدة والارتباطات',true);

  delete from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id and item_type='product' and item_id=p_product_id;
  delete from public.erp_inventory_cost_layers
    where company_id=p_company_id and item_type='product' and item_id=p_product_id;
  update public.erp_inventory_movements set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_product_images set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_warehouse_stock set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_inventory_product_sales set is_deleted=true,deleted_at=now(),updated_at=now()
    where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_inventory set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=p_product_id and not is_deleted;
end;
$$;

-- Attach recycle capture to tables created by this migration.
do $$ declare t text;begin
  foreach t in array array['erp_inventory_cost_layers','erp_inventory_fifo_consumptions','erp_operational_periods'] loop
    execute format('drop trigger if exists erp_capture_hard_delete on public.%I',t);
    execute format('create trigger erp_capture_hard_delete before delete on public.%I for each row execute function public.erp_capture_deleted_record()',t);
    execute format('drop trigger if exists erp_capture_soft_delete on public.%I',t);
    if t='erp_operational_periods' then
      execute format('create trigger erp_capture_soft_delete after update on public.%I for each row execute function public.erp_capture_soft_deleted_record()',t);
    end if;
  end loop;
end $$;

-- Grants and security boundaries.
-- Renaming preserves function ACLs, so explicitly remove direct access to the
-- pre-FIFO implementations. Only the guarded wrappers below remain callable.
do $$
begin
  if to_regprocedure('public.erp_approve_cloud_purchase_receipt_pre_fifo_1890(uuid,uuid)') is not null then
    execute 'revoke all on function public.erp_approve_cloud_purchase_receipt_pre_fifo_1890(uuid,uuid) from public,anon,authenticated';
  end if;
  if to_regprocedure('public.erp_approve_cloud_sales_delivery_pre_fifo_1890(uuid,uuid)') is not null then
    execute 'revoke all on function public.erp_approve_cloud_sales_delivery_pre_fifo_1890(uuid,uuid) from public,anon,authenticated';
  end if;
  if to_regprocedure('public.erp_cancel_cloud_purchase_receipt_pre_fifo_1890(uuid,uuid)') is not null then
    execute 'revoke all on function public.erp_cancel_cloud_purchase_receipt_pre_fifo_1890(uuid,uuid) from public,anon,authenticated';
  end if;
  if to_regprocedure('public.erp_cancel_cloud_sales_delivery_pre_fifo_1890(uuid,uuid)') is not null then
    execute 'revoke all on function public.erp_cancel_cloud_sales_delivery_pre_fifo_1890(uuid,uuid) from public,anon,authenticated';
  end if;
end $$;

revoke all on function public.erp_capture_deleted_record() from public,anon,authenticated;
revoke all on function public.erp_capture_soft_deleted_record() from public,anon,authenticated;
revoke all on function public.erp_assign_professional_document_number() from public,anon,authenticated;
revoke all on function public.erp_phase2_insert_journal_at(uuid,text,text,text,text,text,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function public.erp_fifo_prepare_opening_layers(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_require_any_cloud_permission(uuid,text[]) from public,anon,authenticated;
revoke all on function public.erp_next_document_number(uuid,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.erp_set_operational_effective_at(uuid,text,text,uuid,timestamptz) from public,anon;
revoke all on function public.erp_list_operational_periods(uuid) from public,anon;
revoke all on function public.erp_save_operational_period(uuid,uuid,text,text,timestamptz,timestamptz,text,text) from public,anon;
revoke all on function public.erp_delete_operational_period(uuid,uuid) from public,anon;
revoke all on function public.erp_validate_operational_date(uuid,text,timestamptz) from public,anon,authenticated;
revoke all on function public.erp_next_child_account_code(uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_fifo_register_purchase_receipt(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_fifo_apply_sales_delivery(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_inventory_product_delete_impact(uuid,text) from public,anon;
revoke all on function public.erp_delete_inventory_product(uuid,text) from public,anon;
revoke all on function public.erp_approve_cloud_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_approve_cloud_sales_delivery(uuid,uuid) from public,anon;
revoke all on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) from public,anon;
revoke all on function public.erp_phase2_approve_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_phase2_approve_sales_delivery(uuid,uuid) from public,anon;
revoke all on function public.erp_phase2_restore_commercial_order_links(uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.erp_phase2_post_purchase_receipt(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_phase2_post_sales_delivery(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_delete_cloud_purchase_order(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_sales_order(uuid,uuid) from public,anon;
revoke all on function public.erp_recycle_bin_list(uuid,text,text) from public,anon;
revoke all on function public.erp_recycle_bin_restore(uuid,text,text) from public,anon;
revoke all on function public.erp_recycle_bin_purge(uuid,text,text) from public,anon;
grant execute on function public.erp_recycle_bin_list(uuid,text,text) to authenticated;
grant execute on function public.erp_recycle_bin_restore(uuid,text,text) to authenticated;
grant execute on function public.erp_recycle_bin_purge(uuid,text,text) to authenticated;
grant execute on function public.erp_set_operational_effective_at(uuid,text,text,uuid,timestamptz) to authenticated;
grant execute on function public.erp_list_operational_periods(uuid) to authenticated;
grant execute on function public.erp_save_operational_period(uuid,uuid,text,text,timestamptz,timestamptz,text,text) to authenticated;
grant execute on function public.erp_delete_operational_period(uuid,uuid) to authenticated;
grant execute on function public.erp_inventory_product_delete_impact(uuid,text) to authenticated;
grant execute on function public.erp_delete_inventory_product(uuid,text) to authenticated;
grant execute on function public.erp_approve_cloud_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_approve_cloud_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_phase2_approve_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_phase2_approve_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_delete_cloud_purchase_order(uuid,uuid) to authenticated;
grant execute on function public.erp_delete_cloud_sales_order(uuid,uuid) to authenticated;
grant select on public.erp_document_sequences,public.erp_operational_periods,
  public.erp_inventory_cost_layers,public.erp_inventory_fifo_consumptions to authenticated;

commit;
