\set ON_ERROR_STOP on
\pset pager off

-- R56.1 executable acceptance proof. Every fixture is transaction-local.
begin;
set local session_replication_role=replica;

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('00000000-0000-0000-0000-000000000000','56010000-0000-4000-8000-000000000001',
 'authenticated','authenticated','r56.1@local.invalid','',now(),'{}','{}',now(),now());
insert into public.companies(id,slug,name_ar,name_en,is_active) values
('56010000-0000-4000-8000-000000000010','r56-1-a','R56.1 A','R56.1 A',true),
('56010000-0000-4000-8000-000000000011','r56-1-b','R56.1 B','R56.1 B',true);
insert into public.company_memberships(company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active) values
('56010000-0000-4000-8000-000000000010','56010000-0000-4000-8000-000000000001',
 '56010000-0000-4000-8000-000000000001','r56.1@local.invalid','admin',true,true);

insert into public.erp_customers(company_id,id,data) values
('56010000-0000-4000-8000-000000000010','56010000-0000-4000-8000-000000000020','{"name":"R56 Customer","currency":"USD"}'),
('56010000-0000-4000-8000-000000000011','56010000-0000-4000-8000-000000000021','{"name":"Other Customer"}');
insert into public.erp_suppliers(company_id,id,data) values
('56010000-0000-4000-8000-000000000010','r56-supplier','{"name":"R56 Supplier","currency":"IQD"}');
insert into public.erp_warehouses(company_id,id,data) values
('56010000-0000-4000-8000-000000000010','r56-warehouse','{"name":"R56 Warehouse","isActive":true}');
insert into public.erp_cars(company_id,id,data) values
('56010000-0000-4000-8000-000000000010','r56-car-a','{"carNumber":"CAR-A","brand":"Quality","model":"A","purchasePrice":987654.32}'),
('56010000-0000-4000-8000-000000000010','r56-car-b','{"carNumber":"CAR-B","brand":"Quality","model":"B","inventoryValue":876543.21}'),
('56010000-0000-4000-8000-000000000011','r56-car-other','{"carNumber":"OTHER"}');

-- Approved sales invoices establish the canonical sold-vehicle/customer relationship.
insert into public.erp_sales_orders_cloud(id,company_id,order_number,customer_id,status,currency,
  exchange_rate,subtotal,discount,total) values
('56010000-0000-4000-8000-000000000030','56010000-0000-4000-8000-000000000010','R56-SO-A',
 '56010000-0000-4000-8000-000000000020','completed','USD',1,1000,0,1000),
('56010000-0000-4000-8000-000000000031','56010000-0000-4000-8000-000000000010','R56-SO-B',
 '56010000-0000-4000-8000-000000000020','completed','USD',1,1200,0,1200);
insert into public.erp_sales_order_items_cloud(company_id,order_id,item_type,item_id,description,
  quantity,unit_price,line_total) values
('56010000-0000-4000-8000-000000000010','56010000-0000-4000-8000-000000000030','car','r56-car-a','Car A',1,1000,1000),
('56010000-0000-4000-8000-000000000010','56010000-0000-4000-8000-000000000031','car','r56-car-b','Car B',1,1200,1200);
insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,
  document_number,status,payload,created_at) values
('56010000-0000-4000-8000-000000000040','56010000-0000-4000-8000-000000000010','sales','invoice',
 '56010000-0000-4000-8000-000000000030','R56-SINV-A','approved','{"currency":"USD","totalAmount":1000}',now()-interval '4 days'),
('56010000-0000-4000-8000-000000000041','56010000-0000-4000-8000-000000000010','sales','invoice',
 '56010000-0000-4000-8000-000000000031','R56-SINV-B','approved','{"currency":"USD","totalAmount":1200}',now()-interval '3 days');
insert into public.erp_records(company_id,entity_type,record_id,payload) values
('r56-1-a','opportunities','r56-opp-car','{"opportunityNumber":"R56-OPP-CAR","title":"With car","customerId":"56010000-0000-4000-8000-000000000020","carId":"r56-car-a","status":"pending","stage":"new","currency":"USD","createdAt":"2026-08-11T08:00:00Z"}'),
('r56-1-a','opportunities','r56-opp-no-car','{"opportunityNumber":"R56-OPP-NO-CAR","title":"Without car","customerId":"56010000-0000-4000-8000-000000000020","status":"pending","stage":"new","currency":"USD","createdAt":"2026-08-11T09:00:00Z"}'),
('r56-1-b','opportunities','r56-opp-other','{"opportunityNumber":"OTHER","customerId":"56010000-0000-4000-8000-000000000021","carId":"r56-car-other"}');

-- Complete commercial fixtures for both partner types.
insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,
 document_number,status,payload) values
('56010000-0000-4000-8000-000000000042','56010000-0000-4000-8000-000000000010','sales','delivery','56010000-0000-4000-8000-000000000030','R56-SDEL','approved','{"currency":"USD","totalAmount":1000}'),
('56010000-0000-4000-8000-000000000043','56010000-0000-4000-8000-000000000010','sales','payment','56010000-0000-4000-8000-000000000030','R56-SPAY','approved','{"currency":"USD","totalAmount":1000,"paidAmount":1000,"remainingAmount":0}');
insert into public.erp_purchase_orders_cloud(id,company_id,order_number,supplier_id,status,currency,
 exchange_rate,subtotal,discount,total) values
('56010000-0000-4000-8000-000000000050','56010000-0000-4000-8000-000000000010','R56-PO','r56-supplier','approved','IQD',1,500,0,500);
insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,
 document_number,status,payload) values
('56010000-0000-4000-8000-000000000051','56010000-0000-4000-8000-000000000010','purchases','receipt','56010000-0000-4000-8000-000000000050','R56-PREC','approved','{"currency":"IQD","totalAmount":500}'),
('56010000-0000-4000-8000-000000000052','56010000-0000-4000-8000-000000000010','purchases','invoice','56010000-0000-4000-8000-000000000050','R56-PINV','approved','{"currency":"IQD","totalAmount":500}'),
('56010000-0000-4000-8000-000000000053','56010000-0000-4000-8000-000000000010','purchases','payment','56010000-0000-4000-8000-000000000050','R56-PPAY','approved','{"currency":"IQD","paidAmount":300,"remainingAmount":200}');

insert into public.erp_accounts(organization_id,account_id,code,name,account_type,currency,
 opening_balance,is_active,source_updated_at,synced_at,synced_by) values
('56010000-0000-4000-8000-000000000010','r56-customer-usd','1201','Customer USD','asset','USD',10,true,now(),now(),'56010000-0000-4000-8000-000000000001'),
('56010000-0000-4000-8000-000000000010','r56-customer-iqd','1202','Customer IQD','asset','IQD',20,true,now(),now(),'56010000-0000-4000-8000-000000000001'),
('56010000-0000-4000-8000-000000000010','r56-supplier-usd','2101','Supplier USD','liability','USD',30,true,now(),now(),'56010000-0000-4000-8000-000000000001'),
('56010000-0000-4000-8000-000000000010','r56-supplier-iqd','2102','Supplier IQD','liability','IQD',40,true,now(),now(),'56010000-0000-4000-8000-000000000001');
insert into public.erp_accounts(organization_id,account_id,code,name,account_type,currency,
 opening_balance,is_active,source_updated_at,synced_at,synced_by) values
('56010000-0000-4000-8000-000000000011','r56-other-usd','1299','Other tenant USD','asset','USD',999,true,now(),now(),'56010000-0000-4000-8000-000000000001');
insert into public.erp_partner_accounts(organization_id,partner_type,partner_id,partner_name,
 usd_account_id,iqd_account_id,is_active,source_updated_at,synced_at,synced_by) values
('56010000-0000-4000-8000-000000000010','customer','56010000-0000-4000-8000-000000000020','R56 Customer','r56-customer-usd','r56-customer-iqd',true,now(),now(),'56010000-0000-4000-8000-000000000001'),
('56010000-0000-4000-8000-000000000010','supplier','r56-supplier','R56 Supplier','r56-supplier-usd','r56-supplier-iqd',true,now(),now(),'56010000-0000-4000-8000-000000000001');
insert into public.erp_partner_accounts(organization_id,partner_type,partner_id,partner_name,
 usd_account_id,iqd_account_id,is_active,source_updated_at,synced_at,synced_by) values
('56010000-0000-4000-8000-000000000011','customer','56010000-0000-4000-8000-000000000021','Other Customer','r56-other-usd',null,true,now(),now(),'56010000-0000-4000-8000-000000000001');

insert into public.erp_journal_entries(company_id,id,data) values
('56010000-0000-4000-8000-000000000010','r56-customer-entry','{"entryNumber":"R56-CJ-USD","date":"2026-08-11","referenceType":"sales_invoice","referenceId":"R56-SINV-A"}'),
('56010000-0000-4000-8000-000000000010','r56-supplier-entry','{"entryNumber":"R56-SJ-IQD","date":"2026-08-11","referenceType":"purchases_invoice","referenceId":"R56-PINV"}'),
('56010000-0000-4000-8000-000000000011','r56-other-entry','{"entryNumber":"R56-OTHER-JOURNAL","date":"2026-08-11","referenceType":"sales_invoice","referenceId":"R56-OTHER"}');
insert into public.erp_journal_lines(company_id,id,data) values
('56010000-0000-4000-8000-000000000010','r56-customer-line','{"entryId":"r56-customer-entry","accountId":"r56-customer-usd","date":"2026-08-11","debit":125,"credit":25,"description":"R56 customer ledger"}'),
('56010000-0000-4000-8000-000000000010','r56-supplier-line','{"entryId":"r56-supplier-entry","accountId":"r56-supplier-iqd","date":"2026-08-11","debit":0,"credit":75,"description":"R56 supplier ledger"}'),
('56010000-0000-4000-8000-000000000011','r56-other-line','{"entryId":"r56-other-entry","accountId":"r56-other-usd","date":"2026-08-11","debit":999,"credit":0,"description":"R56 cross tenant sentinel"}');

set local session_replication_role=origin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"56010000-0000-4000-8000-000000000001","role":"authenticated"}',true);
-- Return to the local database owner for direct boundary/trigger probes while
-- retaining the authenticated JWT claims consumed by active-company guards.
reset role;

do $verify$
declare
 c constant uuid:='56010000-0000-4000-8000-000000000010';
 customer constant uuid:='56010000-0000-4000-8000-000000000020';
 with_car uuid; with_car_retry uuid; without_car uuid; another_a uuid; history jsonb; profile jsonb;
 boundary_before bigint; boundary_after bigint; denied boolean;
begin
 select count(*) into boundary_before from (
   select id::text from public.erp_commercial_workflow_documents where company_id=c
   union all select id from public.erp_cash_transactions where company_id=c
   union all select id from public.erp_journal_entries where company_id=c
   union all select id from public.erp_inventory_movements where company_id=c
 ) x;

 with_car:=public.erp_r56_create_cloud_maintenance_order(c,'r56-car-a','r56-warehouse','paid',10,100,
   'USD',1,'with car','[]','r56-opp-car',null,'2026-08-11T10:00:00Z');
 with_car_retry:=public.erp_r56_create_cloud_maintenance_order(c,'r56-car-a','r56-warehouse','paid',10,100,
   'USD',1,'retry','[]','r56-opp-car',null,'2026-08-11T10:01:00Z');
 if with_car<>with_car_retry then raise exception 'r56_linked_create_not_idempotent'; end if;
 if not exists(select 1 from public.erp_maintenance_orders where id=with_car and company_id=c
   and customer_id=customer and source_car_id='r56-car-a' and opportunity_id='r56-opp-car'
   and opportunity_number='R56-OPP-CAR') then raise exception 'r56_with_car_relationship_failed'; end if;

 without_car:=public.erp_r56_create_cloud_maintenance_order(c,'r56-car-b','r56-warehouse','paid',5,75,
   'USD',1,'explicit car','[]','r56-opp-no-car',null,'2026-08-11T11:00:00Z');
 if not exists(select 1 from public.erp_maintenance_orders where id=without_car and source_car_id='r56-car-b'
   and opportunity_id='r56-opp-no-car') then raise exception 'r56_no_car_explicit_selection_failed'; end if;
 another_a:=public.erp_r56_create_cloud_maintenance_order(c,'r56-car-a','r56-warehouse','free',0,0,
   'USD',1,'later history','[]',null,null,'2026-08-11T12:00:00Z');

 select count(*) into boundary_after from (
   select id::text from public.erp_commercial_workflow_documents where company_id=c
   union all select id from public.erp_cash_transactions where company_id=c
   union all select id from public.erp_journal_entries where company_id=c
   union all select id from public.erp_inventory_movements where company_id=c
 ) x;
 if boundary_after<>boundary_before then raise exception 'r56_maintenance_created_downstream_side_effect'; end if;

 denied:=false; begin
   perform public.erp_r56_create_cloud_maintenance_order(c,'r56-car-other','r56-warehouse','paid',0,1,
    'USD',1,'wrong tenant','[]',null,null,now());
 exception when others then denied:=true; end;
 if not denied then raise exception 'r56_cross_company_vehicle_allowed'; end if;
 denied:=false; begin
   update public.erp_maintenance_orders set opportunity_id='r56-opp-other' where id=without_car;
 exception when others then denied:=true; end;
 if not denied then raise exception 'r56_cross_company_opportunity_allowed'; end if;
 denied:=false; begin
   update public.erp_maintenance_orders set source_car_id='r56-car-a' where id=without_car;
 exception when others then denied:=true; end;
 if not denied then raise exception 'r56_historical_vehicle_mutable'; end if;
 denied:=false; begin
   update public.erp_maintenance_orders set customer_id='56010000-0000-4000-8000-000000000021'
    where id=without_car;
 exception when others then denied:=true; end;
 if not denied then raise exception 'r56_opportunity_customer_mismatch_allowed'; end if;

 update public.erp_maintenance_orders set workflow_stage='cancelled',status='cancelled',
  cancelled_at=now(),cancel_reason='runtime cancellation' where id=with_car;
 history:=public.erp_r56_vehicle_service_card(c,'r56-car-a');
 if jsonb_array_length(history->'maintenanceHistory')<>2
    or history->'maintenanceHistory'->0->>'id'<>another_a::text
    or history->'maintenanceHistory'->1->>'cancelReason'<>'runtime cancellation'
    or history::text ~* '(987654.32|876543.21|purchasePrice|unitCost|partsCost|profit)' then
   raise exception 'r56_vehicle_history_or_privacy_failed:%',history;
 end if;
 if history::text like '%r56-car-b%' then raise exception 'r56_vehicle_history_cross_vehicle_leak'; end if;

 profile:=public.erp_r56_business_partner_360(c,'customer',customer::text);
 if not (profile->'commercialChain' @> '[{"documentNumber":"R56-SDEL"}]'
   and profile->'commercialChain' @> '[{"documentNumber":"R56-SINV-A"}]'
   and profile->'commercialChain' @> '[{"documentNumber":"R56-SPAY"}]'
   and profile->'crmOpportunities' @> '[{"opportunityNumber":"R56-OPP-CAR"}]'
   and profile->'maintenanceHistory' @> '[{"entityType":"maintenance"}]'
   and profile->'accountsByCurrency' @> '[{"currencyCode":"USD","debit":125,"credit":25,"currentBalance":110},{"currencyCode":"IQD","currentBalance":20}]'
   and profile->'ledgerMovements' @> '[{"entryNumber":"R56-CJ-USD","documentType":"sales_invoice","documentReference":"R56-SINV-A","debit":125,"credit":25,"currency":"USD"}]'
   and profile::text not like '%R56-OTHER-JOURNAL%') then
   raise exception 'r56_customer_360_incomplete:%',profile;
 end if;
 profile:=public.erp_r56_business_partner_360(c,'supplier','r56-supplier');
 if not (profile->'commercialChain' @> '[{"documentNumber":"R56-PREC"}]'
   and profile->'commercialChain' @> '[{"documentNumber":"R56-PINV"}]'
   and profile->'commercialChain' @> '[{"documentNumber":"R56-PPAY"}]'
   and profile->'accountsByCurrency' @> '[{"currencyCode":"USD","currentBalance":30},{"currencyCode":"IQD","debit":0,"credit":75,"currentBalance":-35}]'
   and profile->'ledgerMovements' @> '[{"entryNumber":"R56-SJ-IQD","documentType":"purchases_invoice","documentReference":"R56-PINV","debit":0,"credit":75,"currency":"IQD"}]'
   and profile::text not like '%R56-OTHER-JOURNAL%') then
   raise exception 'r56_supplier_360_incomplete:%',profile;
 end if;
end
$verify$;

rollback;
