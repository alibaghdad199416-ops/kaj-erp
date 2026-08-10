-- Quality Line ERP 17.19.0
-- Retire standalone modules that are no longer part of the accepted runtime.
-- Operational data for inventory, partners, maintenance, customer service,
-- sales, purchases, payments, accounting, settings and document attachments
-- is intentionally preserved.

begin;

create schema if not exists qualityline_retired;
comment on schema qualityline_retired is
  'One-time pre-drop archive created by 20260728001200_accepted_module_cleanup.sql. Export this schema before removing it.';

-- Archive every retired dedicated table before dropping it. The archive is
-- deliberately outside public so it is not exposed by PostgREST.
do $$
declare
  v_table text;
  v_tables constant text[] := array[
    'erp_contract_warranties',
    'erp_contract_warranty_claims',
    'erp_contract_installment_plans',
    'erp_contract_installment_schedule',
    'erp_contract_installment_payments',
    'erp_contract_reschedule_history',
    'erp_contracts',
    'erp_contract_versions',
    'erp_contract_events',
    'erp_contract_reviews',
    'erp_contract_approval_requests',
    'erp_contract_signature_requests',
    'erp_contract_parties',
    'erp_contract_renewals',
    'erp_contract_lifecycle_runs',
    'erp_contract_clauses',
    'erp_contract_links',
    'erp_document_processing_jobs',
    'erp_document_index_terms',
    'erp_document_duplicate_matches',
    'erp_document_governance_actions',
    'erp_workflow_definitions',
    'erp_workflow_steps',
    'erp_workflow_instances',
    'erp_hr_departments',
    'erp_hr_employees',
    'erp_hr_employment_contracts',
    'erp_hr_attendance_records',
    'erp_hr_leave_requests',
    'erp_hr_payroll_runs',
    'erp_hr_payroll_items',
    'erp_projects',
    'erp_project_tasks',
    'erp_project_expenses',
    'erp_project_time_entries',
    'erp_asset_categories',
    'erp_fixed_assets',
    'erp_asset_maintenance_plans',
    'erp_asset_work_orders',
    'erp_asset_depreciation_entries',
    'erp_bi_daily_snapshots',
    'erp_bi_alerts',
    'erp_security_events',
    'erp_security_sessions',
    'erp_security_trusted_devices',
    'erp_security_mfa_factors',
    'erp_security_identity_providers',
    'erp_governance_approvals',
    'erp_governance_attachments'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass(format('public.%I', v_table)) is not null then
      execute format(
        'create table if not exists qualityline_retired.%I as table public.%I',
        v_table,
        v_table
      );
    end if;
  end loop;
end $$;

-- Archive and remove generic erp_records rows belonging only to retired
-- modules. Customer-service opportunities and operational audit records stay.
create table if not exists qualityline_retired.erp_records_removed_modules as
select *
from public.erp_records
where entity_type = any(array[
  'ai_conversations','ai_messages','ai_suggestions',
  'builder_artifacts','builder_dashboards','builder_forms','builder_reports',
  'builder_rules','builder_workflows',
  'enterprise_document_links','enterprise_documents','document_status_history',
  'integration_api_clients','integration_connectors','integration_messages',
  'integration_webhook_subscriptions',
  'lts_health_checks','lts_incidents','lts_release_gates',
  'mobile_cloud_actions','mobile_devices','mobile_notifications',
  'prediction_forecasts','prediction_risks','security_sessions'
]::text[]);

delete from public.erp_records
where entity_type = any(array[
  'ai_conversations','ai_messages','ai_suggestions',
  'builder_artifacts','builder_dashboards','builder_forms','builder_reports',
  'builder_rules','builder_workflows',
  'enterprise_document_links','enterprise_documents','document_status_history',
  'integration_api_clients','integration_connectors','integration_messages',
  'integration_webhook_subscriptions',
  'lts_health_checks','lts_incidents','lts_release_gates',
  'mobile_cloud_actions','mobile_devices','mobile_notifications',
  'prediction_forecasts','prediction_risks','security_sessions'
]::text[]);

-- Retain only permissions used by the accepted modules and their embedded
-- operational subsections. The FK on role_permissions removes stale role links.
create table if not exists qualityline_retired.permissions_removed_modules as
select *
from public.permissions
where split_part(code, '.', 1) = any(array[
  'assets','contracts','documents','hr','opportunities','projects','reservations',
  'governance','business_intelligence','artificial_intelligence','predictions',
  'mobile','platform_builder','security','cloud_platform',
  'production_hardening','integration'
]::text[]);

delete from public.permissions
where split_part(code, '.', 1) = any(array[
  'assets','contracts','documents','hr','opportunities','projects','reservations',
  'governance','business_intelligence','artificial_intelligence','predictions',
  'mobile','platform_builder','security','cloud_platform',
  'production_hardening','integration'
]::text[]);

-- Remove the corresponding per-company permission and role-permission rows.
delete from public.erp_records r
where r.entity_type = 'permissions'
  and split_part(coalesce(r.payload->>'code', r.record_id), '.', 1) = any(array[
    'assets','contracts','documents','hr','opportunities','projects','reservations',
    'governance','business_intelligence','artificial_intelligence','predictions',
    'mobile','platform_builder','security','cloud_platform',
    'production_hardening','integration'
  ]::text[]);

delete from public.erp_records r
where r.entity_type = 'role_permissions'
  and split_part(coalesce(r.payload->>'permissionId', split_part(r.record_id, '::', 2)), '.', 1) = any(array[
    'assets','contracts','documents','hr','opportunities','projects','reservations',
    'governance','business_intelligence','artificial_intelligence','predictions',
    'mobile','platform_builder','security','cloud_platform',
    'production_hardening','integration'
  ]::text[]);

-- Drop dedicated retired tables only after their archive copies exist.
do $$
declare
  v_table text;
  v_tables constant text[] := array[
    'erp_contract_warranties','erp_contract_warranty_claims',
    'erp_contract_installment_plans','erp_contract_installment_schedule',
    'erp_contract_installment_payments','erp_contract_reschedule_history',
    'erp_contracts','erp_contract_versions','erp_contract_events',
    'erp_contract_reviews','erp_contract_approval_requests',
    'erp_contract_signature_requests','erp_contract_parties',
    'erp_contract_renewals','erp_contract_lifecycle_runs',
    'erp_contract_clauses','erp_contract_links',
    'erp_document_processing_jobs','erp_document_index_terms',
    'erp_document_duplicate_matches','erp_document_governance_actions',
    'erp_workflow_definitions','erp_workflow_steps','erp_workflow_instances',
    'erp_hr_departments','erp_hr_employees','erp_hr_employment_contracts',
    'erp_hr_attendance_records','erp_hr_leave_requests','erp_hr_payroll_runs',
    'erp_hr_payroll_items','erp_projects','erp_project_tasks',
    'erp_project_expenses','erp_project_time_entries','erp_asset_categories',
    'erp_fixed_assets','erp_asset_maintenance_plans','erp_asset_work_orders',
    'erp_asset_depreciation_entries','erp_bi_daily_snapshots','erp_bi_alerts',
    'erp_security_events','erp_security_sessions','erp_security_trusted_devices',
    'erp_security_mfa_factors','erp_security_identity_providers',
    'erp_governance_approvals','erp_governance_attachments'
  ];
begin
  foreach v_table in array v_tables loop
    if to_regclass(format('public.%I', v_table)) is not null then
      execute format('drop table public.%I cascade', v_table);
    end if;
  end loop;
end $$;

-- Replace the historical multi-module command router with the four supporting
-- areas that remain reachable from accepted modules.
create or replace function public.erp_phase26_cloud_command(
  p_area text,
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_slug text;
  v_id text;
  v_row jsonb;
  v_now timestamptz := now();
begin
  select company_uuid, company_slug
    into v_company, v_slug
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found'; end if;

  if p_area = 'opportunity' then
    if p_action = 'list' then
      return public.erp_phase26_records('opportunities', 500);
    elsif p_action = 'save' then
      return public.erp_phase26_upsert('opportunities', p_payload->'record');
    elsif p_action = 'delete' then
      update public.erp_records
         set deleted_at = v_now,
             updated_at = v_now,
             payload = payload || jsonb_build_object(
               'isDeleted', true, 'is_deleted', true,
               'deletedAt', v_now, 'deleted_at', v_now)
       where company_id = v_slug
         and entity_type = 'opportunities'
         and record_id = p_payload->>'id';
      return '{}'::jsonb;
    elsif p_action = 'mark_lost' then
      select payload into v_row
      from public.erp_records
      where company_id = v_slug and entity_type = 'opportunities'
        and record_id = p_payload->>'id' and deleted_at is null
      for update;
      if v_row is null then raise exception 'opportunity_not_found'; end if;
      return public.erp_phase26_upsert(
        'opportunities',
        v_row || jsonb_build_object('status','lost','closedAt',v_now,'updatedAt',v_now),
        p_payload->>'id'
      );
    elsif p_action = 'mark_won' then
      select payload into v_row
      from public.erp_records
      where company_id = v_slug and entity_type = 'opportunities'
        and record_id = p_payload->>'opportunity_id' and deleted_at is null
      for update;
      if v_row is null then raise exception 'opportunity_not_found'; end if;
      v_id := gen_random_uuid()::text;
      v_row := jsonb_build_object(
        'id',v_id,'carId',p_payload->>'car_id','customerId',v_row->>'customerId',
        'salePrice',coalesce((p_payload->>'sale_price')::numeric,0),
        'paidAmount',coalesce((p_payload->>'paid_amount')::numeric,0),
        'remainingAmount',coalesce((p_payload->>'sale_price')::numeric,0)-coalesce((p_payload->>'paid_amount')::numeric,0),
        'paymentMethod',p_payload->>'payment_method','saleDate',v_now,
        'invoiceNumber','SAL-'||extract(epoch from clock_timestamp())::bigint,
        'opportunityId',p_payload->>'opportunity_id'
      );
      perform public.erp_phase26_upsert('sales',v_row,v_id);
      perform public.erp_phase26_upsert(
        'opportunities',
        (select payload from public.erp_records
          where company_id=v_slug and entity_type='opportunities'
            and record_id=p_payload->>'opportunity_id') ||
        jsonb_build_object(
          'status','won','carId',p_payload->>'car_id',
          'carName',p_payload->>'car_name','saleId',v_id,'closedAt',v_now),
        p_payload->>'opportunity_id'
      );
      update public.erp_records
         set payload=payload||jsonb_build_object('status','مباعة','updatedAt',v_now),
             updated_at=v_now
       where company_id=v_slug and entity_type in ('cars','erp_cars')
         and record_id=p_payload->>'car_id';
      return v_row;
    end if;
  end if;

  if p_area = 'backup' then
    if p_action = 'list' then
      return coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',id,'name',name,'created_at',created_at,'size_bytes',size_bytes,
          'checksum',checksum,'schema_version',schema_version,
          'record_count',record_count,'status',status,
          'last_verified_at',last_verified_at) order by created_at desc)
        from public.erp_cloud_backups
        where company_id=v_company and deleted_at is null
      ), '[]'::jsonb);
    elsif p_action = 'create' then
      insert into public.erp_cloud_backups(
        company_id,name,status,manifest,checksum,schema_version,
        record_count,size_bytes,created_by,last_verified_at)
      values(
        v_company,
        coalesce(nullif(p_payload->>'name',''),'نسخة سحابية '||to_char(v_now,'YYYY-MM-DD HH24:MI')),
        coalesce(p_payload->>'status','verified'),
        jsonb_build_object('format','quality-line-erp-cloud-backup','company_id',v_company,'created_at',v_now),
        encode(digest(v_company::text||v_now::text,'sha256'),'hex'),
        1,0,0,auth.uid(),v_now);
      return '{}'::jsonb;
    elsif p_action = 'export' then
      select jsonb_build_object(
        'id',id,'name',name,'createdAt',created_at,'schemaVersion',schema_version,
        'recordCount',record_count,'checksum',checksum,'manifest',manifest)
      into v_row
      from public.erp_cloud_backups
      where company_id=v_company and id=(p_payload->>'id')::uuid and deleted_at is null;
      if v_row is null then raise exception 'backup_not_found'; end if;
      return jsonb_build_object(
        'file_name','quality_line_cloud_backup.qlbackup.json',
        'envelope',v_row||jsonb_build_object('format','quality-line-erp-cloud-backup','formatVersion',2));
    elsif p_action = 'import' then
      insert into public.erp_cloud_backups(
        company_id,name,status,manifest,checksum,schema_version,created_by,last_verified_at)
      values(
        v_company,'مستوردة - '||coalesce(p_payload->>'source_name','backup'),
        'verified',p_payload->'envelope',
        encode(digest((p_payload->'envelope')::text,'sha256'),'hex'),2,auth.uid(),v_now)
      returning id::text into v_id;
      return jsonb_build_object('id',v_id);
    elsif p_action = 'verify' then
      update public.erp_cloud_backups
         set status='verified',last_verified_at=v_now
       where company_id=v_company and id=(p_payload->>'id')::uuid and deleted_at is null;
      return jsonb_build_object('valid',found);
    elsif p_action = 'restore' then
      raise exception 'cloud_restore_requires_server_operator';
    elsif p_action = 'delete' then
      update public.erp_cloud_backups set deleted_at=v_now
       where company_id=v_company and id=(p_payload->>'id')::uuid and deleted_at is null;
      return '{}'::jsonb;
    end if;
  end if;

  if p_area = 'company_settings' and p_action = 'branding' then
    return public.erp_get_cloud_company_settings();
  end if;

  if p_area = 'system_monitor' then
    if p_action = 'snapshot' then
      return jsonb_build_object(
        'cloud_table_count',(select count(distinct entity_type) from public.erp_records where company_id=v_slug),
        'cloud_record_count',(select count(*) from public.erp_records where company_id=v_slug and deleted_at is null),
        'active_sessions',(select count(*) from public.company_memberships where company_id=v_company and is_active),
        'backup_count',(select count(*) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),
        'audit_log_count',(select count(*) from public.erp_records where company_id=v_slug and entity_type='audit_logs' and deleted_at is null),
        'last_backup_at',(select max(created_at) from public.erp_cloud_backups where company_id=v_company and deleted_at is null),
        'last_backup_status',(select status from public.erp_cloud_backups where company_id=v_company and deleted_at is null order by created_at desc limit 1)
      );
    elsif p_action in ('health_check','retry_server_jobs') then
      return '{}'::jsonb;
    end if;
  end if;

  raise exception 'unsupported_phase26_command: %.%', p_area, p_action;
end $$;


revoke all on function public.erp_phase26_cloud_command(text,text,jsonb) from public, anon;
grant execute on function public.erp_phase26_cloud_command(text,text,jsonb) to authenticated;

-- Canonical search results only point to routes that remain in the Flutter
-- application. Attachments are searchable through their parent sale/purchase,
-- not as a standalone Documents module.
create or replace function public.erp_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
  with q as (
    select '%' || btrim(coalesce(p_query,'')) || '%' pattern
  ), rows as (
    select c.id::text id, 'السيارات'::text type,
      concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year') title,
      concat_ws(' • ',coalesce(c.data->>'chassis',c.data->>'vin'),coalesce(c.data->>'plateNumber',c.data->>'carNumber')) subtitle,
      '/inventory'::text route, 'cars.view'::text permission, 'car'::text icon,
      c.data->>'status' status, public.erp_try_numeric(c.data->>'salePrice',0) amount,
      c.created_at occurred_at, 1 rank
    from public.erp_cars c cross join q
    where c.company_id=p_company_id and not c.is_deleted and (
      coalesce(c.data->>'brand',c.data->>'make','') ilike q.pattern or
      coalesce(c.data->>'model','') ilike q.pattern or
      coalesce(c.data->>'chassis',c.data->>'vin','') ilike q.pattern or
      coalesce(c.data->>'plateNumber','') ilike q.pattern or
      coalesce(c.data->>'carNumber','') ilike q.pattern)
    union all
    select i.id, 'المنتجات', coalesce(i.data->>'nameAr',i.data->>'name',i.data->>'nameEn',i.data->>'code',''),
      concat_ws(' • ',i.data->>'code',i.data->>'sku',i.data->>'barcode'),
      '/products','inventory.view','inventory',
      case when public.erp_try_boolean(i.data->>'isActive',true) then 'active' else 'inactive' end,
      public.erp_try_numeric(i.data->>'salePrice',0),i.created_at,2
    from public.erp_inventory i cross join q
    where i.company_id=p_company_id and not i.is_deleted and (
      coalesce(i.data->>'nameAr',i.data->>'name',i.data->>'nameEn','') ilike q.pattern or
      coalesce(i.data->>'code','') ilike q.pattern or
      coalesce(i.data->>'sku','') ilike q.pattern or
      coalesce(i.data->>'barcode','') ilike q.pattern)
    union all
    select w.id, 'المخازن', coalesce(w.data->>'name',''),
      concat_ws(' • ',w.data->>'code',w.data->>'address'),
      '/inventory','inventory.view','inventory',
      case when public.erp_try_boolean(w.data->>'isActive',true) then 'active' else 'inactive' end,
      null::numeric,w.created_at,3
    from public.erp_warehouses w cross join q
    where w.company_id=p_company_id and not w.is_deleted and (
      coalesce(w.data->>'name','') ilike q.pattern or
      coalesce(w.data->>'code','') ilike q.pattern or
      coalesce(w.data->>'address','') ilike q.pattern)
    union all
    select x.id, 'العملاء', coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/business-partners','customers.view','customer',
      case when public.erp_try_boolean(x.data->>'isActive',true) then 'active' else 'inactive' end,
      public.erp_try_numeric(x.data->>'balance',0),x.created_at,4
    from public.erp_customers x cross join q
    where x.company_id=p_company_id and not x.is_deleted and (
      coalesce(x.data->>'name','') ilike q.pattern or coalesce(x.data->>'phone','') ilike q.pattern or
      coalesce(x.data->>'email','') ilike q.pattern or coalesce(x.data->>'taxNumber','') ilike q.pattern)
    union all
    select x.id, 'المجهزون', coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/business-partners','suppliers.view','supplier',
      case when public.erp_try_boolean(x.data->>'isActive',true) then 'active' else 'inactive' end,
      public.erp_try_numeric(x.data->>'balance',0),x.created_at,5
    from public.erp_suppliers x cross join q
    where x.company_id=p_company_id and not x.is_deleted and (
      coalesce(x.data->>'name','') ilike q.pattern or coalesce(x.data->>'phone','') ilike q.pattern or
      coalesce(x.data->>'email','') ilike q.pattern or coalesce(x.data->>'taxNumber','') ilike q.pattern)
    union all
    select m.id::text, 'الصيانة', m.order_number,concat_ws(' • ',m.customer_name,m.car_name),
      '/maintenance','maintenance.view','maintenance',m.status,m.total_cost,m.created_at,6
    from public.erp_maintenance_orders m cross join q
    where m.company_id=p_company_id and not m.is_deleted and (
      m.order_number ilike q.pattern or coalesce(m.customer_name,'') ilike q.pattern or
      coalesce(m.car_name,'') ilike q.pattern or coalesce(m.invoice_number,'') ilike q.pattern)
    union all
    select sc.id::text, 'خدمة العملاء', sc.case_number,concat_ws(' • ',sc.title,sc.description),
      '/customer-service','customer_service.view','service',sc.status,null::numeric,sc.created_at,7
    from public.erp_service_cases sc cross join q
    where sc.company_id=p_company_id and not sc.is_deleted and (
      sc.case_number ilike q.pattern or sc.title ilike q.pattern or coalesce(sc.description,'') ilike q.pattern)
    union all
    select o.id::text, 'أوامر البيع', o.order_number,coalesce(c.data->>'name',''),
      '/sales','sales.view','sale',o.status,o.total,o.created_at,8
    from public.erp_sales_orders_cloud o cross join q
    left join public.erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
    where o.company_id=p_company_id and not o.is_deleted and (
      o.order_number ilike q.pattern or coalesce(c.data->>'name','') ilike q.pattern)
    union all
    select o.id::text, 'أوامر الشراء', o.order_number,coalesce(sp.data->>'name',''),
      '/purchases','purchases.view','purchase',o.status,o.total,o.created_at,9
    from public.erp_purchase_orders_cloud o cross join q
    left join public.erp_suppliers sp on sp.company_id=o.company_id and sp.id=o.supplier_id and not sp.is_deleted
    where o.company_id=p_company_id and not o.is_deleted and (
      o.order_number ilike q.pattern or coalesce(sp.data->>'name','') ilike q.pattern)
    union all
    select d.id::text,
      case when d.document_type='delivery' then 'التجهيز' when d.document_type='receipt' then 'الاستلام' else 'الفواتير' end,
      d.document_number,coalesce(d.payload->>'partnerName',''),
      case when d.module='sales' then '/sales' else '/purchases' end,
      case when d.module='sales' then 'sales.view' else 'purchases.view' end,
      case when d.document_type='delivery' then 'delivery' when d.document_type='receipt' then 'receipt' else 'invoice' end,
      d.status,public.erp_try_numeric(d.payload->>'totalAmount',0),d.created_at,10
    from public.erp_commercial_workflow_documents d cross join q
    where d.company_id=p_company_id and not d.is_deleted and (
      d.document_number ilike q.pattern or coalesce(d.payload->>'invoiceNumber','') ilike q.pattern)
    union all
    select j.id::text, 'القيود المحاسبية',coalesce(j.data->>'entryNumber',j.data->>'number',j.id::text),
      coalesce(j.data->>'description',''),'/accounting','accounting.view','journal',
      coalesce(j.data->>'status','posted'),public.erp_try_numeric(j.data->>'totalDebit',0),j.created_at,11
    from public.erp_journal_entries j cross join q
    where j.company_id=p_company_id and not j.is_deleted and (
      coalesce(j.data->>'entryNumber',j.data->>'number','') ilike q.pattern or
      coalesce(j.data->>'description','') ilike q.pattern or coalesce(j.data->>'reference','') ilike q.pattern)
    union all
    select ins.id, 'الدفعات',coalesce(ins.data->>'invoiceNumber',ins.data->>'installmentNumber',ins.id),
      coalesce(ins.data->>'customerName',''),'/accounting','installments.view','payment',
      coalesce(ins.data->>'status','pending'),public.erp_try_numeric(ins.data->>'remainingAmount',0),ins.created_at,12
    from public.erp_installments ins cross join q
    where ins.company_id=p_company_id and not ins.is_deleted and (
      coalesce(ins.data->>'invoiceNumber','') ilike q.pattern or
      coalesce(ins.data->>'installmentNumber','') ilike q.pattern or
      coalesce(ins.data->>'customerName','') ilike q.pattern)
  )
  select jsonb_build_object(
    'id',id,'type',type,'title',title,'subtitle',subtitle,'route',route,
    'permission',permission,'icon',icon,'status',status,'amount',amount,
    'date',occurred_at::text)
  from rows
  where public.erp_is_company_member(p_company_id)
    and length(btrim(coalesce(p_query,''))) >= 2
  order by rank, occurred_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
$$;

revoke all on function public.erp_cloud_global_search(uuid,text,integer) from public, anon;
grant execute on function public.erp_cloud_global_search(uuid,text,integer) to authenticated;


-- Persistent Notification Center records remain operational. Recreate the
-- writer with duplicate prevention for the same active business reference.
create or replace function public.erp_create_cloud_notification(
  p_company_id uuid,
  p_user_id uuid,
  p_role_id uuid,
  p_title_ar text,
  p_title_en text,
  p_body_ar text,
  p_body_en text,
  p_type text,
  p_reference_type text,
  p_reference_id text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_now timestamptz := now();
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  if nullif(btrim(coalesce(p_reference_type,'')),'') is not null
     and nullif(btrim(coalesce(p_reference_id,'')),'') is not null then
    select n.id into v_id
    from public.erp_enterprise_notifications n
    where n.company_id=p_company_id
      and not n.is_deleted
      and coalesce(n.data->>'type','info')=coalesce(nullif(btrim(p_type),''),'info')
      and coalesce(n.data->>'referenceType','')=btrim(p_reference_type)
      and coalesce(n.data->>'referenceId','')=btrim(p_reference_id)
      and coalesce(n.data->>'userId','')=coalesce(p_user_id::text,'')
      and coalesce(n.data->>'roleId','')=coalesce(p_role_id::text,'')
    order by n.created_at desc
    limit 1
    for update;
  end if;

  if v_id is null then
    v_id := gen_random_uuid();
    insert into public.erp_enterprise_notifications(company_id,id,data)
    values(
      p_company_id,
      v_id,
      jsonb_build_object(
        'userId',p_user_id,
        'roleId',p_role_id,
        'titleAr',coalesce(p_title_ar,''),
        'titleEn',coalesce(p_title_en,''),
        'bodyAr',coalesce(p_body_ar,''),
        'bodyEn',coalesce(p_body_en,''),
        'type',coalesce(nullif(btrim(p_type),''),'info'),
        'referenceType',nullif(btrim(coalesce(p_reference_type,'')),''),
        'referenceId',nullif(btrim(coalesce(p_reference_id,'')),''),
        'isRead',false,
        'createdAt',v_now
      )
    );
  else
    update public.erp_enterprise_notifications
       set data=data || jsonb_build_object(
         'titleAr',coalesce(p_title_ar,''),
         'titleEn',coalesce(p_title_en,''),
         'bodyAr',coalesce(p_body_ar,''),
         'bodyEn',coalesce(p_body_en,''),
         'isRead',false,
         'readAt',null,
         'updatedAt',v_now
       ),
       updated_at=v_now
     where company_id=p_company_id and id=v_id and not is_deleted;
  end if;

  return v_id;
end $$;

create or replace function public.erp_archive_cloud_notification(
  p_company_id uuid,
  p_notification_id uuid
) returns void
language sql
security definer
set search_path = public
as $$
  update public.erp_enterprise_notifications
     set is_deleted=true,
         deleted_at=now(),
         updated_at=now(),
         data=data || jsonb_build_object('archivedAt',now())
   where company_id=p_company_id
     and id=p_notification_id
     and not is_deleted
     and public.erp_is_company_member(p_company_id);
$$;

revoke all on function public.erp_create_cloud_notification(uuid,uuid,uuid,text,text,text,text,text,text,text) from public, anon;
grant execute on function public.erp_create_cloud_notification(uuid,uuid,uuid,text,text,text,text,text,text,text) to authenticated;
revoke all on function public.erp_list_cloud_notifications(uuid,uuid,uuid,boolean,integer,integer) from public, anon;
grant execute on function public.erp_list_cloud_notifications(uuid,uuid,uuid,boolean,integer,integer) to authenticated;
revoke all on function public.erp_cloud_unread_notification_count(uuid,uuid,uuid) from public, anon;
grant execute on function public.erp_cloud_unread_notification_count(uuid,uuid,uuid) to authenticated;
revoke all on function public.erp_mark_cloud_notification_read(uuid,uuid) from public, anon;
grant execute on function public.erp_mark_cloud_notification_read(uuid,uuid) to authenticated;
revoke all on function public.erp_mark_all_cloud_notifications_read(uuid,uuid,uuid) from public, anon;
grant execute on function public.erp_mark_all_cloud_notifications_read(uuid,uuid,uuid) to authenticated;
revoke all on function public.erp_archive_cloud_notification(uuid,uuid) from public, anon;
grant execute on function public.erp_archive_cloud_notification(uuid,uuid) to authenticated;

-- Dynamic alert routes also remain inside the accepted module catalog.
create or replace function public.erp_cloud_notification_alerts(
  p_company_id uuid,
  p_reference_day date
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
  with metrics as (
    select 'overdue-installments'::text id,'أقساط متأخرة'::text title,
      'يوجد أقساط متأخرة تحتاج إلى متابعة وتحصيل.'::text message,
      'critical'::text severity,'installment'::text icon,'/accounting'::text route,
      count(*)::int count,coalesce(sum(public.erp_try_numeric(data->>'remainingAmount',0)),0)::numeric amount
    from public.erp_installments
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'status',''))<>'paid'
      and public.erp_try_numeric(data->>'remainingAmount',0)>0
      and public.erp_try_date(data->>'dueDate',p_reference_day)<p_reference_day
    union all
    select 'out-of-stock','منتجات نافدة','توجد منتجات وصل رصيدها المتاح إلى صفر.','critical','stock','/products',
      count(*)::int,null::numeric
    from public.erp_warehouse_stock
    where company_id=p_company_id and not is_deleted
      and public.erp_try_numeric(data->>'quantity',0)-public.erp_try_numeric(data->>'reservedQuantity',0)<=0
    union all
    select 'low-stock','مواد عند حد إعادة الطلب','توجد مواد بلغت حد إعادة الطلب.','warning','stock','/inventory',
      count(*)::int,null::numeric
    from public.erp_warehouse_stock
    where company_id=p_company_id and not is_deleted
      and public.erp_try_numeric(data->>'quantity',0)-public.erp_try_numeric(data->>'reservedQuantity',0)>0
      and public.erp_try_numeric(data->>'quantity',0)-public.erp_try_numeric(data->>'reservedQuantity',0)
          <=public.erp_try_numeric(data->>'minimumQuantity',0)
    union all
    select 'cars-without-warehouse','سيارات بلا مخزن','توجد سيارات غير مرتبطة بمخزن حالي.','critical','car','/inventory',
      count(*)::int,null::numeric
    from public.erp_cars
    where company_id=p_company_id and not is_deleted
      and nullif(btrim(coalesce(data->>'warehouseId',data->>'warehouse_id','')),'') is null
      and lower(coalesce(data->>'status','')) not in ('sold','مباعة','مباع')
    union all
    select 'overdue-maintenance','أوامر صيانة متأخرة','توجد أوامر صيانة مفتوحة تجاوزت موعدها.','warning','maintenance','/maintenance',
      count(*)::int,coalesce(sum(total_cost),0)::numeric
    from public.erp_maintenance_orders
    where company_id=p_company_id and not is_deleted
      and lower(status) not in ('completed','closed','cancelled','canceled')
      and maintenance_date::date<p_reference_day
    union all
    select 'open-service-cases','طلبات خدمة عملاء مفتوحة','توجد طلبات خدمة عملاء تحتاج إلى متابعة.','warning','service','/customer-service',
      count(*)::int,null::numeric
    from public.erp_service_cases
    where company_id=p_company_id and not is_deleted
      and lower(status) not in ('closed','resolved','cancelled','canceled')
    union all
    select 'delayed-sales','أوامر بيع متأخرة','توجد أوامر بيع لم تكتمل خلال سبعة أيام.','warning','sale','/sales',
      count(*)::int,coalesce(sum(total),0)::numeric
    from public.erp_sales_orders_cloud
    where company_id=p_company_id and not is_deleted
      and lower(status) in ('draft','pending','approved','partial')
      and created_at::date<p_reference_day-7
    union all
    select 'delayed-purchases','أوامر شراء متأخرة','توجد أوامر شراء لم تكتمل خلال سبعة أيام.','warning','purchase','/purchases',
      count(*)::int,coalesce(sum(total),0)::numeric
    from public.erp_purchase_orders_cloud
    where company_id=p_company_id and not is_deleted
      and lower(status) in ('draft','pending','approved','partial')
      and created_at::date<p_reference_day-7
  )
  select jsonb_build_object(
    'id',id,'title',title,'message',message,'severity',severity,
    'icon',icon,'route',route,'count',count,'amount',amount)
  from metrics
  where count>0 and public.erp_is_company_member(p_company_id);
$$;

revoke all on function public.erp_cloud_notification_alerts(uuid,date) from public, anon;
grant execute on function public.erp_cloud_notification_alerts(uuid,date) to authenticated;

commit;
