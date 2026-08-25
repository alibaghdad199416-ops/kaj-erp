-- Phase 19: cloud-only contract master, document intelligence and generic approvals.
create table if not exists public.erp_contract_clauses (like public.erp_contracts including all);
create table if not exists public.erp_contract_links (like public.erp_contracts including all);
create table if not exists public.erp_document_processing_jobs (like public.erp_contracts including all);
create table if not exists public.erp_document_index_terms (like public.erp_contracts including all);
create table if not exists public.erp_document_duplicate_matches (like public.erp_contracts including all);
create table if not exists public.erp_document_governance_actions (like public.erp_contracts including all);
create table if not exists public.erp_workflow_definitions (like public.erp_contracts including all);
create table if not exists public.erp_workflow_steps (like public.erp_contracts including all);
create table if not exists public.erp_workflow_instances (like public.erp_contracts including all);
create table if not exists public.erp_approval_requests (like public.erp_contracts including all);

create index if not exists erp_contract_clause_version_idx on public.erp_contract_clauses(company_id,((data->>'contractVersionId')));
create index if not exists erp_contract_link_idx on public.erp_contract_links(company_id,((data->>'contractId')),((data->>'entityType')),((data->>'entityId')));
create index if not exists erp_doc_job_status_idx on public.erp_document_processing_jobs(company_id,((data->>'status')),created_at);
create index if not exists erp_doc_term_idx on public.erp_document_index_terms(company_id,((data->>'normalizedTerm')));
create index if not exists erp_approval_pending_idx on public.erp_approval_requests(company_id,((data->>'status')),((data->>'requestedRoleId')));

alter table public.erp_contract_clauses enable row level security;
alter table public.erp_contract_links enable row level security;
alter table public.erp_document_processing_jobs enable row level security;
alter table public.erp_document_index_terms enable row level security;
alter table public.erp_document_duplicate_matches enable row level security;
alter table public.erp_document_governance_actions enable row level security;
alter table public.erp_workflow_definitions enable row level security;
alter table public.erp_workflow_steps enable row level security;
alter table public.erp_workflow_instances enable row level security;
alter table public.erp_approval_requests enable row level security;

do $$ declare t text; begin
  foreach t in array array['erp_contract_clauses','erp_contract_links','erp_document_processing_jobs','erp_document_index_terms','erp_document_duplicate_matches','erp_document_governance_actions','erp_workflow_definitions','erp_workflow_steps','erp_workflow_instances','erp_approval_requests'] loop
    execute format('drop policy if exists tenant_access on public.%I',t);
    execute format('create policy tenant_access on public.%I for all using (erp_user_belongs_to_company(company_id)) with check (erp_user_belongs_to_company(company_id))',t);
  end loop;
end $$;

create or replace function public.erp_create_cloud_contract_master(p_company_id uuid,p_contract jsonb,p_initial_content jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare cid uuid:=coalesce((p_contract->>'id')::uuid,gen_random_uuid()); vid uuid:=gen_random_uuid(); n text:=trim(p_contract->>'contractNumber');
begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'unauthorized'; end if;
 if n is null or n='' then raise exception 'contract number required'; end if;
 if exists(select 1 from erp_contracts where company_id=p_company_id and data->>'contractNumber'=n and not is_deleted) then raise exception 'duplicate contract number'; end if;
 insert into erp_contracts(company_id,id,data) values(p_company_id,cid,p_contract||jsonb_build_object('status','draft','currentVersion',1,'createdAt',now()));
 insert into erp_contract_versions(company_id,id,data) values(p_company_id,vid,jsonb_build_object('contractId',cid,'versionNumber',1,'majorVersion',1,'minorVersion',0,'content',coalesce(p_initial_content,'{}'::jsonb),'changeSummary','Initial contract version','status','draft','createdBy',p_contract->>'createdBy','createdAt',now()));
 insert into erp_contract_events(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('contractId',cid,'eventType','created','toStatus','draft','performedBy',p_contract->>'createdBy','occurredAt',now()));
 return cid;
end $$;

create or replace function public.erp_add_cloud_contract_version(p_company_id uuid,p_contract_id uuid,p_content jsonb,p_change_summary text,p_created_by text,p_major boolean default false)
returns integer language plpgsql security definer set search_path=public as $$
declare c erp_contracts%rowtype; v erp_contract_versions%rowtype; vn int; maj int; minr int;
begin
 select * into c from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted for update;
 if not found or not erp_user_belongs_to_company(p_company_id) then raise exception 'contract not found'; end if;
 if c.data->>'status' in ('cancelled','terminated') then raise exception 'contract cannot be versioned'; end if;
 select * into v from erp_contract_versions where company_id=p_company_id and data->>'contractId'=p_contract_id::text and not is_deleted order by (data->>'versionNumber')::int desc limit 1;
 vn:=coalesce((v.data->>'versionNumber')::int,0)+1; maj:=coalesce((v.data->>'majorVersion')::int,1); minr:=coalesce((v.data->>'minorVersion')::int,0);
 if p_major then maj:=maj+1; minr:=0; else minr:=minr+1; end if;
 insert into erp_contract_versions(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('contractId',p_contract_id,'versionNumber',vn,'majorVersion',maj,'minorVersion',minr,'content',coalesce(p_content,'{}'::jsonb),'changeSummary',coalesce(p_change_summary,''),'status','draft','createdBy',p_created_by,'createdAt',now()));
 update erp_contracts set data=data||jsonb_build_object('currentVersion',vn,'updatedAt',now()),updated_at=now() where id=p_contract_id;
 return vn;
end $$;

create or replace function public.erp_add_cloud_contract_clause(p_company_id uuid,p_contract_id uuid,p_version_number int,p_clause jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare vid uuid;
begin
 select id into vid from erp_contract_versions where company_id=p_company_id and data->>'contractId'=p_contract_id::text and (data->>'versionNumber')::int=p_version_number and not is_deleted;
 if vid is null or not erp_user_belongs_to_company(p_company_id) then raise exception 'contract version not found'; end if;
 insert into erp_contract_clauses(company_id,id,data) values(p_company_id,coalesce((p_clause->>'id')::uuid,gen_random_uuid()),p_clause||jsonb_build_object('contractId',p_contract_id,'contractVersionId',vid,'createdAt',now()));
end $$;

create or replace function public.erp_link_cloud_contract_entity(p_company_id uuid,p_contract_id uuid,p_link jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from erp_contracts where company_id=p_company_id and id=p_contract_id and not is_deleted) or not erp_user_belongs_to_company(p_company_id) then raise exception 'contract not found'; end if;
 if not exists(select 1 from erp_contract_links where company_id=p_company_id and data->>'contractId'=p_contract_id::text and data->>'entityType'=p_link->>'entityType' and data->>'entityId'=p_link->>'entityId' and not is_deleted) then
  insert into erp_contract_links(company_id,id,data) values(p_company_id,coalesce((p_link->>'id')::uuid,gen_random_uuid()),p_link||jsonb_build_object('contractId',p_contract_id,'createdAt',now()));
 end if;
end $$;

create or replace function public.erp_search_cloud_contracts(p_company_id uuid,p_query text default '',p_status text default null,p_contract_type text default null)
returns setof jsonb language sql security definer set search_path=public as $$
 select data||jsonb_build_object('id',id) from erp_contracts where company_id=p_company_id and not is_deleted and erp_user_belongs_to_company(p_company_id)
 and (coalesce(p_query,'')='' or data->>'contractNumber' ilike '%'||p_query||'%' or data->>'titleAr' ilike '%'||p_query||'%' or data->>'titleEn' ilike '%'||p_query||'%')
 and (p_status is null or data->>'status'=p_status) and (p_contract_type is null or data->>'contractType'=p_contract_type) order by created_at desc $$;

create or replace function public.erp_enqueue_cloud_document_processing(p_company_id uuid,p_document_id uuid,p_job_type text,p_engine text,p_language_hints text,p_requested_by text)
returns uuid language plpgsql security definer set search_path=public as $$
declare vid uuid; jid uuid:=gen_random_uuid();
begin
 select id into vid from erp_document_versions where company_id=p_company_id and data->>'documentId'=p_document_id::text and coalesce((data->>'isCurrent')::boolean,false) and not is_deleted;
 if vid is null or not erp_user_belongs_to_company(p_company_id) then raise exception 'current version not found'; end if;
 insert into erp_document_processing_jobs(company_id,id,data) values(p_company_id,jid,jsonb_build_object('documentId',p_document_id,'versionId',vid,'jobType',p_job_type,'status','pending','engine',p_engine,'languageHints',p_language_hints,'attempts',0,'requestedBy',p_requested_by,'requestedAt',now())); return jid;
end $$;

create or replace function public.erp_complete_cloud_document_extraction(p_company_id uuid,p_job_id uuid,p_extracted_text text,p_metadata jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare j erp_document_processing_jobs%rowtype; term text; freq int;
begin
 select * into j from erp_document_processing_jobs where company_id=p_company_id and id=p_job_id and not is_deleted for update;
 if not found or not erp_user_belongs_to_company(p_company_id) then raise exception 'job not found'; end if;
 update erp_document_versions set data=data||jsonb_build_object('extractedText',p_extracted_text),updated_at=now() where id=(j.data->>'versionId')::uuid;
 update erp_document_index_terms set is_deleted=true,deleted_at=now() where company_id=p_company_id and data->>'versionId'=j.data->>'versionId' and not is_deleted;
 for term,freq in select x,count(*) from regexp_split_to_table(lower(coalesce(p_extracted_text,'')),'[^[:alnum:]ء-ي]+') x where length(x)>1 group by x loop
  insert into erp_document_index_terms(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('documentId',j.data->>'documentId','versionId',j.data->>'versionId','term',term,'normalizedTerm',term,'frequency',freq,'source','extracted_text','createdAt',now()));
 end loop;
 update erp_document_processing_jobs set data=data||jsonb_build_object('status','completed','completedAt',now(),'metadata',coalesce(p_metadata,'{}'::jsonb),'errorMessage',''),updated_at=now() where id=p_job_id;
 insert into erp_document_duplicate_matches(company_id,id,data)
 select p_company_id,gen_random_uuid(),jsonb_build_object('sourceDocumentId',j.data->>'documentId','sourceVersionId',j.data->>'versionId','matchedDocumentId',v2.data->>'documentId','matchedVersionId',v2.id,'matchType','sha256','confidence',1.0,'status','detected','detectedAt',now())
 from erp_document_versions v1 join erp_document_versions v2 on v2.company_id=v1.company_id and v2.id<>v1.id and v2.data->>'checksumSha256'=v1.data->>'checksumSha256' where v1.id=(j.data->>'versionId')::uuid;
end $$;

create or replace function public.erp_fail_cloud_document_processing(p_company_id uuid,p_job_id uuid,p_error text) returns void language plpgsql security definer set search_path=public as $$
begin update erp_document_processing_jobs set data=data||jsonb_build_object('status','failed','attempts',coalesce((data->>'attempts')::int,0)+1,'completedAt',now(),'errorMessage',p_error),updated_at=now() where company_id=p_company_id and id=p_job_id and erp_user_belongs_to_company(p_company_id); end $$;

create or replace function public.erp_run_cloud_document_governance(p_company_id uuid,p_reference_date timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$ declare ex int:=0; begin
 if not erp_user_belongs_to_company(p_company_id) then raise exception 'unauthorized'; end if;
 update erp_document_records set data=data||jsonb_build_object('status','expired','updatedAt',now()),updated_at=now() where company_id=p_company_id and data->>'status'='active' and nullif(data->>'expiryDate','')::timestamptz<p_reference_date and not is_deleted; get diagnostics ex=row_count;
 return jsonb_build_object('expired',ex,'archived',0,'scheduled',0); end $$;

create or replace function public.erp_list_cloud_document_processing_jobs(p_company_id uuid,p_limit int default 50) returns setof jsonb language sql security definer set search_path=public as $$ select data||jsonb_build_object('id',id) from erp_document_processing_jobs where company_id=p_company_id and data->>'status' in ('pending','failed') and not is_deleted and erp_user_belongs_to_company(p_company_id) order by created_at limit greatest(1,least(p_limit,500)) $$;
create or replace function public.erp_list_cloud_document_duplicates(p_company_id uuid,p_document_id uuid) returns setof jsonb language sql security definer set search_path=public as $$ select data||jsonb_build_object('id',id) from erp_document_duplicate_matches where company_id=p_company_id and (data->>'sourceDocumentId'=p_document_id::text or data->>'matchedDocumentId'=p_document_id::text) and not is_deleted and erp_user_belongs_to_company(p_company_id) order by created_at desc $$;

create or replace function public.erp_submit_cloud_generic_approval(p_company_id uuid,p_document_id uuid,p_workflow_code text,p_requested_by text)
returns uuid language plpgsql security definer set search_path=public as $$
declare d erp_document_records%rowtype; w erp_workflow_definitions%rowtype; s erp_workflow_steps%rowtype; iid uuid:=gen_random_uuid(); rid uuid:=gen_random_uuid();
begin
 select * into d from erp_document_records where company_id=p_company_id and id=p_document_id and not is_deleted for update;
 if not found or not erp_user_belongs_to_company(p_company_id) then raise exception 'document not found'; end if;
 if d.data->>'status'<>'draft' then raise exception 'only draft documents can be submitted'; end if;
 select * into w from erp_workflow_definitions where company_id=p_company_id and data->>'code'=p_workflow_code and coalesce((data->>'isActive')::boolean,true) and not is_deleted limit 1;
 if not found then raise exception 'workflow not found'; end if;
 select * into s from erp_workflow_steps where company_id=p_company_id and data->>'workflowId'=w.id::text and not is_deleted order by (data->>'stepOrder')::int limit 1;
 if not found then raise exception 'workflow has no steps'; end if;
 insert into erp_workflow_instances(company_id,id,data) values(p_company_id,iid,jsonb_build_object('workflowId',w.id,'documentId',p_document_id,'status','running','currentStepOrder',s.data->>'stepOrder','startedBy',p_requested_by,'startedAt',now()));
 insert into erp_approval_requests(company_id,id,data) values(p_company_id,rid,jsonb_build_object('instanceId',iid,'documentId',p_document_id,'stepId',s.id,'status','pending','requestedRoleId',s.data->>'requiredRoleId','requestedBy',p_requested_by,'requestedAt',now()));
 update erp_document_records set data=data||jsonb_build_object('status','pending_approval'),updated_at=now() where id=p_document_id; return rid;
end $$;

create or replace function public.erp_decide_cloud_generic_approval(p_company_id uuid,p_request_id uuid,p_approve boolean,p_decided_by text,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare r erp_approval_requests%rowtype; i erp_workflow_instances%rowtype; s erp_workflow_steps%rowtype; ns erp_workflow_steps%rowtype;
begin
 select * into r from erp_approval_requests where company_id=p_company_id and id=p_request_id and data->>'status'='pending' and not is_deleted for update;
 if not found or not erp_user_belongs_to_company(p_company_id) then raise exception 'pending request not found'; end if;
 select * into i from erp_workflow_instances where id=(r.data->>'instanceId')::uuid for update;
 update erp_approval_requests set data=data||jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'decidedBy',p_decided_by,'decidedAt',now(),'decisionReason',p_reason),updated_at=now() where id=p_request_id;
 if not p_approve then
  update erp_workflow_instances set data=data||jsonb_build_object('status','rejected','completedAt',now()),updated_at=now() where id=i.id;
  update erp_document_records set data=data||jsonb_build_object('status','draft','approvedBy',null,'approvedAt',null),updated_at=now() where id=(r.data->>'documentId')::uuid; return;
 end if;
 select * into s from erp_workflow_steps where id=(r.data->>'stepId')::uuid;
 select * into ns from erp_workflow_steps where company_id=p_company_id and data->>'workflowId'=i.data->>'workflowId' and (data->>'stepOrder')::int>(s.data->>'stepOrder')::int and not is_deleted order by (data->>'stepOrder')::int limit 1;
 if found then
  update erp_workflow_instances set data=data||jsonb_build_object('currentStepOrder',ns.data->>'stepOrder'),updated_at=now() where id=i.id;
  insert into erp_approval_requests(company_id,id,data) values(p_company_id,gen_random_uuid(),jsonb_build_object('instanceId',i.id,'documentId',r.data->>'documentId','stepId',ns.id,'status','pending','requestedRoleId',ns.data->>'requiredRoleId','requestedBy',r.data->>'requestedBy','requestedAt',now()));
 else
  update erp_workflow_instances set data=data||jsonb_build_object('status','completed','completedAt',now()),updated_at=now() where id=i.id;
  update erp_document_records set data=data||jsonb_build_object('status','approved','approvedBy',p_decided_by,'approvedAt',now()),updated_at=now() where id=(r.data->>'documentId')::uuid;
 end if;
end $$;

create or replace function public.erp_list_cloud_pending_approvals(p_company_id uuid,p_role_id text) returns setof jsonb language sql security definer set search_path=public as $$
 select r.data||jsonb_build_object('id',r.id,'documentNumber',d.data->>'documentNumber','module',d.data->>'module','documentType',d.data->>'documentType','totalAmount',d.data->>'totalAmount','currencyCode',d.data->>'currencyCode')
 from erp_approval_requests r join erp_document_records d on d.company_id=r.company_id and d.id=(r.data->>'documentId')::uuid
 where r.company_id=p_company_id and r.data->>'status'='pending' and (r.data->>'requestedRoleId'=p_role_id or nullif(r.data->>'requestedRoleId','') is null) and not r.is_deleted and erp_user_belongs_to_company(p_company_id) order by r.created_at $$;

do $$ declare t text; begin foreach t in array array['erp_contract_clauses','erp_contract_links','erp_document_processing_jobs','erp_document_duplicate_matches','erp_workflow_instances','erp_approval_requests'] loop begin execute format('alter publication supabase_realtime add table public.%I',t); exception when duplicate_object then null; end; end loop; end $$;
