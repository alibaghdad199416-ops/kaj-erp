\set ON_ERROR_STOP on
\pset pager off

begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
  ('00000000-0000-0000-0000-000000000000','aaaaaaaa-0000-4000-8000-000000000001','authenticated','authenticated','admin-a@fresh.local','',now(),'{}','{}',now(),now()),
  ('00000000-0000-4000-8000-000000000000','aaaaaaaa-0000-4000-8000-000000000002','authenticated','authenticated','crm-a@fresh.local','',now(),'{}','{}',now(),now()),
  ('00000000-0000-4000-8000-000000000000','aaaaaaaa-0000-4000-8000-000000000003','authenticated','authenticated','member-a@fresh.local','',now(),'{}','{}',now(),now()),
  ('00000000-0000-4000-8000-000000000000','bbbbbbbb-0000-4000-8000-000000000001','authenticated','authenticated','admin-b@fresh.local','',now(),'{}','{}',now(),now());

insert into public.companies(id,slug,name_ar,name_en,is_active) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','fresh-company-a','شركة أ','Company A',true),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','fresh-company-b','شركة ب','Company B',true),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','fresh-company-inactive','شركة متوقفة','Inactive Company',false);

insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001','admin-a@fresh.local','admin',true,true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000002','aaaaaaaa-0000-4000-8000-000000000002','crm-a@fresh.local','user',false,true),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000003','aaaaaaaa-0000-4000-8000-000000000003','member-a@fresh.local','user',false,true),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bbbbbbbb-0000-4000-8000-000000000001','bbbbbbbb-0000-4000-8000-000000000001','admin-b@fresh.local','admin',true,true),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001','admin-a@fresh.local','admin',true,true);

insert into public.erp_permission_roles(id,company_id,code,name_ar,name_en,created_by)
values('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','fresh-crm','مخول CRM','CRM authorized','fixture');
insert into public.erp_role_permission_grants(company_id,role_id,permission_code,effect,granted_by)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','customer_service.update','allow','fixture');
insert into public.erp_user_role_assignments(company_id,user_uid,role_id,assigned_by)
values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','aaaaaaaa-0000-4000-8000-000000000002','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','fixture');

insert into public.erp_cars(company_id,id,data) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','r52-car','{"brand":"R52 Car","model":"Verified","currency":"USD","salePrice":11000}');
insert into public.erp_inventory(company_id,id,data) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','r52-product','{"name":"R52 Product","code":"R52-PRODUCT","currency":"IQD","salePrice":25000,"isActive":true}');
insert into public.erp_sales_orders_cloud(
  id,company_id,order_number,customer_id,status,currency,exchange_rate,subtotal,discount,total
) values
  ('a1000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','R52-SALE','customer-a','draft','USD',1,100,0,100),
  ('a1000000-0000-4000-8000-000000000002','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','R52-CRM-LINK','customer-a','draft','USD',1,200,0,200),
  ('b1000000-0000-4000-8000-000000000001','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','R52-B-SALE','customer-b','draft','IQD',1,300,0,300);
insert into public.erp_purchase_orders_cloud(
  id,company_id,order_number,supplier_id,status,currency,exchange_rate,subtotal,discount,total
) values(
  'a2000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','R52-PURCHASE','supplier-a','draft','IQD',1,400,0,400
);
insert into public.erp_maintenance_orders(
  id,company_id,order_number,car_id,car_name,customer_name,status,total_cost,currency_code
) values(
  'a3000000-0000-4000-8000-000000000001','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','R52-MAINTENANCE',
  'a3000000-0000-4000-8000-000000000002','R52 Car','R52 Customer','draft',50,'USD'
);
insert into public.erp_journal_entries(company_id,id,data) values(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','r52-journal',
  '{"entryNumber":"R52-JOURNAL","description":"R52 financial record","status":"posted","currency":"USD","totalDebit":100,"totalCredit":100,"lines":[]}'
);
insert into public.erp_commercial_workflow_documents(
  company_id,id,module,document_type,parent_id,document_number,status,payload
) values(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','a4000000-0000-4000-8000-000000000001',
  'sales','invoice','a1000000-0000-4000-8000-000000000001','R52-DOC','draft',
  '{"partnerName":"R52 Customer","totalAmount":100}'
);
insert into public.erp_records(company_id,entity_type,record_id,payload) values
  ('fresh-company-a','opportunities','r52-opportunity','{"title":"R52 Opportunity","status":"pending","stage":"proposal","expectedValue":500,"currency":"USD"}'),
  ('fresh-company-a','opportunities','r52-crm-link','{"title":"R52 CRM Link","status":"pending","stage":"new","saleId":"a1000000-0000-4000-8000-000000000002"}'),
  ('fresh-company-b','opportunities','r52-b-opportunity','{"title":"R52 B Opportunity","status":"pending","stage":"new","saleId":"b1000000-0000-4000-8000-000000000001"}');

set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}',true);

do $verify$
declare
  v_snapshot jsonb;
  v_retry jsonb;
  v_rows jsonb;
  v_result jsonb;
begin
  v_snapshot:=public.erp_r9_system_monitor_command('snapshot','{}'::jsonb);
  if (v_snapshot->>'pending_sync_operations')::integer<>0
     or (v_snapshot->>'failed_sync_operations')::integer<>0
     or v_snapshot->'oldest_pending_at'<>'null'::jsonb then
    raise exception 'system_monitor_cloud_only_queue_contract_failed:%',v_snapshot;
  end if;
  v_retry:=public.erp_r9_system_monitor_command('retry_server_jobs','{}'::jsonb);
  if (v_retry->>'retried_jobs')::integer<>0 then raise exception 'system_monitor_retry_contract_failed'; end if;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_rows
  from public.erp_r9_list_cloud_master_records(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','erp_inventory'
  ) x;
  if jsonb_array_length(v_rows)<>1 or v_rows->0->>'id'<>'r52-product' then
    raise exception 'r9_master_list_contract_failed:%',v_rows;
  end if;
  v_result:=public.erp_r9_get_cloud_master_record(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','erp_inventory','r52-product'
  );
  if v_result->>'id'<>'r52-product' or (v_result->>'_cloudVersion')::integer<>1 then
    raise exception 'r9_master_get_contract_failed:%',v_result;
  end if;
  if public.erp_r9_get_cloud_master_record(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','erp_inventory','missing'
  ) is not null then raise exception 'r9_missing_master_must_be_null'; end if;

  v_result:=public.erp_r15_reconcile_company_state('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  if not (v_result->>'ok')::boolean then raise exception 'r15_reconcile_failed:%',v_result; end if;
  v_result:=public.erp_r16_current_state_health('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  if not (v_result->>'ok')::boolean then raise exception 'r16_health_failed:%',v_result; end if;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_rows
  from public.erp_r49_cloud_global_search(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','R52',100
  ) x;
  if not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='r52-opportunity')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='a1000000-0000-4000-8000-000000000001')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='a2000000-0000-4000-8000-000000000001')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='a3000000-0000-4000-8000-000000000001')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='r52-car')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='r52-product')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='r52-journal')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='a4000000-0000-4000-8000-000000000001') then
    raise exception 'global_search_module_coverage_failed:%',v_rows;
  end if;
  if exists(select 1 from jsonb_array_elements(v_rows) x where x->>'date' is null) then
    raise exception 'global_search_date_contract_failed:%',v_rows;
  end if;
  if not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='r52-opportunity' and x->>'currency'='USD')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='a1000000-0000-4000-8000-000000000001' and x->>'currency'='USD')
     or not exists(select 1 from jsonb_array_elements(v_rows) x where x->>'id'='a2000000-0000-4000-8000-000000000001' and x->>'currency'='IQD') then
    raise exception 'global_search_currency_contract_failed:%',v_rows;
  end if;
end
$verify$;

-- R50/R51 administrative and delegated success.
select public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

-- Unauthorized member, both cross-tenant directions, invalid and inactive
-- companies must all fail closed with 42501.
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $verify$ begin
  perform public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  raise exception 'unauthorized_member_unexpected_success';
exception when sqlstate '42501' then null; end $verify$;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $verify$ begin
  perform public.erp_r43_reconcile_opportunity_sales_links('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  raise exception 'cross_tenant_a_to_b_unexpected_success';
exception when sqlstate '42501' then null; end $verify$;
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $verify$ begin
  perform public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  raise exception 'cross_tenant_b_to_a_unexpected_success';
exception when sqlstate '42501' then null; end $verify$;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $verify$ begin
  perform public.erp_r43_reconcile_opportunity_sales_links('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
  raise exception 'invalid_company_unexpected_success';
exception when sqlstate '42501' then null; end $verify$;
do $verify$ begin
  perform public.erp_r43_reconcile_opportunity_sales_links('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
  raise exception 'inactive_company_unexpected_success';
exception when sqlstate '42501' then null; end $verify$;

-- Internal implementations and triggers remain inaccessible to browser roles.
do $verify$ begin
  perform public.erp_r37_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  raise exception 'r37_direct_unexpected_success';
exception when insufficient_privilege then null; end $verify$;
do $verify$ begin
  perform public.erp_r37_opportunity_record_link_trigger();
  raise exception 'opportunity_trigger_direct_unexpected_success';
exception when insufficient_privilege then null; end $verify$;
do $verify$ begin
  perform public.erp_r37_sales_order_opportunity_trigger();
  raise exception 'sales_trigger_direct_unexpected_success';
exception when insufficient_privilege then null; end $verify$;

-- Anonymous cannot execute R43.
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
do $verify$ begin
  perform public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  raise exception 'anonymous_unexpected_success';
exception when insufficient_privilege then null; end $verify$;

-- Idempotent retry preserves one active relation and the bridge does not leak.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select public.erp_r43_reconcile_opportunity_sales_links('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
do $verify$
begin
  if coalesce(current_setting('qualityline.r51_reconciliation_permission',true),'')<>'' then
    raise exception 'r51_bridge_marker_leaked';
  end if;
  if (select count(*) from public.erp_sales_orders_cloud
      where company_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        and opportunity_id='r52-crm-link' and not is_deleted)<>1 then
    raise exception 'r50_r51_relation_not_idempotent';
  end if;
end
$verify$;

rollback;

select 'PASS R50-R52 local runtime regression' as result;
