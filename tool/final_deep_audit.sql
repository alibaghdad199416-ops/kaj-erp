\set ON_ERROR_STOP on
begin;

create temporary table audit_constants as
select '11111111-1111-4111-8111-111111111111'::uuid company_id,
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid user_id,
       'audit-r56-r68@example.invalid'::text email;

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
select user_id,'authenticated','authenticated',email,crypt('Audit-R56-R68-Password!',gen_salt('bf')),now(),now(),now(),'{}'::jsonb,'{"audit":true}'::jsonb from audit_constants
on conflict(id) do update set email=excluded.email,encrypted_password=excluded.encrypted_password,email_confirmed_at=excluded.email_confirmed_at,updated_at=now();
insert into public.profiles(id,full_name,is_active) select user_id,'Final Deep Audit',true from audit_constants on conflict(id) do update set full_name=excluded.full_name,is_active=true;
insert into public.company_memberships(company_id,user_id,role_code,is_system_admin,is_active) select company_id,user_id,'owner',true,true from audit_constants on conflict(company_id,user_id) do update set role_code='owner',is_system_admin=true,is_active=true;
select set_config('request.jwt.claim.sub',user_id::text,true) from audit_constants;
select set_config('request.jwt.claim.role','authenticated',true);

do $$
declare v text;
begin
  select string_agg(c.relname,', ' order by c.relname) into v from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p') and c.relname not like 'supabase_%' and c.relname<>'schema_migrations' and exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id') and not c.relrowsecurity;
  if v is not null then raise exception 'FINAL_DEEP_AUDIT RLS_DISABLED: %',v; end if;
  select string_agg(grantee||':'||privilege_type||':'||table_name,', ' order by table_name,grantee,privilege_type) into v from information_schema.role_table_grants where table_schema='public' and grantee in('anon','authenticated') and privilege_type in('INSERT','UPDATE','DELETE') and table_name not like 'supabase_%' and table_name<>'schema_migrations';
  if v is not null then raise exception 'FINAL_DEEP_AUDIT DIRECT_DML_GRANTS: %',v; end if;
end $$;

do $$
declare other_company uuid:='33333333-3333-4333-8333-333333333333';
begin
  insert into public.companies(id,slug,name_ar,name_en,default_currency_code) values(other_company,'audit-other-company','شركة ثانية','Audit Other Company','USD') on conflict(id) do nothing;
  begin perform public.erp_v2300_create_sales_order(other_company,jsonb_build_object('customerId','audit-customer','currency','USD','exchangeRate',1,'items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',10,'description','cross tenant')))); raise exception 'FINAL_DEEP_AUDIT cross-tenant write succeeded'; exception when others then if sqlstate<>'42501' and sqlerrm not like '%tenant_denied%' and sqlerrm not like '%company_membership_required%' then raise; end if; end;
end $$;

insert into public.erp_customers(company_id,id,data,created_by,updated_by) select company_id,'audit-customer',jsonb_build_object('name','Final Audit Customer','currency','USD','isActive',true),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
insert into public.erp_suppliers(company_id,id,data,created_by,updated_by) select company_id,'audit-supplier',jsonb_build_object('name','Final Audit Supplier','currency','USD','isActive',true),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
insert into public.erp_warehouses(company_id,id,data,created_by,updated_by) select company_id,'audit-warehouse',jsonb_build_object('code','AUDIT','name','Final Audit Warehouse','isActive',true),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
insert into public.erp_cars(company_id,id,data,created_by,updated_by) select company_id,'audit-car',jsonb_build_object('brand','Audit','model','E2E','chassis','AUDIT-R56-R68','status','available','warehouse_id','audit-warehouse','warehouseId','audit-warehouse','currency','USD'),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();

do $$
declare c uuid; first_id uuid; retry_id uuid; before_count bigint; after_count bigint;
begin
  select company_id into c from audit_constants;
  select public.erp_v2300_create_sales_order(c,jsonb_build_object('customerId','audit-customer','currency','USD','exchangeRate',1,'opportunityId','AUDIT-SALES-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',1000,'description','Final Audit Vehicle Sale')))) into first_id;
  if first_id is null then raise exception 'sales create returned null'; end if;
  select public.erp_v2300_create_sales_order(c,jsonb_build_object('customerId','audit-customer','currency','USD','exchangeRate',1,'opportunityId','AUDIT-SALES-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',1000,'description','duplicate retry')))) into retry_id;
  if retry_id<>first_id then raise exception 'sales retry not idempotent'; end if;
  select count(*) into before_count from public.erp_sales_orders_cloud where company_id=c;
  begin perform public.erp_v2300_create_sales_order(c,jsonb_build_object('customerId','missing-audit-customer','currency','USD','exchangeRate',1,'items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',10)))); raise exception 'invalid sales order unexpectedly succeeded'; exception when others then if sqlerrm not like '%customer_not_found%' then raise; end if; end;
  select count(*) into after_count from public.erp_sales_orders_cloud where company_id=c;
  if after_count<>before_count then raise exception 'sales rollback left partial state'; end if;
end $$;

do $$
declare c uuid; first_id uuid; retry_id uuid;
begin
  select company_id into c from audit_constants;
  select public.erp_v2300_create_purchase_order(c,jsonb_build_object('supplierId','audit-supplier','currency','USD','exchangeRate',1,'opportunityId','AUDIT-PURCHASE-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitCost',700,'description','Final Audit Vehicle Purchase')))) into first_id;
  if first_id is null then raise exception 'purchase create returned null'; end if;
  select public.erp_v2300_create_purchase_order(c,jsonb_build_object('supplierId','audit-supplier','currency','USD','exchangeRate',1,'opportunityId','AUDIT-PURCHASE-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitCost',700,'description','duplicate retry')))) into retry_id;
  if retry_id<>first_id then raise exception 'purchase retry not idempotent'; end if;
end $$;

do $$
declare company_slug text; initial_updated timestamptz; first_updated timestamptz; payload jsonb; rejected boolean:=false; probe jsonb;
begin
  select slug into company_slug from public.companies where id=(select company_id from audit_constants);
  insert into public.erp_records(company_id,entity_type,record_id,payload,updated_at) values(company_slug,'opportunities','audit-concurrency',jsonb_build_object('id','audit-concurrency','status','pending','auditMarker','AUDIT-R56-R68'),now()) on conflict(company_id,entity_type,record_id) do update set payload=excluded.payload,deleted_at=null,updated_at=now();
  select updated_at into initial_updated from public.erp_records where company_id=company_slug and entity_type='opportunities' and record_id='audit-concurrency';
  payload:=jsonb_build_object('record',jsonb_build_object('id','audit-concurrency','status','pending'),'expected_updated_at',initial_updated::text);
  perform public.erp_r49_opportunity_command('save',payload);
  select updated_at into first_updated from public.erp_records where company_id=company_slug and entity_type='opportunities' and record_id='audit-concurrency';
  if first_updated is null or first_updated=initial_updated then raise exception 'concurrency version did not advance'; end if;
  begin perform public.erp_r49_opportunity_command('save',payload); exception when others then rejected:=sqlstate='40001' or sqlerrm like '%stale_record_conflict%'; end;
  if not rejected then raise exception 'stale update accepted'; end if;
  if to_regprocedure('public.erp_r22_approve_workflow_invoice(uuid,uuid,text)') is null then raise exception 'R22 approval RPC missing'; end if;
  probe:=public.erp_r22_approve_workflow_invoice(c,gen_random_uuid(),'sales');
  if coalesce((probe->>'ok')::boolean,true) then raise exception 'R22 missing-invoice probe unexpectedly succeeded'; end if;
  if coalesce(probe->>'error','') not like '%workflow_invoice_not_found%' then raise exception 'R22 missing-invoice probe returned unexpected error: %',probe; end if;
end $$;

do $$
declare c uuid; d uuid:=gen_random_uuid(); v uuid:=gen_random_uuid();
begin
  select company_id into c from audit_constants;
  insert into public.erp_document_records(company_id,id,data) values(c,d,jsonb_build_object('documentNumber','AUDIT-DOC','titleAr','Final Audit'));
  insert into public.erp_document_versions(company_id,id,data) values(c,v,jsonb_build_object('documentId',d::text,'versionNumber',1));
  begin perform public.erp_register_cloud_document_blob(c,d,v,'other-company/file.bin',4); raise exception 'foreign document path accepted'; exception when others then if sqlerrm not like '%invalid_document_storage_path%' then raise; end if; end;
  perform public.erp_register_cloud_document_blob(c,d,v,c::text||'/'||d::text||'/'||v::text||'.bin',4);
  if not exists(select 1 from public.erp_document_versions where id=v and data->>'storagePath' like c::text||'/%') then raise exception 'canonical storage path not persisted'; end if;
end $$;

commit;
select 'FINAL_DEEP_AUDIT_RUNTIME_PASS' as quality_gate;
