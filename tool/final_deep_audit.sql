\set ON_ERROR_STOP on
begin;

-- Final runtime gate: executable, transactional ERP behavior rather than static existence.
create temporary table audit_constants as
select '11111111-1111-4111-8111-111111111111'::uuid company_id,
       'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid user_id,
       'audit-r56-r68@example.invalid'::text email;

insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at,raw_app_meta_data,raw_user_meta_data)
select user_id,'authenticated','authenticated',email,crypt('Audit-R56-R68-Password!',gen_salt('bf')),now(),now(),now(),'{}'::jsonb,'{"audit":true}'::jsonb from audit_constants
on conflict(id) do update set email=excluded.email,encrypted_password=excluded.encrypted_password,email_confirmed_at=excluded.email_confirmed_at,updated_at=now();
insert into public.profiles(id,full_name,is_active) select user_id,'Final Deep Audit',true from audit_constants on conflict(id) do update set is_active=true;
insert into public.company_memberships(company_id,user_id,role_code,is_system_admin,is_active) select company_id,user_id,'owner',true,true from audit_constants on conflict(company_id,user_id) do update set role_code='owner',is_system_admin=true,is_active=true;
select set_config('request.jwt.claim.sub',user_id::text,true) from audit_constants;
select set_config('request.jwt.claim.role','authenticated',true);

-- Minimal accounting master fixture required by the inventory/cars runtime guards.
insert into public.erp_accounts(organization_id,account_id,code,name,account_type,currency,is_active)
select company_id,'audit-inventory-asset','AUDIT-INV-ASSET','Audit Inventory Asset','asset','USD',true from audit_constants
on conflict(organization_id,account_id) do update set is_active=true;
insert into public.erp_accounts(organization_id,account_id,code,name,account_type,currency,is_active)
select company_id,'audit-cogs-expense','AUDIT-COGS','Audit COGS Expense','expense','USD',true from audit_constants
on conflict(organization_id,account_id) do update set is_active=true;

-- Applied security contract.
do $$
declare v text;
begin
  select string_agg(c.relname,', ' order by c.relname) into v from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in('r','p') and c.relname not like 'supabase_%' and c.relname<>'schema_migrations'
    and exists(select 1 from information_schema.columns x where x.table_schema='public' and x.table_name=c.relname and x.column_name='company_id') and not c.relrowsecurity;
  if v is not null then raise exception 'FINAL_DEEP_AUDIT RLS_DISABLED: %',v; end if;
  select string_agg(grantee||':'||privilege_type||':'||table_name,', ' order by table_name,grantee,privilege_type) into v from information_schema.role_table_grants
  where table_schema='public' and grantee in('anon','authenticated') and privilege_type in('INSERT','UPDATE','DELETE') and table_name not like 'supabase_%' and table_name<>'schema_migrations';
  if v is not null then raise exception 'FINAL_DEEP_AUDIT DIRECT_DML_GRANTS: %',v; end if;
  if has_table_privilege('authenticated','public.erp_notification_user_states','SELECT') then raise exception 'FINAL_DEEP_AUDIT notification state readable'; end if;
  if has_table_privilege('authenticated','public.erp_audit_log','SELECT') then raise exception 'FINAL_DEEP_AUDIT audit log readable'; end if;
  if to_regprocedure('public.erp_open_cloud_service_case(uuid,uuid,text,text,text)') is not null and has_function_privilege('anon',to_regprocedure('public.erp_open_cloud_service_case(uuid,uuid,text,text,text)'),'EXECUTE') then raise exception 'FINAL_DEEP_AUDIT privileged anon RPC grant'; end if;
end $$;

-- Tenant boundary: company A cannot mutate company B through a callable RPC.
do $$
declare other_company uuid:='33333333-3333-4333-8333-333333333333';
begin
  insert into public.companies(id,slug,name_ar,name_en,default_currency_code) values(other_company,'audit-other-company','شركة ثانية','Audit Other Company','USD') on conflict(id) do nothing;
  begin
    perform public.erp_v2300_create_sales_order(other_company,jsonb_build_object('customerId','audit-customer','currency','USD','exchangeRate',1,'items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',10))));
    raise exception 'FINAL_DEEP_AUDIT cross-tenant write succeeded';
  exception when others then
    if sqlstate<>'42501' and sqlerrm not like '%company_membership_required%' then raise; end if;
  end;
end $$;

-- Business fixtures.
insert into public.erp_customers(company_id,id,data,created_by,updated_by) select company_id,'audit-customer',jsonb_build_object('name','Final Audit Customer','currency','USD','isActive',true),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
insert into public.erp_suppliers(company_id,id,data,created_by,updated_by) select company_id,'audit-supplier',jsonb_build_object('name','Final Audit Supplier','currency','USD','isActive',true),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
insert into public.erp_warehouses(company_id,id,data,created_by,updated_by) select company_id,'audit-warehouse',jsonb_build_object('code','AUDIT','name','Final Audit Warehouse','isActive',true),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();
insert into public.erp_cars(company_id,id,data,created_by,updated_by) select company_id,'audit-car',jsonb_build_object('brand','Audit','model','E2E','chassis','AUDIT-R56-R68','status','available','warehouse_id','audit-warehouse','warehouseId','audit-warehouse','currency','USD','purchaseCost',0,'purchase_cost',0,'landedCost',0,'maintenanceCost',0,'unitCost',0,'salePrice',1000,'inventoryAssetAccountId','audit-inventory-asset','inventory_asset_account_id','audit-inventory-asset','salesCostExpenseAccountId','audit-cogs-expense','sales_cost_expense_account_id','audit-cogs-expense'),user_id,user_id from audit_constants on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=now();

-- Sales: create + idempotent retry + rollback on invalid master data.
do $$
declare c uuid; a uuid; b uuid; before_count bigint; after_count bigint;
begin
  select company_id into c from audit_constants;
  select public.erp_v2300_create_sales_order(c,jsonb_build_object('customerId','audit-customer','currency','USD','exchangeRate',1,'opportunityId','AUDIT-SALES-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',1000)))) into a;
  if a is null then raise exception 'sales create returned null'; end if;
  select public.erp_v2300_create_sales_order(c,jsonb_build_object('customerId','audit-customer','currency','USD','exchangeRate',1,'opportunityId','AUDIT-SALES-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',1000)))) into b;
  if b<>a then raise exception 'sales retry not idempotent'; end if;
  select count(*) into before_count from public.erp_sales_orders_cloud where company_id=c;
  begin
    perform public.erp_v2300_create_sales_order(c,jsonb_build_object('customerId','missing','currency','USD','exchangeRate',1,'items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitPrice',10))));
    raise exception 'invalid sale succeeded';
  exception when others then if sqlerrm not like '%customer_not_found%' then raise; end if; end;
  select count(*) into after_count from public.erp_sales_orders_cloud where company_id=c;
  if after_count<>before_count then raise exception 'sales rollback left partial state'; end if;
end $$;

-- Purchases: create + idempotent retry.
do $$
declare c uuid; a uuid; b uuid;
begin
  select company_id into c from audit_constants;
  select public.erp_v2300_create_purchase_order(c,jsonb_build_object('supplierId','audit-supplier','currency','USD','exchangeRate',1,'opportunityId','AUDIT-PURCHASE-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitCost',700)))) into a;
  if a is null then raise exception 'purchase create returned null'; end if;
  select public.erp_v2300_create_purchase_order(c,jsonb_build_object('supplierId','audit-supplier','currency','USD','exchangeRate',1,'opportunityId','AUDIT-PURCHASE-OPP','items',jsonb_build_array(jsonb_build_object('itemType','car','itemId','audit-car','quantity',1,'unitCost',700)))) into b;
  if b<>a then raise exception 'purchase retry not idempotent'; end if;
end $$;

-- Optimistic concurrency: stale version rejected.
do $$
declare t timestamptz; t2 timestamptz; payload jsonb; rejected boolean:=false;
begin
  insert into public.erp_records(company_id,entity_type,record_id,payload,updated_at) values('quality-line','opportunities','audit-concurrency',jsonb_build_object('id','audit-concurrency','status','pending'),now()) on conflict(company_id,entity_type,record_id) do update set payload=excluded.payload,deleted_at=null,updated_at=now();
  select updated_at into t from public.erp_records where company_id='quality-line' and entity_type='opportunities' and record_id='audit-concurrency';
  payload=jsonb_build_object('record',jsonb_build_object('id','audit-concurrency','status','pending'),'expected_updated_at',t::text);
  perform public.erp_r49_opportunity_command('save',payload);
  select updated_at into t2 from public.erp_records where company_id='quality-line' and entity_type='opportunities' and record_id='audit-concurrency';
  if t2=t then raise exception 'concurrency version did not advance'; end if;
  begin perform public.erp_r49_opportunity_command('save',payload); exception when others then rejected:=sqlstate='40001' or sqlerrm like '%stale_record_conflict%'; end;
  if not rejected then raise exception 'stale update accepted'; end if;
end $$;

-- Document storage: canonical path accepted, foreign path rejected.
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

-- Accounting runtime contract.
do $$
declare c uuid; probe jsonb;
begin
  select company_id into c from audit_constants;
  probe:=public.erp_r22_runtime_contract_probe(c);
  if coalesce((probe->>'ok')::boolean,false) is not true then raise exception 'accounting runtime probe failed: %',probe; end if;
end $$;

commit;
select 'FINAL_DEEP_AUDIT_RUNTIME_PASS' as quality_gate;
