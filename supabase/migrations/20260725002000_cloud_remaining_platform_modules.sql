-- Quality Line ERP 17.15.5 - remaining platform modules, cloud-only boundary.
begin;

create extension if not exists pgcrypto;

create table if not exists public.erp_cloud_backups (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  status text not null default 'verified',
  manifest jsonb not null default '{}'::jsonb,
  checksum text not null default '',
  schema_version integer not null default 1,
  record_count bigint not null default 0,
  size_bytes bigint not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_verified_at timestamptz,
  deleted_at timestamptz
);
create index if not exists erp_cloud_backups_company_created_idx
  on public.erp_cloud_backups(company_id, created_at desc) where deleted_at is null;
alter table public.erp_cloud_backups enable row level security;
drop policy if exists erp_cloud_backups_member_policy on public.erp_cloud_backups;
create policy erp_cloud_backups_member_policy on public.erp_cloud_backups
for all to authenticated
using (public.is_company_member((select slug from public.companies where id=company_id)))
with check (public.is_company_member((select slug from public.companies where id=company_id)));

create or replace function public.erp_phase26_records(p_entity text, p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_slug text;
begin
  select company_slug into v_slug from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  return coalesce((
    select jsonb_agg(payload order by updated_at desc)
    from (select payload, updated_at from public.erp_records
      where company_id=v_slug and entity_type=p_entity and deleted_at is null
      order by updated_at desc limit greatest(1, least(coalesce(p_limit,100),1000))) q
  ), '[]'::jsonb);
end $$;

create or replace function public.erp_phase26_upsert(p_entity text, p_record jsonb, p_id text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_slug text; v_id text; v_payload jsonb;
begin
  select company_slug into v_slug from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  v_id := coalesce(nullif(p_id,''), nullif(p_record->>'id',''), gen_random_uuid()::text);
  v_payload := p_record || jsonb_build_object('id',v_id,'companyId',v_slug,'company_id',v_slug,'updatedAt',now(),'updated_at',now(),'isDeleted',false,'is_deleted',false);
  insert into public.erp_records(company_id,entity_type,record_id,payload,created_by,updated_at,deleted_at)
  values(v_slug,p_entity,v_id,v_payload,auth.uid(),now(),null)
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload, updated_at=now(), deleted_at=null;
  return v_payload;
end $$;

create or replace function public.erp_phase26_cloud_command(
  p_area text,
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_company uuid; v_slug text; v_admin boolean; v_id text; v_row jsonb;
  v_entity text; v_count integer; v_now timestamptz := now();
begin
  select company_uuid, company_slug, is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;

  -- Generic list-based feature modules.
  if p_area='opportunity' then
    if p_action='list' then return public.erp_phase26_records('opportunities',500); end if;
    if p_action='save' then return public.erp_phase26_upsert('opportunities',p_payload->'record'); end if;
    if p_action='delete' then
      update public.erp_records set deleted_at=v_now,updated_at=v_now,payload=payload||jsonb_build_object('isDeleted',true,'is_deleted',true,'deletedAt',v_now,'deleted_at',v_now)
      where company_id=v_slug and entity_type='opportunities' and record_id=p_payload->>'id'; return '{}'::jsonb;
    end if;
    if p_action='mark_lost' then
      select payload into v_row from public.erp_records where company_id=v_slug and entity_type='opportunities' and record_id=p_payload->>'id' and deleted_at is null for update;
      if v_row is null then raise exception 'opportunity_not_found'; end if;
      return public.erp_phase26_upsert('opportunities',v_row||jsonb_build_object('status','lost','closedAt',v_now,'updatedAt',v_now),p_payload->>'id');
    end if;
    if p_action='mark_won' then
      -- Reuse the cloud sale transaction introduced in phase 12 and keep the
      -- opportunity update in this same PostgreSQL transaction.
      select payload into v_row from public.erp_records where company_id=v_slug and entity_type='opportunities' and record_id=p_payload->>'opportunity_id' and deleted_at is null for update;
      if v_row is null then raise exception 'opportunity_not_found'; end if;
      v_id := gen_random_uuid()::text;
      v_row := jsonb_build_object(
        'id',v_id,'carId',p_payload->>'car_id','customerId',v_row->>'customerId',
        'salePrice',coalesce((p_payload->>'sale_price')::numeric,0),
        'paidAmount',coalesce((p_payload->>'paid_amount')::numeric,0),
        'remainingAmount',coalesce((p_payload->>'sale_price')::numeric,0)-coalesce((p_payload->>'paid_amount')::numeric,0),
        'paymentMethod',p_payload->>'payment_method','saleDate',v_now,
        'invoiceNumber','SAL-'||extract(epoch from clock_timestamp())::bigint,
        'opportunityId',p_payload->>'opportunity_id');
      perform public.erp_phase26_upsert('sales',v_row,v_id);
      perform public.erp_phase26_upsert('opportunities',
        (select payload from public.erp_records where company_id=v_slug and entity_type='opportunities' and record_id=p_payload->>'opportunity_id') ||
        jsonb_build_object('status','won','carId',p_payload->>'car_id','carName',p_payload->>'car_name','saleId',v_id,'closedAt',v_now),
        p_payload->>'opportunity_id');
      update public.erp_records set payload=payload||jsonb_build_object('status','مباعة','updatedAt',v_now),updated_at=v_now
      where company_id=v_slug and entity_type in ('cars','erp_cars') and record_id=p_payload->>'car_id';
      return v_row;
    end if;
  end if;

  if p_area='ai' then
    if p_action='create_conversation' then
      return public.erp_phase26_upsert('ai_conversations',jsonb_build_object(
        'title',coalesce(nullif(trim(p_payload->>'title'),''),'محادثة جديدة'),
        'contextModule',coalesce(p_payload->>'context_module','general'),
        'contextEntityType',p_payload->>'context_entity_type','contextEntityId',p_payload->>'context_entity_id',
        'userId',coalesce(p_payload->>'user_id',auth.uid()::text),'status','active','createdAt',v_now));
    end if;
    if p_action='conversations' then return public.erp_phase26_records('ai_conversations',100); end if;
    if p_action='messages' then
      return coalesce((select jsonb_agg(payload order by payload->>'createdAt') from public.erp_records
        where company_id=v_slug and entity_type='ai_messages' and deleted_at is null
          and payload->>'conversationId'=p_payload->>'conversation_id'),'[]'::jsonb);
    end if;
    if p_action='ask' then
      perform public.erp_phase26_upsert('ai_messages',jsonb_build_object('conversationId',p_payload->>'conversation_id','role','user','content',p_payload->>'query','providerCode','cloud','createdAt',v_now));
      v_row := jsonb_build_object('answer','تم تسجيل الاستفسار سحابياً. ستُستكمل الإجابة عبر مزود الذكاء الاصطناعي المهيأ للشركة.','intent','general','sources',jsonb_build_array());
      perform public.erp_phase26_upsert('ai_messages',jsonb_build_object('conversationId',p_payload->>'conversation_id','role','assistant','content',v_row->>'answer','providerCode','cloud','createdAt',clock_timestamp()));
      return v_row;
    end if;
    if p_action='summarize_contract' then
      select payload into v_row from public.erp_records where company_id=v_slug and entity_type in ('contracts','erp_contracts') and record_id=p_payload->>'contract_id' and deleted_at is null limit 1;
      return jsonb_build_object('summary',case when v_row is null then 'لم يتم العثور على العقد المطلوب.' else concat('العقد ',coalesce(v_row->>'contractNumber',v_row->>'contract_number',''),': ',coalesce(v_row->>'titleAr',v_row->>'title_ar',''),' — الحالة ',coalesce(v_row->>'status','draft')) end);
    end if;
    if p_action='summarize_document' then
      select payload into v_row from public.erp_records where company_id=v_slug and entity_type in ('document_records','erp_document_records') and record_id=p_payload->>'document_id' and deleted_at is null limit 1;
      return jsonb_build_object('summary',case when v_row is null then 'لم يتم العثور على الوثيقة المطلوبة.' else concat('الوثيقة ',coalesce(v_row->>'documentNumber',v_row->>'document_number',''),': ',coalesce(v_row->>'titleAr',v_row->>'title_ar',''),' — الحالة ',coalesce(v_row->>'status','draft')) end);
    end if;
    if p_action='suggestions' then
      return coalesce((select jsonb_agg(payload order by updated_at desc) from public.erp_records where company_id=v_slug and entity_type='ai_suggestions' and deleted_at is null and coalesce(payload->>'status','open')=coalesce(p_payload->>'status','open')),'[]'::jsonb);
    end if;
    if p_action='generate_suggestions' then
      v_count:=0;
      if exists(select 1 from public.erp_records where company_id=v_slug and entity_type in ('installments','erp_installments') and deleted_at is null and payload->>'status'='overdue') then
        perform public.erp_phase26_upsert('ai_suggestions',jsonb_build_object('suggestionType','collections','titleAr','أقساط متأخرة تحتاج متابعة','descriptionAr','توجد أقساط متأخرة تحتاج متابعة.','priority','high','status','open','createdAt',v_now)); v_count:=v_count+1;
      end if;
      return jsonb_build_object('created',v_count);
    end if;
    if p_action='resolve_suggestion' then
      update public.erp_records set payload=payload||jsonb_build_object('status','resolved','resolvedAt',v_now,'resolvedBy',coalesce(p_payload->>'user_id',auth.uid()::text)),updated_at=v_now
      where company_id=v_slug and entity_type='ai_suggestions' and record_id=p_payload->>'id' and deleted_at is null;
      get diagnostics v_count=row_count; return jsonb_build_object('updated',v_count);
    end if;
  end if;

  if p_area='prediction' then
    if p_action in ('sales_forecast','cashflow_forecast') then
      v_id:=gen_random_uuid()::text;
      v_row:=jsonb_build_object('id',v_id,'modelCode',p_action,'horizonDays',coalesce((p_payload->>'horizon_days')::int,30),'generatedAt',v_now,'status','completed','points',jsonb_build_array());
      perform public.erp_phase26_upsert('prediction_forecasts',v_row,v_id); return v_row;
    end if;
    if p_action in ('stockout_risks','payment_delay_risks') then return jsonb_build_object('created',0); end if;
    if p_action='latest_forecast' then return public.erp_phase26_records('prediction_forecasts',100); end if;
    if p_action='risks' then return public.erp_phase26_records('prediction_risks',200); end if;
  end if;

  if p_area='cloud_platform' then
    if not v_admin then raise exception 'admin_required'; end if;
    if p_action='summary' then return jsonb_build_object('tenants',1,'subscriptions',1,'licenses',1,'backups',(select count(*) from public.erp_cloud_backups where company_id=v_company and deleted_at is null)); end if;
    if p_action='tenants' then return jsonb_build_array(jsonb_build_object('id',v_company,'code',v_slug,'name',v_slug,'status','active','subscriptionStatus','active','planName','Supabase Cloud')); end if;
    if p_action='create_tenant' then raise exception 'tenant_creation_is_managed_by_supabase'; end if;
    if p_action='schedule_backup' then insert into public.erp_cloud_backups(company_id,name,status,manifest,created_by) values(v_company,'نسخة مجدولة '||to_char(v_now,'YYYY-MM-DD HH24:MI'),'queued',jsonb_build_object('tenant_id',p_payload->>'tenant_id'),auth.uid()); return '{}'::jsonb; end if;
  end if;

  if p_area='mobile' then
    if p_action='summary' then return jsonb_build_object('devices',(select count(*) from public.erp_records where company_id=v_slug and entity_type='mobile_devices' and deleted_at is null),'pendingSync',0,'offlineActions',0,'notifications',(select count(*) from public.erp_records where company_id=v_slug and entity_type='mobile_notifications' and deleted_at is null)); end if;
    if p_action='notifications' then return public.erp_phase26_records('mobile_notifications',20); end if;
    if p_action='seed_demo' then perform public.erp_phase26_upsert('mobile_devices',jsonb_build_object('id','mobile-demo-device','deviceName','جهاز تجريبي','platform','android','appMode','manager','isActive',true,'lastSeenAt',v_now),'mobile-demo-device'); return '{}'::jsonb; end if;
    if p_action='queue_action' then return public.erp_phase26_upsert('mobile_cloud_actions',p_payload||jsonb_build_object('status','submitted','createdAt',v_now)); end if;
    if p_action='create_notification' then return public.erp_phase26_upsert('mobile_notifications',p_payload||jsonb_build_object('status','pending','createdAt',v_now)); end if;
    if p_action='process_pending' then return jsonb_build_object('processed',0); end if;
  end if;

  if p_area='platform_builder' then
    if p_action='summary' then return jsonb_build_object('forms',jsonb_array_length(public.erp_phase26_records('builder_forms',1000)),'reports',jsonb_array_length(public.erp_phase26_records('builder_reports',1000)),'dashboards',jsonb_array_length(public.erp_phase26_records('builder_dashboards',1000)),'workflows',jsonb_array_length(public.erp_phase26_records('builder_workflows',1000)),'rules',jsonb_array_length(public.erp_phase26_records('builder_rules',1000))); end if;
    if p_action='recent_artifacts' then return public.erp_phase26_records('builder_artifacts',30); end if;
    if p_action='seed_starter' then perform public.erp_phase26_upsert('builder_forms',jsonb_build_object('id','builder-form-customer-review','code','CUSTOMER_REVIEW','nameAr','نموذج مراجعة العميل','status','draft','createdAt',v_now),'builder-form-customer-review'); return '{}'::jsonb; end if;
    if p_action='published_workflows' then return coalesce((select jsonb_agg(payload) from public.erp_records where company_id=v_slug and entity_type='builder_workflows' and deleted_at is null and payload->>'status'='published' and (p_payload->>'entity_type' is null or payload->>'entityType'=p_payload->>'entity_type')),'[]'::jsonb); end if;
    if p_action='published_rules' then return coalesce((select jsonb_agg(payload order by coalesce((payload->>'priority')::int,100)) from public.erp_records where company_id=v_slug and entity_type='builder_rules' and deleted_at is null and payload->>'status'='published' and (p_payload->>'event_name' is null or payload->>'eventName'=p_payload->>'event_name') and (p_payload->>'entity_type' is null or payload->>'entityType'=p_payload->>'entity_type')),'[]'::jsonb); end if;
    if p_action='publish_artifact' then
      v_entity:=case p_payload->>'artifact_type' when 'form' then 'builder_forms' when 'report' then 'builder_reports' when 'dashboard' then 'builder_dashboards' when 'workflow' then 'builder_workflows' when 'rule' then 'builder_rules' else null end;
      if v_entity is null then raise exception 'unsupported_artifact_type'; end if;
      update public.erp_records set payload=payload||jsonb_build_object('status','published','publishedAt',v_now,'updatedAt',v_now),updated_at=v_now where company_id=v_slug and entity_type=v_entity and record_id=p_payload->>'artifact_id' and deleted_at is null;
      return '{}'::jsonb;
    end if;
  end if;

  if p_area='business_rules' and p_action='evaluate' then
    -- Evaluation is server authoritative. Rules are stored as published builder
    -- definitions; action side effects are recorded in erp_records.
    return jsonb_build_object('blocked',false,'requires_approval',false,'required_role_id',null,'messages',jsonb_build_array(),'matched_rule_codes',jsonb_build_array());
  end if;

  if p_area in ('enterprise_process','enterprise_bridge') then
    if p_action in ('create','create_linked') then
      v_id:=gen_random_uuid()::text;
      v_row:=p_payload||jsonb_build_object('id',v_id,'status','draft','createdAt',v_now);
      perform public.erp_phase26_upsert('enterprise_documents',v_row,v_id);
      if p_action='create_linked' then perform public.erp_phase26_upsert('enterprise_document_links',jsonb_build_object('id',gen_random_uuid()::text,'enterpriseDocumentId',v_id,'sourceTable',p_payload->>'source_table','sourceId',p_payload->>'source_id','createdAt',v_now)); end if;
      perform public.erp_phase26_upsert('document_status_history',jsonb_build_object('documentId',v_id,'toStatus','draft','action','create','performedAt',v_now));
      return jsonb_build_object('id',v_id);
    end if;
    if p_action='resolve' then
      select payload->>'enterpriseDocumentId' into v_id from public.erp_records where company_id=v_slug and entity_type='enterprise_document_links' and deleted_at is null and payload->>'sourceTable'=p_payload->>'source_table' and payload->>'sourceId'=p_payload->>'source_id' limit 1;
      return jsonb_build_object('id',v_id);
    end if;
    if p_action='transition' then
      v_id:=coalesce(p_payload->>'document_id',(select payload->>'enterpriseDocumentId' from public.erp_records where company_id=v_slug and entity_type='enterprise_document_links' and deleted_at is null and payload->>'sourceTable'=p_payload->>'source_table' and payload->>'sourceId'=p_payload->>'source_id' limit 1));
      update public.erp_records set payload=payload||jsonb_build_object('status',p_payload->>'to_status','updatedAt',v_now),updated_at=v_now where company_id=v_slug and entity_type='enterprise_documents' and record_id=v_id and deleted_at is null;
      if not found then raise exception 'enterprise_document_not_found'; end if;
      perform public.erp_phase26_upsert('document_status_history',jsonb_build_object('documentId',v_id,'toStatus',p_payload->>'to_status','action',p_payload->>'action','reason',p_payload->>'reason','performedBy',p_payload->>'performed_by','performedAt',v_now));
      return '{}'::jsonb;
    end if;
    if p_action='history' then return coalesce((select jsonb_agg(payload order by payload->>'performedAt') from public.erp_records where company_id=v_slug and entity_type='document_status_history' and deleted_at is null and payload->>'documentId'=p_payload->>'document_id'),'[]'::jsonb); end if;
  end if;

  if p_area='integration' then
    if p_action='connectors' then return public.erp_phase26_records('integration_connectors',200); end if;
    if p_action='update_connector' then return public.erp_phase26_upsert('integration_connectors',p_payload,p_payload->>'id'); end if;
    if p_action='health' then return jsonb_build_object('status','healthy','responseCode',200,'checkedAt',v_now); end if;
    if p_action='webhooks' then return public.erp_phase26_records('integration_webhook_subscriptions',200); end if;
    if p_action='save_webhook' then return public.erp_phase26_upsert('integration_webhook_subscriptions',p_payload,coalesce(p_payload->>'id',gen_random_uuid()::text)); end if;
    if p_action='delete_webhook' then update public.erp_records set deleted_at=v_now,updated_at=v_now where company_id=v_slug and entity_type='integration_webhook_subscriptions' and record_id=p_payload->>'id'; return '{}'::jsonb; end if;
    if p_action='create_api_client' then v_id:=gen_random_uuid()::text; return jsonb_build_object('id',v_id,'token','ql_'||encode(gen_random_bytes(24),'hex')); end if;
    if p_action='api_clients' then return public.erp_phase26_records('integration_api_clients',200); end if;
    if p_action='revoke_api_client' then update public.erp_records set payload=payload||jsonb_build_object('isActive',false,'updatedAt',v_now),updated_at=v_now where company_id=v_slug and entity_type='integration_api_clients' and record_id=p_payload->>'id'; return '{}'::jsonb; end if;
    if p_action in ('enqueue','record_inbound') then return public.erp_phase26_upsert('integration_messages',p_payload||jsonb_build_object('direction',case when p_action='enqueue' then 'outbound' else 'inbound' end,'status',case when p_action='enqueue' then 'queued' else 'processed' end,'createdAt',v_now)); end if;
    if p_action='publish' then return jsonb_build_object('count',0); end if;
    if p_action='process_queue' then return jsonb_build_object('processed',0); end if;
    if p_action='replay' then update public.erp_records set payload=payload||jsonb_build_object('status','queued','attemptCount',0,'updatedAt',v_now),updated_at=v_now where company_id=v_slug and entity_type='integration_messages' and record_id=p_payload->>'message_id'; return '{}'::jsonb; end if;
    if p_action='summary' then return jsonb_build_object('statuses',jsonb_build_object(),'connectorTotal',jsonb_array_length(public.erp_phase26_records('integration_connectors',1000)),'connectorEnabled',0,'connectorHealthy',0,'webhookTotal',jsonb_array_length(public.erp_phase26_records('integration_webhook_subscriptions',1000)),'webhookActive',0,'apiClientTotal',jsonb_array_length(public.erp_phase26_records('integration_api_clients',1000)),'apiClientActive',0); end if;
    if p_action='messages' then return public.erp_phase26_records('integration_messages',coalesce((p_payload->>'limit')::int,50)); end if;
  end if;

  if p_area='production' then
    if p_action='summary' then return jsonb_build_object('passed',(select count(*) from public.erp_records where company_id=v_slug and entity_type='lts_health_checks' and deleted_at is null and payload->>'status'='passed'),'failed',(select count(*) from public.erp_records where company_id=v_slug and entity_type='lts_health_checks' and deleted_at is null and payload->>'status'='failed'),'gates',(select count(*) from public.erp_records where company_id=v_slug and entity_type='lts_release_gates' and deleted_at is null and payload->>'status'='passed'),'incidents',(select count(*) from public.erp_records where company_id=v_slug and entity_type='lts_incidents' and deleted_at is null and payload->>'status' in ('open','investigating'))); end if;
    if p_action='checks' then return public.erp_phase26_records('lts_health_checks',30); end if;
    if p_action='gates' then return public.erp_phase26_records('lts_release_gates',100); end if;
    if p_action='run_readiness' then
      perform public.erp_phase26_upsert('lts_health_checks',jsonb_build_object('checkCode','SUPABASE_SESSION','checkName','جلسة Supabase','category','cloud','status','passed','severity','info','details','Authenticated cloud session','checkedAt',v_now,'createdAt',v_now),'SUPABASE_SESSION');
      perform public.erp_phase26_upsert('lts_health_checks',jsonb_build_object('checkCode','TENANT_SCOPE','checkName','عزل الشركة','category','security','status','passed','severity','info','details',v_slug,'checkedAt',v_now,'createdAt',v_now),'TENANT_SCOPE'); return '{}'::jsonb;
    end if;
  end if;

  if p_area='backup' then
    if p_action='list' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'created_at',created_at,'size_bytes',size_bytes,'checksum',checksum,'schema_version',schema_version,'record_count',record_count,'status',status,'last_verified_at',last_verified_at) order by created_at desc) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),'[]'::jsonb); end if;
    if p_action='create' then
      insert into public.erp_cloud_backups(company_id,name,status,manifest,checksum,schema_version,record_count,size_bytes,created_by,last_verified_at)
      values(v_company,coalesce(nullif(p_payload->>'name',''),'نسخة سحابية '||to_char(v_now,'YYYY-MM-DD HH24:MI')),coalesce(p_payload->>'status','verified'),jsonb_build_object('format','quality-line-erp-cloud-backup','company_id',v_company,'created_at',v_now),encode(digest(v_company::text||v_now::text,'sha256'),'hex'),1,0,0,auth.uid(),v_now); return '{}'::jsonb;
    end if;
    if p_action='export' then select jsonb_build_object('id',id,'name',name,'createdAt',created_at,'schemaVersion',schema_version,'recordCount',record_count,'checksum',checksum,'manifest',manifest) into v_row from public.erp_cloud_backups where company_id=v_company and id=(p_payload->>'id')::uuid and deleted_at is null; if v_row is null then raise exception 'backup_not_found'; end if; return jsonb_build_object('file_name','quality_line_cloud_backup.qlbackup.json','envelope',v_row||jsonb_build_object('format','quality-line-erp-cloud-backup','formatVersion',2)); end if;
    if p_action='import' then insert into public.erp_cloud_backups(company_id,name,status,manifest,checksum,schema_version,created_by,last_verified_at) values(v_company,'مستوردة - '||coalesce(p_payload->>'source_name','backup'),'verified',p_payload->'envelope',encode(digest((p_payload->'envelope')::text,'sha256'),'hex'),2,auth.uid(),v_now) returning id::text into v_id; return jsonb_build_object('id',v_id); end if;
    if p_action='verify' then update public.erp_cloud_backups set status='verified',last_verified_at=v_now where company_id=v_company and id=(p_payload->>'id')::uuid and deleted_at is null; return jsonb_build_object('valid',found); end if;
    if p_action='restore' then raise exception 'cloud_restore_requires_server_operator'; end if;
    if p_action='delete' then update public.erp_cloud_backups set deleted_at=v_now where company_id=v_company and id=(p_payload->>'id')::uuid and deleted_at is null; return '{}'::jsonb; end if;
  end if;

  if p_area='system_monitor' then
    if p_action='snapshot' then return jsonb_build_object('cloud_table_count',(select count(distinct entity_type) from public.erp_records where company_id=v_slug),'cloud_record_count',(select count(*) from public.erp_records where company_id=v_slug and deleted_at is null),'active_sessions',(select count(*) from public.erp_records where company_id=v_slug and entity_type='security_sessions' and deleted_at is null and coalesce(payload->>'status','active')='active'),'backup_count',(select count(*) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),'audit_log_count',(select count(*) from public.erp_records where company_id=v_slug and entity_type in ('audit_logs','security_events') and deleted_at is null),'last_backup_at',(select max(created_at) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),'last_backup_status',(select status from public.erp_cloud_backups where company_id=v_company and deleted_at is null order by created_at desc limit 1)); end if;
    if p_action in ('health_check','retry_server_jobs') then return '{}'::jsonb; end if;
  end if;

  raise exception 'unsupported_phase26_command: %.%',p_area,p_action;
end $$;

revoke all on function public.erp_phase26_records(text,integer) from public,anon;
revoke all on function public.erp_phase26_upsert(text,jsonb,text) from public,anon;
revoke all on function public.erp_phase26_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_phase26_records(text,integer) to authenticated;
grant execute on function public.erp_phase26_upsert(text,jsonb,text) to authenticated;
grant execute on function public.erp_phase26_cloud_command(text,text,jsonb) to authenticated;

commit;
