-- Phase 24: cloud-only governance, security and data scopes.
create extension if not exists pgcrypto;

create table if not exists public.erp_role_data_scopes (
  id uuid primary key default gen_random_uuid(), company_id uuid not null,
  role_id text not null, scope_type text not null check (scope_type in ('branch','warehouse')),
  scope_id text not null, can_view boolean not null default true,
  can_create boolean not null default false, can_update boolean not null default false,
  can_delete boolean not null default false, created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(), deleted_at timestamptz,
  unique(company_id, role_id, scope_type, scope_id)
);
create table if not exists public.erp_security_events (
  id uuid primary key default gen_random_uuid(), company_id uuid not null,
  event_type text not null, severity text not null default 'info', user_id text,
  outcome text not null default 'success', description text, metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(), acknowledged_at timestamptz, acknowledged_by text
);
create table if not exists public.erp_security_sessions (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, user_id text not null,
  status text not null default 'active', revoked_at timestamptz, revoke_reason text, created_at timestamptz not null default now()
);
create table if not exists public.erp_security_trusted_devices (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, user_id text,
  status text not null default 'trusted', created_at timestamptz not null default now()
);
create table if not exists public.erp_security_mfa_factors (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, user_id text,
  is_verified boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.erp_security_identity_providers (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, code text not null,
  name text not null, provider_type text not null, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(company_id,code)
);
create table if not exists public.erp_governance_approvals (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, module text not null,
  record_id text not null, action text not null, amount_usd numeric not null default 0,
  requested_by text, requested_at timestamptz not null default now(), status text not null default 'pending',
  reviewed_by text, reviewed_at timestamptz, notes text
);
create table if not exists public.erp_governance_attachments (
  id text primary key, company_id uuid not null, module text not null, record_id text not null,
  file_name text not null, mime_type text not null, storage_path text not null unique,
  size_bytes bigint not null, created_by text, created_at timestamptz not null default now(), deleted_at timestamptz
);
create table if not exists public.erp_branch_transfers (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, transfer_number text not null,
  module text not null, record_id text not null, from_branch_id text not null, to_branch_id text not null,
  quantity numeric not null default 1, status text not null default 'completed', transferred_at timestamptz not null default now(),
  transferred_by text, notes text, unique(company_id,transfer_number)
);
create table if not exists public.erp_login_attempts (
  id uuid primary key default gen_random_uuid(), company_id uuid not null, username text not null,
  succeeded boolean not null, attempted_at timestamptz not null default now(), device_info text, failure_reason text
);

alter table public.erp_role_data_scopes enable row level security;
alter table public.erp_security_events enable row level security;
alter table public.erp_security_sessions enable row level security;
alter table public.erp_security_trusted_devices enable row level security;
alter table public.erp_security_mfa_factors enable row level security;
alter table public.erp_security_identity_providers enable row level security;
alter table public.erp_governance_approvals enable row level security;
alter table public.erp_governance_attachments enable row level security;
alter table public.erp_branch_transfers enable row level security;
alter table public.erp_login_attempts enable row level security;

-- Existing helper introduced by earlier migrations validates active company membership.
do $$ declare t text; begin
  foreach t in array array['erp_role_data_scopes','erp_security_events','erp_security_sessions','erp_security_trusted_devices','erp_security_mfa_factors','erp_security_identity_providers','erp_governance_approvals','erp_governance_attachments','erp_branch_transfers','erp_login_attempts'] loop
    execute format('drop policy if exists company_members_only on public.%I',t);
    execute format('create policy company_members_only on public.%I for all using (public.erp_is_active_company_member(company_id)) with check (public.erp_is_active_company_member(company_id))',t);
  end loop;
end $$;

create or replace function public.erp_list_cloud_role_data_scopes(p_company_id uuid,p_role_id text) returns setof public.erp_role_data_scopes language sql security definer set search_path=public as $$
 select * from public.erp_role_data_scopes where company_id=p_company_id and role_id=p_role_id and deleted_at is null order by scope_type,scope_id;
$$;
create or replace function public.erp_save_cloud_role_data_scope(p_company_id uuid,p_role_id text,p_scope_type text,p_scope_id text,p_can_view boolean,p_can_create boolean,p_can_update boolean,p_can_delete boolean) returns void language plpgsql security definer set search_path=public as $$ begin
 if not public.erp_is_active_company_member(p_company_id) then raise exception 'forbidden'; end if;
 insert into public.erp_role_data_scopes(company_id,role_id,scope_type,scope_id,can_view,can_create,can_update,can_delete)
 values(p_company_id,p_role_id,p_scope_type,p_scope_id,p_can_view,p_can_create,p_can_update,p_can_delete)
 on conflict(company_id,role_id,scope_type,scope_id) do update set can_view=excluded.can_view,can_create=excluded.can_create,can_update=excluded.can_update,can_delete=excluded.can_delete,updated_at=now(),deleted_at=null;
end $$;
create or replace function public.erp_cloud_role_scope_allowed(p_company_id uuid,p_role_id text,p_scope_type text,p_scope_id text,p_action text) returns boolean language sql security definer set search_path=public as $$
 select coalesce((select case p_action when 'view' then can_view when 'create' then can_create when 'update' then can_update when 'delete' then can_delete else false end from public.erp_role_data_scopes where company_id=p_company_id and role_id=p_role_id and scope_type=p_scope_type and scope_id=p_scope_id and deleted_at is null),false);
$$;

create or replace function public.erp_cloud_security_summary(p_company_id uuid) returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('activeSessions',(select count(*) from erp_security_sessions where company_id=p_company_id and status='active'),'trustedDevices',(select count(*) from erp_security_trusted_devices where company_id=p_company_id and status='trusted'),'verifiedMfa',(select count(*) from erp_security_mfa_factors where company_id=p_company_id and is_verified),'criticalEvents',(select count(*) from erp_security_events where company_id=p_company_id and severity in ('high','critical') and acknowledged_at is null),'identityProviders',(select count(*) from erp_security_identity_providers where company_id=p_company_id and is_active));
$$;
create or replace function public.erp_list_cloud_security_events(p_company_id uuid,p_limit integer default 30) returns setof public.erp_security_events language sql security definer set search_path=public as $$ select * from erp_security_events where company_id=p_company_id order by occurred_at desc limit greatest(1,least(p_limit,200)); $$;
create or replace function public.erp_log_cloud_security_event(p_company_id uuid,p_event_type text,p_severity text,p_outcome text,p_user_id text,p_description text,p_metadata jsonb) returns void language sql security definer set search_path=public as $$ insert into erp_security_events(company_id,event_type,severity,outcome,user_id,description,metadata) values(p_company_id,p_event_type,p_severity,p_outcome,p_user_id,p_description,coalesce(p_metadata,'{}'::jsonb)); $$;
create or replace function public.erp_seed_cloud_security_baseline(p_company_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin insert into erp_security_identity_providers(company_id,code,name,provider_type) values(p_company_id,'SUPABASE','Supabase Auth','supabase') on conflict(company_id,code) do update set is_active=true,updated_at=now(); perform erp_log_cloud_security_event(p_company_id,'security_baseline_initialized','info','success',auth.uid()::text,'تمت تهيئة خط الأساس الأمني السحابي.','{}'); end $$;
create or replace function public.erp_revoke_cloud_user_sessions(p_company_id uuid,p_user_id text,p_reason text) returns void language plpgsql security definer set search_path=public as $$ begin update erp_security_sessions set status='revoked',revoked_at=now(),revoke_reason=p_reason where company_id=p_company_id and user_id=p_user_id and status='active'; perform erp_log_cloud_security_event(p_company_id,'sessions_revoked','high','success',p_user_id,'تم إلغاء جميع جلسات المستخدم.','{}'); end $$;
create or replace function public.erp_acknowledge_cloud_security_event(p_company_id uuid,p_event_id uuid,p_user_id text) returns void language sql security definer set search_path=public as $$ update erp_security_events set acknowledged_at=now(),acknowledged_by=coalesce(p_user_id,auth.uid()::text) where company_id=p_company_id and id=p_event_id and acknowledged_at is null; $$;

create or replace function public.erp_request_cloud_governance_approval(p_company_id uuid,p_module text,p_record_id text,p_action text,p_amount_usd numeric,p_requested_by text,p_notes text) returns uuid language plpgsql security definer set search_path=public as $$ declare v uuid; begin insert into erp_governance_approvals(company_id,module,record_id,action,amount_usd,requested_by,notes) values(p_company_id,p_module,p_record_id,p_action,p_amount_usd,p_requested_by,p_notes) returning id into v; return v; end $$;
create or replace function public.erp_review_cloud_governance_approval(p_company_id uuid,p_approval_id uuid,p_approved boolean,p_reviewed_by text,p_notes text) returns void language plpgsql security definer set search_path=public as $$ begin update erp_governance_approvals set status=case when p_approved then 'approved' else 'rejected' end,reviewed_by=p_reviewed_by,reviewed_at=now(),notes=coalesce(p_notes,notes) where company_id=p_company_id and id=p_approval_id and status='pending'; if not found then raise exception 'Approval is missing or already reviewed'; end if; end $$;
create or replace function public.erp_list_cloud_governance_approvals(p_company_id uuid,p_module text default null) returns setof public.erp_governance_approvals language sql security definer set search_path=public as $$ select * from erp_governance_approvals where company_id=p_company_id and status='pending' and (p_module is null or module=p_module) order by requested_at; $$;
create or replace function public.erp_register_cloud_governance_attachment(p_company_id uuid,p_attachment_id text,p_module text,p_record_id text,p_file_name text,p_mime_type text,p_storage_path text,p_size_bytes bigint,p_created_by text) returns text language sql security definer set search_path=public as $$ insert into erp_governance_attachments(id,company_id,module,record_id,file_name,mime_type,storage_path,size_bytes,created_by) values(p_attachment_id,p_company_id,p_module,p_record_id,p_file_name,p_mime_type,p_storage_path,p_size_bytes,p_created_by) returning id; $$;
create or replace function public.erp_list_cloud_governance_attachments(p_company_id uuid,p_module text,p_record_id text) returns setof public.erp_governance_attachments language sql security definer set search_path=public as $$ select * from erp_governance_attachments where company_id=p_company_id and module=p_module and record_id=p_record_id and deleted_at is null order by created_at desc; $$;
create or replace function public.erp_get_cloud_governance_attachment_path(p_company_id uuid,p_attachment_id text) returns text language sql security definer set search_path=public as $$ select storage_path from erp_governance_attachments where company_id=p_company_id and id=p_attachment_id and deleted_at is null; $$;
create or replace function public.erp_record_cloud_login_attempt(p_company_id uuid,p_username text,p_succeeded boolean,p_device_info text,p_failure_reason text) returns void language sql security definer set search_path=public as $$ insert into erp_login_attempts(company_id,username,succeeded,device_info,failure_reason) values(p_company_id,p_username,p_succeeded,p_device_info,p_failure_reason); $$;
create or replace function public.erp_generate_cloud_operational_alerts(p_company_id uuid)
returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_is_active_company_member(p_company_id) then
    raise exception 'forbidden';
  end if;

  insert into public.erp_enterprise_notifications(company_id,id,data)
  select
    p_company_id,
    gen_random_uuid(),
    jsonb_build_object(
      'titleAr','قسط متأخر',
      'titleEn','Overdue installment',
      'bodyAr','يوجد قسط متأخر يحتاج إلى متابعة.',
      'bodyEn','An overdue installment requires follow-up.',
      'type','overdue_installment',
      'referenceType','installments',
      'referenceId',i.id,
      'isRead',false,
      'createdAt',now()
    )
  from public.erp_installments i
  where i.company_id=p_company_id
    and not i.is_deleted
    and coalesce(i.data->>'status','')<>'paid'
    and nullif(i.data->>'dueDate','')::date<current_date
    and not exists(
      select 1
      from public.erp_enterprise_notifications n
      where n.company_id=p_company_id
        and not n.is_deleted
        and n.data->>'type'='overdue_installment'
        and n.data->>'referenceId'=i.id
        and not coalesce(nullif(n.data->>'isRead','')::boolean,false)
    );
end $$;

insert into storage.buckets(id,name,public) values('enterprise-governance','enterprise-governance',false) on conflict(id) do update set public=false;
drop policy if exists enterprise_governance_storage_select on storage.objects;
drop policy if exists enterprise_governance_storage_insert on storage.objects;
create policy enterprise_governance_storage_select on storage.objects for select using (bucket_id='enterprise-governance' and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid));
create policy enterprise_governance_storage_insert on storage.objects for insert with check (bucket_id='enterprise-governance' and public.erp_is_active_company_member((storage.foldername(name))[1]::uuid));
create or replace function public.erp_close_cloud_governance_period(
  p_company_id uuid,
  p_period_id text,
  p_closed_by text
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.erp_is_active_company_member(p_company_id) then
    raise exception 'forbidden';
  end if;

  update public.erp_fiscal_periods
  set data=data||jsonb_build_object(
        'status','closed',
        'closedBy',p_closed_by,
        'closedAt',now(),
        'updatedAt',now()
      ),
      updated_at=now(),
      updated_by=auth.uid()
  where company_id=p_company_id
    and id=p_period_id
    and not is_deleted
    and data->>'status'='open';

  if not found then
    raise exception 'Financial period is missing or already closed';
  end if;
end $$;
create or replace function public.erp_transfer_cloud_branch_record(
  p_company_id uuid,
  p_module text,
  p_record_id text,
  p_from_branch_id text,
  p_to_branch_id text,
  p_quantity numeric,
  p_transferred_by text,
  p_notes text
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_num text;
begin
  if not public.erp_is_active_company_member(p_company_id) then
    raise exception 'forbidden';
  end if;
  if nullif(trim(p_from_branch_id),'') is null
     or nullif(trim(p_to_branch_id),'') is null
     or p_from_branch_id=p_to_branch_id then
    raise exception 'Branches must be different';
  end if;
  if coalesce(p_quantity,0)<=0 then
    raise exception 'Transfer quantity must be positive';
  end if;

  v_num:='BR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');

  if p_module='cars' then
    update public.erp_cars
    set data=data||jsonb_build_object('branchId',p_to_branch_id,'updatedAt',now()),
        updated_at=now()
    where company_id=p_company_id
      and id=p_record_id
      and data->>'branchId'=p_from_branch_id
      and not is_deleted;
  elsif p_module='inventory' then
    update public.erp_inventory
    set data=data||jsonb_build_object('branchId',p_to_branch_id,'updatedAt',now()),
        updated_at=now()
    where company_id=p_company_id
      and id=p_record_id
      and data->>'branchId'=p_from_branch_id
      and not is_deleted;
  else
    raise exception 'Unsupported branch transfer module';
  end if;

  if not found then
    raise exception 'Record is missing or belongs to another branch';
  end if;

  insert into public.erp_branch_transfers(
    id,company_id,transfer_number,module,record_id,from_branch_id,to_branch_id,
    quantity,transferred_by,notes
  ) values(
    v_id,p_company_id,v_num,p_module,p_record_id,p_from_branch_id,p_to_branch_id,
    p_quantity,p_transferred_by,p_notes
  );
  return v_id;
end $$;
