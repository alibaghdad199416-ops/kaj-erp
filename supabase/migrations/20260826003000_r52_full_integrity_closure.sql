begin;

-- R52 consolidated integrity closure. Additive and data-preserving.
-- Do not derive this operational queue from erp_contracts: contract migrations
-- may legitimately be absent in an already-established migration history.
create table if not exists public.erp_document_processing_jobs (
  company_id uuid not null,
  id uuid not null,
  data jsonb not null default '{}'::jsonb,
  version bigint not null default 1,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (company_id,id)
);
create index if not exists erp_doc_job_status_idx_r52 on public.erp_document_processing_jobs(company_id,((data->>'status')),created_at);
alter table public.erp_document_processing_jobs enable row level security;

do $$
begin
  drop policy if exists tenant_access on public.erp_document_processing_jobs;
  create policy tenant_access on public.erp_document_processing_jobs
    for all using (public.erp_user_belongs_to_company(company_id))
    with check (public.erp_user_belongs_to_company(company_id));
exception when undefined_function then
  null;
end $$;

-- Avoid signature drift: change volatility by function name, regardless of its
-- historical argument list. Missing legacy routines are simply skipped.
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig,p.proname
           from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname in (
             'erp_try_date','erp_try_timestamptz','erp_search_cloud_documents','erp_r22_cash_health',
             'erp_v2300_get_commercial_order_complete_details','erp_r9_cloud_reports_summary',
             'erp_r9_cloud_dashboard_snapshot','erp_r9_cloud_cash_currency_summary','erp_r9_cloud_trial_balance',
             'erp_r9_cloud_account_balance_before','erp_r9_cloud_detailed_accounting_report',
             'erp_r9_cloud_cash_flow_hierarchy','erp_r9_cloud_contextual_report','erp_r9_cloud_model_report',
             'erp_r9_cloud_customer_service_report','erp_r9_cloud_report_audit','erp_r49_get_sales_order_draft',
             'erp_r49_get_purchase_order_draft','erp_get_cloud_current_document_blob','erp_get_cloud_document',
             'erp_list_cloud_document_versions','erp_list_cloud_document_permissions','erp_r15_current_state_health')
  loop
    if r.proname in ('erp_try_date','erp_try_timestamptz') then
      execute format('alter function %s stable',r.sig);
    else
      execute format('alter function %s volatile',r.sig);
    end if;
  end loop;
end $$;

-- R15: never quote an identifier array as one relation name. Process each
-- canonical table independently.
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 t text; tables text[]:=array['erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'];
 checked bigint:=0; conflicts bigint:=0;
begin
 foreach t in array tables loop
  if to_regclass('public.'||t) is not null then
   checked:=checked+1;
   execute format('select count(*) from public.%I r join public.erp_canonical_deletion_tombstones z on z.company_id=r.company_id and z.source_table=$2 and z.record_id=r.id::text where r.company_id=$1 and z.restored_at is null and not coalesce(r.is_deleted,false)',t) into conflicts using p_company_id,t;
  end if;
 end loop;
 return jsonb_build_object('companyId',p_company_id,'checkedTables',checked,'openCanonicalConflicts',conflicts,'status','ok');
end; $$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 t text; tables text[]:=array['erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'];
 conflicts bigint:=0;
begin
 foreach t in array tables loop
  if to_regclass('public.'||t) is not null then
   execute format('select count(*) from public.%I r join public.erp_canonical_deletion_tombstones z on z.company_id=r.company_id and z.source_table=$2 and z.record_id=r.id::text where r.company_id=$1 and z.restored_at is null and not coalesce(r.is_deleted,false)',t) into conflicts using p_company_id,t;
  end if;
 end loop;
 return jsonb_build_object('companyId',p_company_id,'canonicalConflicts',conflicts,'healthy',conflicts=0);
end; $$;

-- Replace record/dynamic-SQL master readers with scalar targets so an empty
-- result never leaves an unassigned record whose tuple type is indeterminate.
create or replace function public.erp_r9_get_cloud_master_record(p_company_id uuid,p_table text,p_record_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id text; v_data jsonb; v_version bigint; v_updated timestamptz;
begin
 execute format('select id::text,data,version,updated_at from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',p_table) into v_id,v_data,v_version,v_updated using p_company_id,p_record_id;
 if v_id is null then return null; end if;
 return public.erp_r9_filter_readable_master_json(p_company_id,p_table,coalesce(v_data,'{}'::jsonb))||jsonb_build_object('id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated);
end; $$;

create or replace function public.erp_r9_list_cloud_master_records(p_company_id uuid,p_table text)
returns setof jsonb language plpgsql security definer set search_path=public as $$
declare v_id text; v_data jsonb; v_version bigint; v_updated timestamptz;
begin
 for v_id,v_data,v_version,v_updated in execute format('select id::text,data,version,updated_at from public.%I where company_id=$1 and not coalesce(is_deleted,false) order by updated_at desc',p_table) using p_company_id loop
  return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,coalesce(v_data,'{}'::jsonb))||jsonb_build_object('id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated);
 end loop;
 return;
end; $$;

-- erp_records has updated_at but not created_at; use payload createdAt when
-- available and fall back to updated_at. This removes the invalid column error.
create or replace function public.erp_r49_cloud_global_search(p_company_id uuid,p_query text,p_limit integer default 50)
returns setof jsonb language plpgsql security definer set search_path=public as $$
declare v_slug text; v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
begin
 select slug into v_slug from public.companies where id=p_company_id;
 if v_slug is null then return; end if;
 return query
 select jsonb_build_object('id',r.record_id,'type','الفرص التجارية','title',coalesce(nullif(r.payload->>'title',''),nullif(r.payload->>'opportunityNumber',''),'فرصة تجارية'),'subtitle',concat_ws(' • ',nullif(r.payload->>'opportunityNumber',''),nullif(r.payload->>'customerName',''),nullif(r.payload->>'stage','')),'route','/customer-service','permission','customer_service.view','icon','opportunity','status',coalesce(nullif(r.payload->>'status',''),nullif(r.payload->>'stage',''),'pending'),'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),'currency',case when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD') then upper(r.payload->>'currency') else null end,'date',coalesce(nullif(r.payload->>'updatedAt',''),nullif(r.payload->>'createdAt',''),r.updated_at::text))
 from public.erp_records r
 where r.company_id=v_slug and r.entity_type='opportunities' and r.deleted_at is null
 and (r.payload::text ilike '%'||btrim(p_query)||'%')
 order by coalesce(r.payload->>'updatedAt',r.updated_at::text) desc limit v_limit;
end; $$;

notify pgrst,'reload schema';
commit;
