\set ON_ERROR_STOP on

-- Final Deep Audit runtime fixture. This script is intentionally destructive only
-- to rows carrying the AUDIT-R56-R68 marker and is executed against a disposable
-- local Supabase database in CI.

begin;

create temporary table audit_constants as
select
  '11111111-1111-4111-8111-111111111111'::uuid as company_id,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as user_id,
  'audit-r56-r68@example.invalid'::text as email,
  'AUDIT-R56-R68'::text as marker;

-- Auth + tenant fixture.
insert into auth.users(
  id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,
  raw_app_meta_data,raw_user_meta_data
)
select user_id,'authenticated','authenticated',email,crypt('Audit-R56-R68-Password!',gen_salt('bf')),
       now(),now(),now(),'{}'::jsonb,'{"audit":true}'::jsonb
from audit_constants
on conflict (id) do update set email=excluded.email, encrypted_password=excluded.encrypted_password,
  email_confirmed_at=excluded.email_confirmed_at, updated_at=now();

insert into public.profiles(id,full_name,is_active)
select user_id,'Final Deep Audit',true from audit_constants
on conflict (id) do update set full_name=excluded.full_name,is_active=true;

insert into public.company_memberships(company_id,user_id,role_code,is_system_admin,is_active)
select company_id,user_id,'owner',true,true from audit_constants
on conflict (company_id,user_id) do update set role_code='owner',is_system_admin=true,is_active=true;

-- Simulate an authenticated PostgREST request for the remainder of the test.
select set_config('request.jwt.claim.sub',user_id::text,true) from audit_constants;
select set_config('request.jwt.claim.role','authenticated',true);

-- Static/runtime surface checks that CI must execute against the applied schema.
do $$
declare
  required_table text;
  required_function text;
  r record;
begin
  foreach required_table in array array[
    'erp_cars','erp_customers','erp_suppliers','erp_sales_orders_cloud',
    'erp_purchase_orders_cloud','erp_sales_order_items_cloud','erp_purchase_order_items_cloud',
    'erp_warehouse_stock','erp_inventory_movements','erp_audit_log',
    'erp_document_records','erp_document_versions','erp_contracts',
    'erp_enterprise_notifications'
  ] loop
    if to_regclass('public.'||required_table) is null then
      raise exception 'FINAL_DEEP_AUDIT missing table: %',required_table;
    end if;
  end loop;

  foreach required_function in array array[
    'erp_r22_runtime_contract_probe','erp_r22_reconcile_company_state',
    'erp_v2300_create_sales_order','erp_v2300_create_purchase_order',
    'erp_r49_create_sales_order','erp_r49_create_purchase_order',
    'erp_r49_update_sales_order','erp_r49_update_purchase_order',
    'erp_v2300_transfer_cloud_cash','erp_v2300_transfer_inventory_stock_batch',
    'erp_r49_opportunity_command','erp_v2300_audit_feed',
    'erp_register_cloud_document_blob'
  ] loop
    if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                  where n.nspname='public' and p.proname=required_function) then
      raise exception 'FINAL_DEEP_AUDIT missing function: %',required_function;
    end if;
  end loop;

  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in (
      'erp_cars','erp_customers','erp_suppliers','erp_sales_orders_cloud',
      'erp_purchase_orders_cloud','erp_inventory_movements','erp_warehouse_stock',
      'erp_document_records','erp_document_versions','erp_contracts','erp_audit_log'
    ) and not c.relrowsecurity
  loop
    raise exception 'FINAL_DEEP_AUDIT RLS disabled: %',r.relname;
  end loop;
end $$;

-- Master data fixture: partner + warehouse + vehicle.
insert into public.erp_customers(company_id,id,data,created_by,updated_by)
select company_id,'audit-customer',jsonb_build_object(
  'name','Final Audit Customer','phone','07000000001','currency','USD','isActive',true,'auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

insert into public.erp_suppliers(company_id,id,data,created_by,updated_by)
select company_id,'audit-supplier',jsonb_build_object(
  'name','Final Audit Supplier','phone','07000000002','currency','USD','isActive',true,'auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

insert into public.erp_warehouses(company_id,id,data,created_by,updated_by)
select company_id,'audit-warehouse',jsonb_build_object(
  'code','AUDIT','name','Final Audit Warehouse','isActive',true,'warehouseType','normal','auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

insert into public.erp_cars(company_id,id,data,created_by,updated_by)
select company_id,'audit-car',jsonb_build_object(
  'brand','Audit','model','E2E','chassis','AUDIT-R56-R68-CHASSIS',
  'status','available','warehouse_id','audit-warehouse','warehouseId','audit-warehouse',
  'currency','USD','auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

-- Real sales + purchases: success path, duplicate/idempotency path, and rollback.
do $$
declare
  c uuid;
  p uuid;
  c2 uuid;
  before_count bigint;
  after_count bigint;
begin
  select company_id into c from audit_constants;

  select public.erp_v2300_create_sales_order(c,jsonb_build_object(
    'customerId','audit-customer','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-SALES-OPP','notes','FINAL DEEP AUDIT',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitPrice',1000
    ))
  )) into p;
  if p is null then raise exception 'sales create returned null'; end if;

  select public.erp_v2300_create_sales_order(c,jsonb_build_object(
    'customerId','audit-customer','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-SALES-OPP','notes','DUPLICATE RETRY',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitPrice',1000
    ))
  )) into c2;
  if c2 <> p then raise exception 'sales duplicate opportunity was not idempotent'; end if;

  select count(*) into before_count from public.erp_sales_orders_cloud where company_id=c;
  begin
    perform public.erp_v2300_create_sales_order(c,jsonb_build_object(
      'customerId','missing-audit-customer','currency','USD','exchangeRate',1,
      'items',jsonb_build_array(jsonb_build_object(
        'itemType','car','itemId','audit-car','description','rollback','quantity',1,'unitPrice',10
      ))
    ));
    raise exception 'invalid sales order unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%customer_not_found%' then raise; end if;
  end;
  select count(*) into after_count from public.erp_sales_orders_cloud where company_id=c;
  if after_count <> before_count then raise exception 'sales rollback left a partial order'; end if;

  select public.erp_v2300_create_purchase_order(c,jsonb_build_object(
    'supplierId','audit-supplier','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-PURCHASE-OPP','notes','FINAL DEEP AUDIT',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitCost',700
    ))
  )) into p;
  if p is null then raise exception 'purchase create returned null'; end if;

  select public.erp_v2300_create_purchase_order(c,jsonb_build_object(
    'supplierId','audit-supplier','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-PURCHASE-OPP','notes','DUPLICATE RETRY',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitCost',700
    ))
  )) into c2;
  if c2 <> p then raise exception 'purchase duplicate opportunity was not idempotent'; end if;
end $$;

-- Optimistic-concurrency path: two writes from one stale snapshot must not both win.
do $$
declare
  company_id uuid;
  initial_updated timestamptz;
  first_updated timestamptz;
  stale_rejected boolean:=false;
  payload jsonb;
begin
  select a.company_id into company_id from audit_constants a;
  insert into public.erp_records(company_id,entity_type,record_id,payload,updated_at)
  select 'quality-line','opportunities','audit-concurrency',jsonb_build_object(
    'id','audit-concurrency','opportunityNumber','AUDIT-CONCURRENCY','status','pending','auditMarker','AUDIT-R56-R68'
  ),now()
  on conflict(company_id,entity_type,record_id) do update set payload=excluded.payload,deleted_at=null,updated_at=now();
  select updated_at into initial_updated from public.erp_records
  where company_id='quality-line' and entity_type='opportunities' and record_id='audit-concurrency';

  payload:=jsonb_build_object(
    'record',jsonb_build_object('id','audit-concurrency','opportunityNumber','AUDIT-CONCURRENCY','status','pending'),
    'expected_updated_at',initial_updated::text
  );
  perform public.erp_r49_opportunity_command('save',payload);
  select updated_at into first_updated from public.erp_records
  where company_id='quality-line' and entity_type='opportunities' and record_id='audit-concurrency';
  if first_updated is null or first_updated=initial_updated then raise exception 'concurrency update did not advance version'; end if;

  begin
    payload:=jsonb_set(payload,'{record,status}','"pending"'::jsonb,true);
    perform public.erp_r49_opportunity_command('save',payload);
  exception when others then
    stale_rejected:=sqlstate='40001' or sqlerrm like '%stale_record_conflict%';
  end;
  if not stale_rejected then raise exception 'stale concurrent update was accepted'; end if;
end $$;

-- Documents: DB registration must reject wrong-tenant paths and accept the canonical path.
do $$
declare
  company_id uuid;
  doc_id uuid:=gen_random_uuid();
  version_id uuid:=gen_random_uuid();
begin
  select a.company_id into company_id from audit_constants a;
  insert into public.erp_document_records(company_id,id,data)
  values(company_id,doc_id,jsonb_build_object('documentNumber','AUDIT-DOC','titleAr','Final Audit','auditMarker','AUDIT-R56-R68'));
  insert into public.erp_document_versions(company_id,id,data)
  values(company_id,version_id,jsonb_build_object('documentId',doc_id::text,'versionNumber',1));
  begin
    perform public.erp_register_cloud_document_blob(company_id,doc_id,version_id,'other-company/file.bin',4);
    raise exception 'cross-tenant storage path unexpectedly accepted';
  exception when others then
    if sqlerrm not like '%invalid_document_storage_path%' then raise; end if;
  end;
  perform public.erp_register_cloud_document_blob(company_id,doc_id,version_id,company_id::text||'/'||doc_id::text||'/'||version_id::text||'.bin',4);
  if not exists(select 1 from public.erp_document_versions where id=version_id and data->>'storagePath' like company_id::text||'/%') then
    raise exception 'document storage registration did not persist canonical path';
  end if;
end $$;

-- Contract lifecycle: review -> approval -> signature -> active.
do $$
declare
  company_id uuid;
  contract_id uuid:=gen_random_uuid();
  version_id uuid:=gen_random_uuid();
  review_id uuid;
  approval_id uuid;
  signature_id uuid;
begin
  select a.company_id into company_id from audit_constants a;
  insert into public.erp_contracts(company_id,id,data)
  values(company_id,contract_id,jsonb_build_object('contractNumber','AUDIT-CONTRACT','titleAr','Final Audit Contract','status','draft','auditMarker','AUDIT-R56-R68'));
  insert into public.erp_contract_versions(company_id,id,data)
  values(company_id,version_id,jsonb_build_object('contractId',contract_id::text,'versionNumber',1));
  select public.erp_request_cloud_contract_review(company_id,contract_id,'audit-user','owner','Final Deep Audit') into review_id;
  perform public.erp_complete_cloud_contract_review(company_id,review_id,true,'accepted','Final Deep Audit');
  select public.erp_submit_cloud_contract_approval(company_id,contract_id,'Final Deep Audit') into approval_id;
  perform public.erp_decide_cloud_contract_approval(company_id,approval_id,true,'Final Deep Audit','accepted');
  select public.erp_request_cloud_contract_signature(company_id,contract_id,'Final Deep Audit','owner',null,null,'Final Deep Audit') into signature_id;
  perform public.erp_complete_cloud_contract_signature(company_id,signature_id,'AUDIT-SIGNATURE-HASH','Final Deep Audit');
  perform public.erp_transition_cloud_contract(company_id,contract_id,'activate','signed','Final Deep Audit');
  if not exists(select 1 from public.erp_contracts where id=contract_id and data->>'status'='active') then
    raise exception 'contract lifecycle did not reach active';
  end if;
end $$;

-- Runtime accounting probe must be callable and return an affirmative contract.
do $$
declare
  company_id uuid;
  probe jsonb;
begin
  select a.company_id into company_id from audit_constants a;
  probe:=public.erp_r22_runtime_contract_probe(company_id);
  if coalesce((probe->>'ok')::boolean,false) is not true then
    raise exception 'runtime contract probe returned non-ok: %',probe;
  end if;
end $$;

commit;

-- Cleanup is intentionally outside the transaction so failed assertions leave
-- enough database evidence in CI logs. The CI wrapper runs db reset for isolation.
