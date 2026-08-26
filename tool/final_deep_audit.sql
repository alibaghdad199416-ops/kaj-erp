\set ON_ERROR_STOP on

-- Executable final ERP audit against a disposable local Supabase database.
-- The fixture is isolated to one audit company/user and is rolled back by CI's
-- database reset between runs. Assertions cover security, tenant isolation,
-- sales, purchases, optimistic concurrency, documents, contracts, and the
-- accounting runtime contract.

begin;

create temporary table audit_constants as
select
  '11111111-1111-4111-8111-111111111111'::uuid as company_id,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as user_id,
  'audit-r56-r68@example.invalid'::text as email,
  'AUDIT-R56-R68'::text as marker;

insert into auth.users(
  id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,
  raw_app_meta_data,raw_user_meta_data
)
select user_id,'authenticated','authenticated',email,
       crypt('Audit-R56-R68-Password!',gen_salt('bf')),
       now(),now(),now(),'{}'::jsonb,'{"audit":true}'::jsonb
from audit_constants
on conflict (id) do update set
  email=excluded.email,
  encrypted_password=excluded.encrypted_password,
  email_confirmed_at=excluded.email_confirmed_at,
  updated_at=now();

insert into public.profiles(id,full_name,is_active)
select user_id,'Final Deep Audit',true from audit_constants
on conflict (id) do update set full_name=excluded.full_name,is_active=true;

insert into public.company_memberships(company_id,user_id,role_code,is_system_admin,is_active)
select company_id,user_id,'owner',true,true from audit_constants
on conflict (company_id,user_id) do update set
  role_code='owner',is_system_admin=true,is_active=true;

select set_config('request.jwt.claim.sub',user_id::text,true) from audit_constants;
select set_config('request.jwt.claim.role','authenticated',true);

-- Security invariants must be true in the applied schema, not merely in source.
do $$
declare v text;
begin
  select string_agg(c.relname,', ' order by c.relname) into v
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
    and c.relkind in ('r','p')
    and c.relname not like 'supabase_%'
    and c.relname <> 'schema_migrations'
    and exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id')
    and not c.relrowsecurity;
  if v is not null then raise exception 'FINAL_DEEP_AUDIT RLS_DISABLED: %',v; end if;

  select string_agg(grantee||':'||privilege_type||':'||table_name,', ' order by table_name,grantee,privilege_type) into v
  from information_schema.role_table_grants
  where table_schema='public'
    and grantee in ('anon','authenticated')
    and privilege_type in ('INSERT','UPDATE','DELETE')
    and table_name not like 'supabase_%'
    and table_name <> 'schema_migrations';
  if v is not null then raise exception 'FINAL_DEEP_AUDIT DIRECT_DML_GRANTS: %',v; end if;

  if has_table_privilege('authenticated','public.erp_notification_user_states','SELECT') then
    raise exception 'FINAL_DEEP_AUDIT notification state is directly readable';
  end if;
  if has_table_privilege('authenticated','public.erp_audit_log','SELECT') then
    raise exception 'FINAL_DEEP_AUDIT audit log is directly readable';
  end if;

  if has_function_privilege('anon','public.erp_open_cloud_service_case(uuid,uuid,text,text,text)','EXECUTE') then
    raise exception 'FINAL_DEEP_AUDIT anonymous privileged RPC execute grant remains';
  end if;
end $$;

-- Cross-tenant denial: a valid authenticated user may never use a different
-- company identifier merely because the RPC is callable.
do $$
declare other_company uuid:='33333333-3333-4333-8333-333333333333';
begin
  insert into public.companies(id,slug,name_ar,name_en,default_currency_code)
  values(other_company,'audit-other-company','شركة اختبار ثانية','Audit Other Company','USD')
  on conflict (id) do nothing;
  begin
    perform public.erp_v2300_create_sales_order(
      other_company,
      jsonb_build_object(
        'customerId','audit-customer','currency','USD','exchangeRate',1,
        'items',jsonb_build_array(jsonb_build_object(
          'itemType','car','itemId','audit-car','description','cross tenant','quantity',1,'unitPrice',10
        ))
      )
    );
    raise exception 'FINAL_DEEP_AUDIT cross-tenant sales write unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%company_membership_required%' and sqlstate <> '42501' then raise; end if;
  end;
end $$;

-- Master data fixture.
insert into public.erp_customers(company_id,id,data,created_by,updated_by)
select company_id,'audit-customer',jsonb_build_object(
  'name','Final Audit Customer','phone','07000000001','currency','USD','isActive',true,'auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set
  data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

insert into public.erp_suppliers(company_id,id,data,created_by,updated_by)
select company_id,'audit-supplier',jsonb_build_object(
  'name','Final Audit Supplier','phone','07000000002','currency','USD','isActive',true,'auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set
  data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

insert into public.erp_warehouses(company_id,id,data,created_by,updated_by)
select company_id,'audit-warehouse',jsonb_build_object(
  'code','AUDIT','name','Final Audit Warehouse','isActive',true,'warehouseType','normal','auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set
  data=excluded.data,is_deleted=false,deleted_at=null,updated_by=excluded.updated_by,updated_at=now();

insert into public.erp_cars(company_id,id,data,created_by,updated_by)
select company_id,'audit-car',jsonb_build_object(
  'brand','Audit','model','E2E','chassis','AUDIT-R56-R68-CHASSIS',
  'status','available','warehouse_id','audit-warehouse','warehouseId','audit-warehouse',
  'currency','USD','auditMarker',marker
),user_id,user_id from audit_constants
on conflict (company_id,id) do update set
  data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();

-- Sales: successful create, deterministic duplicate retry, and atomic rollback.
do $$
declare
  c uuid;
  first_id uuid;
  second_id uuid;
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
  )) into first_id;
  if first_id is null then raise exception 'sales create returned null'; end if;

  select public.erp_v2300_create_sales_order(c,jsonb_build_object(
    'customerId','audit-customer','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-SALES-OPP','notes','DUPLICATE RETRY',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitPrice',1000
    ))
  )) into second_id;
  if second_id <> first_id then raise exception 'sales duplicate opportunity was not idempotent'; end if;

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
  if after_count <> before_count then raise exception 'sales rollback left partial state'; end if;
end $$;

-- Purchases: successful create plus deterministic duplicate retry.
do $$
declare
  c uuid;
  first_id uuid;
  second_id uuid;
begin
  select company_id into c from audit_constants;
  select public.erp_v2300_create_purchase_order(c,jsonb_build_object(
    'supplierId','audit-supplier','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-PURCHASE-OPP','notes','FINAL DEEP AUDIT',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitCost',700
    ))
  )) into first_id;
  if first_id is null then raise exception 'purchase create returned null'; end if;

  select public.erp_v2300_create_purchase_order(c,jsonb_build_object(
    'supplierId','audit-supplier','currency','USD','exchangeRate',1,
    'discount',0,'opportunityId','AUDIT-PURCHASE-OPP','notes','DUPLICATE RETRY',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','car','itemId','audit-car','description','Audit vehicle','quantity',1,'unitCost',700
    ))
  )) into second_id;
  if second_id <> first_id then raise exception 'purchase duplicate opportunity was not idempotent'; end if;
end $$;

-- Optimistic concurrency: a stale snapshot must be rejected after the first
-- write advances updated_at.
do $$
declare
  initial_updated timestamptz;
  first_updated timestamptz;
  payload jsonb;
  stale_rejected boolean:=false;
begin
  insert into public.erp_records(company_id,entity_type,record_id,payload,updated_at)
  values('quality-line','opportunities','audit-concurrency',jsonb_build_object(
    'id','audit-concurrency','opportunityNumber','AUDIT-CONCURRENCY','status','pending','auditMarker','AUDIT-R56-R68'
  ),now())
  on conflict(company_id,entity_type,record_id) do update set
    payload=excluded.payload,deleted_at=null,updated_at=now();
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
    perform public.erp_r49_opportunity_command('save',payload);
  exception when others then
    stale_rejected:=sqlstate='40001' or sqlerrm like '%stale_record_conflict%';
  end;
  if not stale_rejected then raise exception 'stale concurrent update was accepted'; end if;
end $$;

-- Document registration: cross-tenant storage paths are rejected while the
-- canonical company/document/version path is persisted.
do $$
declare
  c uuid;
  doc_id uuid:=gen_random_uuid();
  version_id uuid:=gen_random_uuid();
begin
  select company_id into c from audit_constants;
  insert into public.erp_document_records(company_id,id,data)
  values(c,doc_id,jsonb_build_object('documentNumber','AUDIT-DOC','titleAr','Final Audit','auditMarker','AUDIT-R56-R68'));
  insert into public.erp_document_versions(company_id,id,data)
  values(c,version_id,jsonb_build_object('documentId',doc_id::text,'versionNumber',1));

  begin
    perform public.erp_register_cloud_document_blob(c,doc_id,version_id,'other-company/file.bin',4);
    raise exception 'cross-tenant storage path unexpectedly accepted';
  exception when others then
    if sqlerrm not like '%invalid_document_storage_path%' then raise; end if;
  end;

  perform public.erp_register_cloud_document_blob(
    c,doc_id,version_id,c::text||'/'||doc_id::text||'/'||version_id::text||'.bin',4
  );
  if not exists(
    select 1 from public.erp_document_versions
    where id=version_id and data->>'storagePath' like c::text||'/%'
  ) then raise exception 'document storage registration did not persist canonical path'; end if;
end $$;

-- Contract lifecycle: review -> approval -> signature -> active.
do $$
declare
  c uuid;
  contract_id uuid:=gen_random_uuid();
  version_id uuid:=gen_random_uuid();
  review_id uuid;
  approval_id uuid;
  signature_id uuid;
begin
  select company_id into c from audit_constants;
  insert into public.erp_contracts(company_id,id,data)
  values(c,contract_id,jsonb_build_object('contractNumber','AUDIT-CONTRACT','titleAr','Final Audit Contract','status','draft','auditMarker','AUDIT-R56-R68'));
  insert into public.erp_contract_versions(company_id,id,data)
  values(c,version_id,jsonb_build_object('contractId',contract_id::text,'versionNumber',1));
  select public.erp_request_cloud_contract_review(c,contract_id,'audit-user','owner','Final Deep Audit') into review_id;
  perform public.erp_complete_cloud_contract_review(c,review_id,true,'accepted','Final Deep Audit');
  select public.erp_submit_cloud_contract_approval(c,contract_id,'Final Deep Audit') into approval_id;
  perform public.erp_decide_cloud_contract_approval(c,approval_id,true,'Final Deep Audit','accepted');
  select public.erp_request_cloud_contract_signature(c,contract_id,'Final Deep Audit','owner',null,null,'Final Deep Audit') into signature_id;
  perform public.erp_complete_cloud_contract_signature(c,signature_id,'AUDIT-SIGNATURE-HASH','Final Deep Audit');
  perform public.erp_transition_cloud_contract(c,contract_id,'activate','signed','Final Deep Audit');
  if not exists(select 1 from public.erp_contracts where id=contract_id and data->>'status'='active') then
    raise exception 'contract lifecycle did not reach active';
  end if;
end $$;

-- Accounting runtime contract must execute and affirm the current canonical
-- state rather than merely existing in pg_proc.
do $$
declare
  c uuid;
  probe jsonb;
begin
  select company_id into c from audit_constants;
  probe:=public.erp_r22_runtime_contract_probe(c);
  if coalesce((probe->>'ok')::boolean,false) is not true then
    raise exception 'runtime accounting contract probe returned non-ok: %',probe;
  end if;
end $$;

commit;
select 'FINAL_DEEP_AUDIT_RUNTIME_PASS' as quality_gate;
