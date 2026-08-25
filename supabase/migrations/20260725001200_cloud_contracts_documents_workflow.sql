-- Phase 18: Supabase-only contracts workflow and document management.

create table if not exists public.erp_contracts (
  company_id uuid not null, id uuid not null, data jsonb not null default '{}'::jsonb,
  is_deleted boolean not null default false, deleted_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key(company_id,id)
);
create table if not exists public.erp_contract_versions (like public.erp_contracts including all);
create table if not exists public.erp_contract_events (like public.erp_contracts including all);
create table if not exists public.erp_contract_reviews (like public.erp_contracts including all);
create table if not exists public.erp_contract_approval_requests (like public.erp_contracts including all);
create table if not exists public.erp_contract_signature_requests (like public.erp_contracts including all);
create table if not exists public.erp_contract_parties (like public.erp_contracts including all);
create table if not exists public.erp_contract_renewals (like public.erp_contracts including all);
create table if not exists public.erp_contract_lifecycle_runs (like public.erp_contracts including all);
create table if not exists public.erp_enterprise_notifications (like public.erp_contracts including all);
create table if not exists public.erp_document_records (like public.erp_contracts including all);
create table if not exists public.erp_document_versions (like public.erp_contracts including all);
create table if not exists public.erp_document_links (like public.erp_contracts including all);
create table if not exists public.erp_document_permissions (like public.erp_contracts including all);
create table if not exists public.erp_document_signatures (like public.erp_contracts including all);
create table if not exists public.erp_document_events (like public.erp_contracts including all);

create unique index if not exists erp_contract_number_uq on public.erp_contracts(company_id,((data->>'contractNumber'))) where not is_deleted;
create index if not exists erp_contract_status_idx on public.erp_contracts(company_id,((data->>'status')));
create index if not exists erp_contract_review_idx on public.erp_contract_reviews(company_id,((data->>'contractId')),((data->>'status')));
create index if not exists erp_contract_signature_idx on public.erp_contract_signature_requests(company_id,((data->>'contractId')),((data->>'status')));
create unique index if not exists erp_document_number_uq on public.erp_document_records(company_id,((data->>'documentNumber'))) where not is_deleted;
create index if not exists erp_document_status_idx on public.erp_document_records(company_id,((data->>'status')));
create index if not exists erp_document_version_idx on public.erp_document_versions(company_id,((data->>'documentId')),((data->>'versionNumber')));
create unique index if not exists erp_document_permission_uq on public.erp_document_permissions(company_id,((data->>'documentId')),((data->>'principalType')),((data->>'principalId'))) where not is_deleted;

alter table public.erp_contracts enable row level security;
alter table public.erp_contract_versions enable row level security;
alter table public.erp_contract_events enable row level security;
alter table public.erp_contract_reviews enable row level security;
alter table public.erp_contract_approval_requests enable row level security;
alter table public.erp_contract_signature_requests enable row level security;
alter table public.erp_contract_parties enable row level security;
alter table public.erp_contract_renewals enable row level security;
alter table public.erp_contract_lifecycle_runs enable row level security;
alter table public.erp_enterprise_notifications enable row level security;
alter table public.erp_document_records enable row level security;
alter table public.erp_document_versions enable row level security;
alter table public.erp_document_links enable row level security;
alter table public.erp_document_permissions enable row level security;
alter table public.erp_document_signatures enable row level security;
alter table public.erp_document_events enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'erp_contracts','erp_contract_versions','erp_contract_events','erp_contract_reviews',
    'erp_contract_approval_requests','erp_contract_signature_requests','erp_contract_parties',
    'erp_contract_renewals','erp_contract_lifecycle_runs','erp_enterprise_notifications',
    'erp_document_records','erp_document_versions','erp_document_links','erp_document_permissions',
    'erp_document_signatures','erp_document_events'
  ] loop
    execute format('drop policy if exists tenant_access on public.%I',t);
    execute format('create policy tenant_access on public.%I for all using (public.erp_user_belongs_to_company(company_id)) with check (public.erp_user_belongs_to_company(company_id))',t);
  end loop;
end $$;

create or replace function public.erp_contract_event(p_company_id uuid,p_contract_id uuid,p_type text,p_from text,p_to text,p_actor text,p_description text)
returns void language plpgsql security definer set search_path=public as $$
begin
  insert into erp_contract_events(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object(
    'contractId',p_contract_id,'eventType',p_type,'fromStatus',p_from,'toStatus',p_to,
    'performedBy',p_actor,'description',coalesce(p_description,''),'occurredAt',now()));
end $$;

create or replace function public.erp_transition_cloud_contract(p_company_id uuid,p_contract_id uuid,p_action text,p_reason text,p_performed_by text)
returns void language plpgsql security definer set search_path=public as $$
declare c record; target text; allowed boolean := false;
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  select * into c from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted for update;
  if c.id is null then raise exception 'contract not found'; end if;
  target := case p_action when 'activate' then 'active' when 'suspend' then 'suspended' when 'resume' then 'active' when 'cancel' then 'cancelled' when 'terminate' then 'terminated' else null end;
  allowed := case p_action
    when 'activate' then c.data->>'status'='approved' and not exists(select 1 from erp_contract_signature_requests s where s.company_id=p_company_id and s.data->>'contractId'=p_contract_id::text and not s.is_deleted and s.data->>'status'='pending') and exists(select 1 from erp_contract_signature_requests s where s.company_id=p_company_id and s.data->>'contractId'=p_contract_id::text and not s.is_deleted and s.data->>'status'='signed')
    when 'suspend' then c.data->>'status'='active'
    when 'resume' then c.data->>'status'='suspended'
    when 'cancel' then c.data->>'status' in ('draft','under_review','pending_approval','approved')
    when 'terminate' then c.data->>'status' in ('active','suspended') else false end;
  if not allowed then raise exception 'invalid contract transition'; end if;
  update erp_contracts set data=data || jsonb_build_object('status',target,'updatedAt',now(),'cancellationReason',case when p_action in ('cancel','terminate') then p_reason else data->>'cancellationReason' end),updated_at=now() where company_id=p_company_id and id=p_contract_id;
  perform erp_contract_event(p_company_id,p_contract_id,p_action,c.data->>'status',target,p_performed_by,p_reason);
end $$;

create or replace function public.erp_request_cloud_contract_review(p_company_id uuid,p_contract_id uuid,p_reviewer_user_id text,p_reviewer_role_id text,p_requested_by text)
returns uuid language plpgsql security definer set search_path=public as $$
declare c record; v record; rid uuid:=gen_random_uuid();
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  select * into c from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted for update;
  if c.id is null or c.data->>'status'<>'draft' then raise exception 'only draft contracts can be reviewed'; end if;
  select * into v from erp_contract_versions where company_id=p_company_id and data->>'contractId'=p_contract_id::text and not is_deleted order by (data->>'versionNumber')::int desc limit 1;
  if v.id is null then raise exception 'contract version not found'; end if;
  insert into erp_contract_reviews(company_id,id,data) values(p_company_id,rid,jsonb_build_object('contractId',p_contract_id,'contractVersionId',v.id,'reviewerUserId',p_reviewer_user_id,'reviewerRoleId',p_reviewer_role_id,'status','pending','requestedBy',p_requested_by,'requestedAt',now()));
  update erp_contracts set data=data||jsonb_build_object('status','under_review','updatedAt',now()),updated_at=now() where company_id=p_company_id and id=p_contract_id;
  perform erp_contract_event(p_company_id,p_contract_id,'submit_review','draft','under_review',p_requested_by,'');
  return rid;
end $$;

create or replace function public.erp_complete_cloud_contract_review(p_company_id uuid,p_review_id uuid,p_accepted boolean,p_comments text,p_reviewed_by text)
returns void language plpgsql security definer set search_path=public as $$
declare r record; c record; target text;
begin
  select * into r from erp_contract_reviews where company_id=p_company_id and id=p_review_id and not is_deleted for update;
  if r.id is null or r.data->>'status'<>'pending' then raise exception 'pending review not found'; end if;
  select * into c from erp_contracts where company_id=p_company_id and id=(r.data->>'contractId')::uuid for update;
  target:=case when p_accepted then 'pending_approval' else 'draft' end;
  update erp_contract_reviews set data=data||jsonb_build_object('status',case when p_accepted then 'accepted' else 'rejected' end,'comments',p_comments,'reviewedBy',p_reviewed_by,'reviewedAt',now()),updated_at=now() where company_id=p_company_id and id=p_review_id;
  update erp_contracts set data=data||jsonb_build_object('status',target,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=c.id;
  perform erp_contract_event(p_company_id,c.id,'review_completed',c.data->>'status',target,p_reviewed_by,p_comments);
end $$;

create or replace function public.erp_submit_cloud_contract_approval(p_company_id uuid,p_contract_id uuid,p_requested_by text)
returns uuid language plpgsql security definer set search_path=public as $$
declare c record; rid uuid:=gen_random_uuid();
begin
  select * into c from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted for update;
  if c.id is null or c.data->>'status'<>'pending_approval' then raise exception 'contract is not ready for approval'; end if;
  insert into erp_contract_approval_requests(company_id,id,data) values(p_company_id,rid,jsonb_build_object('contractId',p_contract_id,'status','pending','requestedBy',p_requested_by,'requestedAt',now()));
  return rid;
end $$;

create or replace function public.erp_decide_cloud_contract_approval(p_company_id uuid,p_request_id uuid,p_approve boolean,p_decided_by text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare r record; c record; target text;
begin
  select * into r from erp_contract_approval_requests where company_id=p_company_id and id=p_request_id and not is_deleted for update;
  if r.id is null or r.data->>'status'<>'pending' then raise exception 'pending approval not found'; end if;
  select * into c from erp_contracts where company_id=p_company_id and id=(r.data->>'contractId')::uuid for update;
  target:=case when p_approve then 'approved' else 'draft' end;
  update erp_contract_approval_requests set data=data||jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'decidedBy',p_decided_by,'reason',p_reason,'decidedAt',now()),updated_at=now() where company_id=p_company_id and id=p_request_id;
  update erp_contracts set data=data||jsonb_build_object('status',target,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=c.id;
  perform erp_contract_event(p_company_id,c.id,'approval_decided',c.data->>'status',target,p_decided_by,p_reason);
end $$;

create or replace function public.erp_request_cloud_contract_signature(p_company_id uuid,p_contract_id uuid,p_signer_name text,p_signer_role text,p_party_id text,p_signer_user_id text,p_requested_by text)
returns uuid language plpgsql security definer set search_path=public as $$
declare c record; rid uuid:=gen_random_uuid();
begin
  select * into c from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted for update;
  if c.id is null or c.data->>'status'<>'approved' then raise exception 'only approved contracts can be signed'; end if;
  insert into erp_contract_signature_requests(company_id,id,data) values(p_company_id,rid,jsonb_build_object('contractId',p_contract_id,'signerName',p_signer_name,'signerRole',p_signer_role,'partyId',p_party_id,'signerUserId',p_signer_user_id,'status','pending','requestedBy',p_requested_by,'requestedAt',now()));
  return rid;
end $$;

create or replace function public.erp_complete_cloud_contract_signature(p_company_id uuid,p_request_id uuid,p_signature_hash text,p_signed_by text)
returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  select * into r from erp_contract_signature_requests where company_id=p_company_id and id=p_request_id and not is_deleted for update;
  if r.id is null or r.data->>'status'<>'pending' then raise exception 'pending signature request not found'; end if;
  update erp_contract_signature_requests set data=data||jsonb_build_object('status','signed','signatureHash',p_signature_hash,'signedBy',p_signed_by,'signedAt',now()),updated_at=now() where company_id=p_company_id and id=p_request_id;
  if nullif(r.data->>'partyId','') is not null then update erp_contract_parties set data=data||jsonb_build_object('signatureHash',p_signature_hash,'signedAt',now()),updated_at=now() where company_id=p_company_id and id=(r.data->>'partyId')::uuid; end if;
  perform erp_contract_event(p_company_id,(r.data->>'contractId')::uuid,'signed',null,null,p_signed_by,r.data->>'signerName');
end $$;

create or replace function public.erp_reject_cloud_contract_signature(p_company_id uuid,p_request_id uuid,p_reason text,p_rejected_by text)
returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  select * into r from erp_contract_signature_requests where company_id=p_company_id and id=p_request_id and not is_deleted for update;
  if r.id is null or r.data->>'status'<>'pending' then raise exception 'pending signature request not found'; end if;
  update erp_contract_signature_requests set data=data||jsonb_build_object('status','rejected','reason',p_reason,'rejectedBy',p_rejected_by,'rejectedAt',now()),updated_at=now() where company_id=p_company_id and id=p_request_id;
  perform erp_contract_event(p_company_id,(r.data->>'contractId')::uuid,'signature_rejected',null,null,p_rejected_by,p_reason);
end $$;

create or replace function public.erp_list_cloud_pending_contract_reviews(p_company_id uuid,p_role_id text)
returns setof jsonb language sql security definer set search_path=public as $$
 select r.data||jsonb_build_object('id',r.id,'contractNumber',c.data->>'contractNumber','titleAr',c.data->>'titleAr','titleEn',c.data->>'titleEn')
 from erp_contract_reviews r join erp_contracts c on c.company_id=r.company_id and c.id=(r.data->>'contractId')::uuid
 where r.company_id=p_company_id and not r.is_deleted and r.data->>'status'='pending' and not c.is_deleted
 and (p_role_id is null or r.data->>'reviewerRoleId'=p_role_id) and erp_user_belongs_to_company(p_company_id)
 order by (r.data->>'requestedAt')::timestamptz desc;
$$;

create or replace function public.erp_renew_cloud_contract(p_company_id uuid,p_contract_id uuid,p_new_start_date timestamptz,p_new_end_date timestamptz,p_amount numeric,p_reason text,p_performed_by text)
returns uuid language plpgsql security definer set search_path=public as $$
declare c record; rid uuid:=gen_random_uuid(); n int;
begin
  select * into c from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted for update;
  if c.id is null or c.data->>'status' not in ('active','expired','suspended','approved') then raise exception 'contract cannot be renewed'; end if;
  select count(*)+1 into n from erp_contract_renewals where company_id=p_company_id and data->>'contractId'=p_contract_id::text and not is_deleted;
  insert into erp_contract_renewals(company_id,id,data) values(p_company_id,rid,jsonb_build_object('contractId',p_contract_id,'renewalNumber',n,'previousEndDate',c.data->>'endDate','newStartDate',p_new_start_date,'newEndDate',p_new_end_date,'amount',coalesce(p_amount,(c.data->>'totalAmount')::numeric,0),'currencyCode',coalesce(c.data->>'currencyCode','USD'),'reason',p_reason,'performedBy',p_performed_by,'performedAt',now()));
  update erp_contracts set data=data||jsonb_build_object('status','active','startDate',p_new_start_date,'endDate',p_new_end_date,'renewalDate',null,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=p_contract_id;
  perform erp_contract_event(p_company_id,p_contract_id,'renewed',c.data->>'status','active',p_performed_by,p_reason);
  return rid;
end $$;

create or replace function public.erp_run_cloud_contract_lifecycle(p_company_id uuid,p_reference_date timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ce int:=0; we int:=0; io int:=0; nc int:=0; r record;
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  for r in select * from erp_contracts where company_id=p_company_id and not is_deleted and data->>'status' in ('active','suspended') and nullif(data->>'endDate','') is not null and (data->>'endDate')::timestamptz<p_reference_date for update loop
    update erp_contracts set data=data||jsonb_build_object('status','expired','updatedAt',now()),updated_at=now() where company_id=p_company_id and id=r.id; ce:=ce+1;
    perform erp_contract_event(p_company_id,r.id,'expired',r.data->>'status','expired',null,'');
  end loop;
  update erp_contract_warranties set data=data||jsonb_build_object('status','expired','updatedAt',now()),updated_at=now() where company_id=p_company_id and not is_deleted and data->>'status'='active' and (data->>'endDate')::timestamptz<p_reference_date; get diagnostics we=row_count;
  update erp_contract_installment_schedule set data=data||jsonb_build_object('status','overdue','updatedAt',now()),updated_at=now() where company_id=p_company_id and not is_deleted and data->>'status' in ('pending','partial') and coalesce((data->>'remainingAmount')::numeric,0)>0 and (data->>'dueDate')::timestamptz<p_reference_date; get diagnostics io=row_count;
  insert into erp_contract_lifecycle_runs(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('runType','daily','referenceDate',p_reference_date,'status','completed','contractsExpired',ce,'warrantiesExpired',we,'installmentsOverdue',io,'notificationsCreated',nc,'completedAt',now()));
  return jsonb_build_object('contractsExpired',ce,'warrantiesExpired',we,'installmentsOverdue',io,'notificationsCreated',nc);
end $$;

-- Document operations.
create or replace function public.erp_create_cloud_document(p_company_id uuid,p_document jsonb,p_version jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare did uuid:=(p_document->>'id')::uuid;
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  insert into erp_document_records(company_id,id,data) values(p_company_id,did,p_document||jsonb_build_object('status','draft','currentVersion',1,'createdAt',now()));
  insert into erp_document_versions(company_id,id,data) values(p_company_id,(p_version->>'id')::uuid,p_version||jsonb_build_object('documentId',did,'versionNumber',1,'isCurrent',true,'createdAt',now()));
  insert into erp_document_events(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('documentId',did,'eventType','created','toStatus','draft','actorId',p_document->>'createdBy','description','Document created.','createdAt',now()));
  return did;
end $$;

create or replace function public.erp_add_cloud_document_version(p_company_id uuid,p_document_id uuid,p_version jsonb)
returns int language plpgsql security definer set search_path=public as $$
declare d record; n int;
begin
  select * into d from erp_document_records where company_id=p_company_id and id=p_document_id and not is_deleted for update;
  if d.id is null then raise exception 'document not found'; end if;
  if d.data->>'status'='cancelled' then raise exception 'cancelled documents cannot be versioned'; end if;
  n:=coalesce((d.data->>'currentVersion')::int,0)+1;
  update erp_document_versions set data=data||jsonb_build_object('isCurrent',false),updated_at=now() where company_id=p_company_id and data->>'documentId'=p_document_id::text and not is_deleted;
  insert into erp_document_versions(company_id,id,data) values(p_company_id,(p_version->>'id')::uuid,p_version||jsonb_build_object('documentId',p_document_id,'versionNumber',n,'isCurrent',true,'createdAt',now()));
  update erp_document_records set data=data||jsonb_build_object('currentVersion',n,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=p_document_id;
  insert into erp_document_events(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('documentId',p_document_id,'eventType','version_created','actorId',p_version->>'createdBy','description','Document version '||n||' created.','createdAt',now()));
  return n;
end $$;

create or replace function public.erp_link_cloud_document(p_company_id uuid,p_document_id uuid,p_link jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from erp_document_records where company_id=p_company_id and id=p_document_id and not is_deleted) then raise exception 'document not found'; end if;
  insert into erp_document_links(company_id,id,data) values(p_company_id,(p_link->>'id')::uuid,p_link||jsonb_build_object('documentId',p_document_id,'createdAt',now())) on conflict do nothing;
end $$;

create or replace function public.erp_grant_cloud_document_permission(p_company_id uuid,p_document_id uuid,p_permission jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare existing uuid;
begin
  select id into existing from erp_document_permissions where company_id=p_company_id and data->>'documentId'=p_document_id::text and data->>'principalType'=p_permission->>'principalType' and data->>'principalId'=p_permission->>'principalId' for update;
  if existing is null then insert into erp_document_permissions(company_id,id,data) values(p_company_id,(p_permission->>'id')::uuid,p_permission||jsonb_build_object('documentId',p_document_id,'grantedAt',now()));
  else update erp_document_permissions set data=p_permission||jsonb_build_object('documentId',p_document_id,'grantedAt',now()),is_deleted=false,deleted_at=null,updated_at=now() where company_id=p_company_id and id=existing; end if;
end $$;

create or replace function public.erp_transition_cloud_document(p_company_id uuid,p_document_id uuid,p_to_status text,p_actor_id text,p_description text)
returns void language plpgsql security definer set search_path=public as $$
declare d record; ok boolean:=false;
begin
  select * into d from erp_document_records where company_id=p_company_id and id=p_document_id and not is_deleted for update;
  if d.id is null then raise exception 'document not found'; end if;
  ok:=case d.data->>'status' when 'draft' then p_to_status in ('in_review','cancelled') when 'in_review' then p_to_status in ('approved','draft','cancelled') when 'approved' then p_to_status in ('active','archived','cancelled') when 'active' then p_to_status in ('archived','expired','cancelled') when 'expired' then p_to_status='archived' else false end;
  if not ok then raise exception 'invalid document transition'; end if;
  update erp_document_records set data=data||jsonb_build_object('status',p_to_status,'archivedAt',case when p_to_status='archived' then now() else data->'archivedAt' end,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=p_document_id;
  insert into erp_document_events(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('documentId',p_document_id,'eventType','status_changed','fromStatus',d.data->>'status','toStatus',p_to_status,'actorId',p_actor_id,'description',p_description,'createdAt',now()));
end $$;

create or replace function public.erp_search_cloud_documents(p_company_id uuid,p_query text,p_category_id text,p_status text,p_entity_type text,p_entity_id text,p_limit int)
returns setof jsonb language sql security definer set search_path=public as $$
 select d.data||jsonb_build_object(
   'id',d.id,
   'versionId',v.id,
   'fileName',v.data->>'fileName',
   'mimeType',v.data->>'mimeType',
   'fileSize',v.data->>'fileSize',
   'checksumSha256',v.data->>'checksumSha256',
   'versionNumber',v.data->>'versionNumber',
   'changeSummary',v.data->>'changeSummary'
 )
 from erp_document_records d
 left join lateral (
   select current_version.*
   from erp_document_versions current_version
   where current_version.company_id=d.company_id
     and current_version.data->>'documentId'=d.id::text
     and coalesce((current_version.data->>'isCurrent')::boolean,false)
     and not current_version.is_deleted
   order by coalesce(nullif(current_version.data->>'versionNumber','')::int,0) desc,
            current_version.updated_at desc,
            current_version.id desc
   limit 1
 ) v on true
 where d.company_id=p_company_id
   and not d.is_deleted
   and erp_user_belongs_to_company(p_company_id)
   and (
     coalesce(p_query,'')=''
     or d.data->>'documentNumber' ilike '%'||p_query||'%'
     or d.data->>'titleAr' ilike '%'||p_query||'%'
     or d.data->>'titleEn' ilike '%'||p_query||'%'
     or v.data->>'fileName' ilike '%'||p_query||'%'
     or v.data->>'extractedText' ilike '%'||p_query||'%'
   )
   and (p_category_id is null or d.data->>'categoryId'=p_category_id)
   and (p_status is null or d.data->>'status'=p_status)
   and (
     (p_entity_type is null and p_entity_id is null)
     or exists (
       select 1
       from erp_document_links l
       where l.company_id=d.company_id
         and l.data->>'documentId'=d.id::text
         and not l.is_deleted
         and (p_entity_type is null or l.data->>'entityType'=p_entity_type)
         and (p_entity_id is null or l.data->>'entityId'=p_entity_id)
     )
   )
 order by coalesce(nullif(d.data->>'createdAt','')::timestamptz,d.created_at) desc,
          d.created_at desc,
          d.id desc
 limit greatest(1,least(coalesce(p_limit,100),500));
$$;

create or replace function public.erp_get_cloud_document(p_company_id uuid,p_document_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select d.data||jsonb_build_object('id',d.id,'versionId',v.id,'fileName',v.data->>'fileName','mimeType',v.data->>'mimeType','fileSize',v.data->>'fileSize','checksumSha256',v.data->>'checksumSha256','versionNumber',v.data->>'versionNumber','changeSummary',v.data->>'changeSummary') from erp_document_records d left join erp_document_versions v on v.company_id=d.company_id and v.data->>'documentId'=d.id::text and coalesce((v.data->>'isCurrent')::boolean,false) and not v.is_deleted where d.company_id=p_company_id and d.id=p_document_id and not d.is_deleted and erp_user_belongs_to_company(p_company_id) limit 1;
$$;
create or replace function public.erp_list_cloud_document_versions(p_company_id uuid,p_document_id uuid) returns setof jsonb language sql security definer set search_path=public as $$ select data||jsonb_build_object('id',id) from erp_document_versions where company_id=p_company_id and data->>'documentId'=p_document_id::text and not is_deleted and erp_user_belongs_to_company(p_company_id) order by (data->>'versionNumber')::int desc $$;
create or replace function public.erp_list_cloud_document_permissions(p_company_id uuid,p_document_id uuid) returns setof jsonb language sql security definer set search_path=public as $$ select data||jsonb_build_object('id',id) from erp_document_permissions where company_id=p_company_id and data->>'documentId'=p_document_id::text and not is_deleted and erp_user_belongs_to_company(p_company_id) order by (data->>'grantedAt')::timestamptz desc $$;

create or replace function public.erp_sign_cloud_document_version(p_company_id uuid,p_document_id uuid,p_signature jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v uuid;
begin
  select id into v from erp_document_versions where company_id=p_company_id and data->>'documentId'=p_document_id::text and coalesce((data->>'isCurrent')::boolean,false) and not is_deleted for update;
  if v is null then raise exception 'current document version not found'; end if;
  insert into erp_document_signatures(company_id,id,data) values(p_company_id,(p_signature->>'id')::uuid,p_signature||jsonb_build_object('documentId',p_document_id,'versionId',v,'signedAt',now(),'verificationStatus','verified'));
end $$;

create or replace function public.erp_set_cloud_document_legal_hold(p_company_id uuid,p_document_id uuid,p_enabled boolean,p_actor_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  update erp_document_records set data=data||jsonb_build_object('legalHold',p_enabled,'updatedAt',now()),updated_at=now() where company_id=p_company_id and id=p_document_id and not is_deleted;
  if not found then raise exception 'document not found'; end if;
  insert into erp_document_events(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('documentId',p_document_id,'eventType',case when p_enabled then 'legal_hold_enabled' else 'legal_hold_disabled' end,'actorId',p_actor_id,'description','','createdAt',now()));
end $$;

-- Add phase 18 tables to realtime where available.
do $$ declare t text; begin foreach t in array array['erp_contracts','erp_contract_reviews','erp_contract_approval_requests','erp_contract_signature_requests','erp_document_records','erp_document_versions','erp_document_links'] loop begin execute format('alter publication supabase_realtime add table public.%I',t); exception when duplicate_object then null; end; end loop; end $$;

-- Private object storage for document binaries.
insert into storage.buckets(id,name,public,file_size_limit)
values('enterprise-documents','enterprise-documents',false,52428800)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;

drop policy if exists enterprise_documents_select on storage.objects;
create policy enterprise_documents_select on storage.objects for select to authenticated
using (bucket_id='enterprise-documents' and public.erp_user_belongs_to_company((storage.foldername(name))[1]::uuid));
drop policy if exists enterprise_documents_insert on storage.objects;
create policy enterprise_documents_insert on storage.objects for insert to authenticated
with check (bucket_id='enterprise-documents' and public.erp_user_belongs_to_company((storage.foldername(name))[1]::uuid));
drop policy if exists enterprise_documents_update on storage.objects;
create policy enterprise_documents_update on storage.objects for update to authenticated
using (bucket_id='enterprise-documents' and public.erp_user_belongs_to_company((storage.foldername(name))[1]::uuid))
with check (bucket_id='enterprise-documents' and public.erp_user_belongs_to_company((storage.foldername(name))[1]::uuid));

create or replace function public.erp_register_cloud_document_blob(p_company_id uuid,p_document_id uuid,p_version_id uuid,p_storage_path text,p_size_bytes bigint)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not erp_user_belongs_to_company(p_company_id) then raise exception 'company access denied'; end if;
  if not exists(select 1 from erp_document_records where company_id=p_company_id and id=p_document_id and not is_deleted) then raise exception 'document not found'; end if;
  update erp_document_versions set data=data||jsonb_build_object('storagePath',p_storage_path,'fileSize',p_size_bytes,'blobRegisteredAt',now()),updated_at=now()
  where company_id=p_company_id and id=p_version_id and data->>'documentId'=p_document_id::text and not is_deleted;
  if not found then raise exception 'document version not found'; end if;
end $$;

create or replace function public.erp_get_cloud_current_document_blob(p_company_id uuid,p_document_id uuid)
returns jsonb language sql security definer set search_path=public as $$
 select jsonb_build_object('versionId',v.id,'storagePath',v.data->>'storagePath','fileSize',v.data->>'fileSize')
 from erp_document_versions v where v.company_id=p_company_id and v.data->>'documentId'=p_document_id::text
 and coalesce((v.data->>'isCurrent')::boolean,false) and not v.is_deleted and erp_user_belongs_to_company(p_company_id) limit 1;
$$;
