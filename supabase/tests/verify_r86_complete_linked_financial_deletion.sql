\set ON_ERROR_STOP on
\pset pager off

-- R86 complete linked financial deletion regression.
-- LOCAL Supabase only. All fixtures are rolled back.
begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '86000000-0000-4000-8000-000000000001',
  'authenticated','authenticated','r86-financial-delete@local.invalid','',now(),
  '{}'::jsonb,'{}'::jsonb,now(),now()
);

insert into public.companies(id,slug,name_ar,name_en,is_active) values (
  '86000000-0000-4000-8000-000000000010',
  'r86-financial-delete','R86 حذف مالي','R86 financial delete',true
);

insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values (
  '86000000-0000-4000-8000-000000000010',
  '86000000-0000-4000-8000-000000000001',
  '86000000-0000-4000-8000-000000000001',
  'r86-financial-delete@local.invalid','admin',true,true
);

-- -------------------------------------------------------------------------
-- Sales invoice: two independent payments. Deleting one must preserve the
-- invoice and the other payment.
-- -------------------------------------------------------------------------
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values (
  '86000000-0000-4000-8000-000000000101',
  '86000000-0000-4000-8000-000000000010',
  'sales','invoice','86000000-0000-4000-8000-000000000201',
  'R86-SINV-001','approved',jsonb_build_object(
    'currency','USD','totalAmount',1000,'paidAmount',500,
    'remainingAmount',500,'paymentStatus','partial',
    'payments',jsonb_build_array(
      jsonb_build_object(
        'paymentId','86000000-0000-4000-8000-000000001101',
        'cashTransactionId','r86-sales-cash-delete',
        'journalEntryId','r86-sales-journal-delete',
        'invoiceAmount',400,'paymentCurrency','USD'
      ),
      jsonb_build_object(
        'paymentId','86000000-0000-4000-8000-000000001102',
        'cashTransactionId','r86-sales-cash-keep',
        'journalEntryId','r86-sales-journal-keep',
        'invoiceAmount',100,'paymentCurrency','USD'
      )
    )
  )
);

insert into public.erp_cash_transactions(company_id,id,data) values
(
  '86000000-0000-4000-8000-000000000010','r86-sales-cash-delete',
  jsonb_build_object(
    'id','r86-sales-cash-delete','voucherNumber','R86-SC-DEL','type','receipt',
    'amount',400,'currency','USD','referenceType','sales_payment',
    'referenceId','86000000-0000-4000-8000-000000001101',
    'invoiceId','86000000-0000-4000-8000-000000000101',
    'journalEntryId','r86-sales-journal-delete'
  )
),(
  '86000000-0000-4000-8000-000000000010','r86-sales-cash-keep',
  jsonb_build_object(
    'id','r86-sales-cash-keep','voucherNumber','R86-SC-KEEP','type','receipt',
    'amount',100,'currency','USD','referenceType','sales_payment',
    'referenceId','86000000-0000-4000-8000-000000001102',
    'invoiceId','86000000-0000-4000-8000-000000000101',
    'journalEntryId','r86-sales-journal-keep'
  )
);

insert into public.erp_journal_entries(company_id,id,data) values
(
  '86000000-0000-4000-8000-000000000010','r86-sales-journal-delete',
  jsonb_build_object(
    'entryNumber','R86-SJ-DEL','referenceType','sales_payment',
    'referenceId','86000000-0000-4000-8000-000000001101',
    'status','posted','currency','USD'
  )
),(
  '86000000-0000-4000-8000-000000000010','r86-sales-journal-keep',
  jsonb_build_object(
    'entryNumber','R86-SJ-KEEP','referenceType','sales_payment',
    'referenceId','86000000-0000-4000-8000-000000001102',
    'status','posted','currency','USD'
  )
);

insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-sales-line-delete-a',jsonb_build_object('entryId','r86-sales-journal-delete','debit',400,'credit',0)),
('86000000-0000-4000-8000-000000000010','r86-sales-line-delete-b',jsonb_build_object('entryId','r86-sales-journal-delete','debit',0,'credit',400)),
('86000000-0000-4000-8000-000000000010','r86-sales-line-keep-a',jsonb_build_object('entryId','r86-sales-journal-keep','debit',100,'credit',0)),
('86000000-0000-4000-8000-000000000010','r86-sales-line-keep-b',jsonb_build_object('entryId','r86-sales-journal-keep','debit',0,'credit',100));

-- -------------------------------------------------------------------------
-- Purchase invoice direct payment.
-- -------------------------------------------------------------------------
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values (
  '86000000-0000-4000-8000-000000000102',
  '86000000-0000-4000-8000-000000000010',
  'purchases','invoice','86000000-0000-4000-8000-000000000202',
  'R86-PINV-001','approved',jsonb_build_object(
    'currency','USD','totalAmount',800,'paidAmount',300,
    'remainingAmount',500,'paymentStatus','partial',
    'payments',jsonb_build_array(jsonb_build_object(
      'paymentId','86000000-0000-4000-8000-000000001201',
      'cashTransactionId','r86-purchase-cash-delete',
      'journalEntryId','r86-purchase-journal-delete',
      'invoiceAmount',300,'paymentCurrency','USD'
    ))
  )
);
insert into public.erp_cash_transactions(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-purchase-cash-delete',
  jsonb_build_object(
    'id','r86-purchase-cash-delete','voucherNumber','R86-PC-DEL','type','payment',
    'amount',300,'currency','USD','referenceType','purchases_payment',
    'referenceId','86000000-0000-4000-8000-000000001201',
    'invoiceId','86000000-0000-4000-8000-000000000102',
    'journalEntryId','r86-purchase-journal-delete'
  )
);
insert into public.erp_journal_entries(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-purchase-journal-delete',
  jsonb_build_object(
    'entryNumber','R86-PJ-DEL','referenceType','purchases_payment',
    'referenceId','86000000-0000-4000-8000-000000001201',
    'status','posted','currency','USD'
  )
);
insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-purchase-line-a',jsonb_build_object('entryId','r86-purchase-journal-delete','debit',300,'credit',0)),
('86000000-0000-4000-8000-000000000010','r86-purchase-line-b',jsonb_build_object('entryId','r86-purchase-journal-delete','debit',0,'credit',300));

-- -------------------------------------------------------------------------
-- Maintenance: two independent payments. Delete one and recalculate from the
-- surviving amount_in_order_currency row.
-- -------------------------------------------------------------------------
insert into public.erp_maintenance_orders(
  id,company_id,order_number,car_id,car_name,is_sold_car,pricing_type,
  status,workflow_stage,sale_price,paid_amount,currency_code,exchange_rate
) values (
  '86000000-0000-4000-8000-000000000301',
  '86000000-0000-4000-8000-000000000010','R86-MO-001',
  '86000000-0000-4000-8000-000000000401','R86 Vehicle',true,'paid',
  'completed','paid',500,500,'USD',1
);

insert into public.erp_maintenance_payments(
  id,company_id,maintenance_order_id,amount,currency_code,exchange_rate,
  amount_in_order_currency,cash_transaction_id,journal_entry_id,payment_key,
  settlement_mode,payment_payload
) values
(
  '86000000-0000-4000-8000-000000001301',
  '86000000-0000-4000-8000-000000000010',
  '86000000-0000-4000-8000-000000000301',300,'USD',1,300,
  'r86-maint-cash-delete','r86-maint-journal-delete','r86-maint-key-delete','partial',
  jsonb_build_object(
    'paymentId','86000000-0000-4000-8000-000000001301',
    'cashTransactionId','r86-maint-cash-delete',
    'journalEntryId','r86-maint-journal-delete','invoiceAmount',300
  )
),(
  '86000000-0000-4000-8000-000000001302',
  '86000000-0000-4000-8000-000000000010',
  '86000000-0000-4000-8000-000000000301',200,'USD',1,200,
  'r86-maint-cash-keep','r86-maint-journal-keep','r86-maint-key-keep','partial',
  jsonb_build_object(
    'paymentId','86000000-0000-4000-8000-000000001302',
    'cashTransactionId','r86-maint-cash-keep',
    'journalEntryId','r86-maint-journal-keep','invoiceAmount',200
  )
);

insert into public.erp_cash_transactions(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-maint-cash-delete',jsonb_build_object(
  'id','r86-maint-cash-delete','voucherNumber','R86-MC-DEL','type','receipt','amount',300,'currency','USD',
  'referenceType','maintenance_payment','referenceId','86000000-0000-4000-8000-000000001301',
  'maintenanceOrderId','86000000-0000-4000-8000-000000000301','journalEntryId','r86-maint-journal-delete'
)),
('86000000-0000-4000-8000-000000000010','r86-maint-cash-keep',jsonb_build_object(
  'id','r86-maint-cash-keep','voucherNumber','R86-MC-KEEP','type','receipt','amount',200,'currency','USD',
  'referenceType','maintenance_payment','referenceId','86000000-0000-4000-8000-000000001302',
  'maintenanceOrderId','86000000-0000-4000-8000-000000000301','journalEntryId','r86-maint-journal-keep'
));
insert into public.erp_journal_entries(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-maint-journal-delete',jsonb_build_object(
  'entryNumber','R86-MJ-DEL','referenceType','maintenance_payment','referenceId','86000000-0000-4000-8000-000000001301','status','posted'
)),
('86000000-0000-4000-8000-000000000010','r86-maint-journal-keep',jsonb_build_object(
  'entryNumber','R86-MJ-KEEP','referenceType','maintenance_payment','referenceId','86000000-0000-4000-8000-000000001302','status','posted'
));
insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-maint-line-delete-a',jsonb_build_object('entryId','r86-maint-journal-delete')),
('86000000-0000-4000-8000-000000000010','r86-maint-line-delete-b',jsonb_build_object('entryId','r86-maint-journal-delete')),
('86000000-0000-4000-8000-000000000010','r86-maint-line-keep-a',jsonb_build_object('entryId','r86-maint-journal-keep'));

-- -------------------------------------------------------------------------
-- FX invoice payment: settlement cash/journal + transfer + two transfer cash
-- legs + source/target currency journals. Deleting either transfer cash leg
-- must delete the full payment operation but keep an unrelated invoice payment.
-- -------------------------------------------------------------------------
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values (
  '86000000-0000-4000-8000-000000000103',
  '86000000-0000-4000-8000-000000000010',
  'sales','invoice','86000000-0000-4000-8000-000000000203',
  'R86-SINV-FX','approved',jsonb_build_object(
    'currency','USD','totalAmount',1000,'paidAmount',500,
    'remainingAmount',500,'paymentStatus','partial',
    'payments',jsonb_build_array(
      jsonb_build_object(
        'paymentId','86000000-0000-4000-8000-000000001401',
        'cashTransactionId','r86-fx-settlement-cash',
        'journalEntryId','r86-fx-payment-journal',
        'transferId','r86-fx-transfer','invoiceAmount',400,
        'paymentCurrency','IQD','invoiceCurrency','USD'
      ),
      jsonb_build_object(
        'paymentId','86000000-0000-4000-8000-000000001402',
        'cashTransactionId','r86-fx-unrelated-cash',
        'journalEntryId','r86-fx-unrelated-journal',
        'invoiceAmount',100,'paymentCurrency','USD','invoiceCurrency','USD'
      )
    )
  )
);
insert into public.erp_cash_transfers(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-fx-transfer',
  jsonb_build_object(
    'id','r86-fx-transfer','transferNumber','R86-FX-TR','sourceAmount',400,
    'sourceCurrency','USD','targetAmount',600000,'targetCurrency','IQD',
    'exchangeRate',1500,'status','posted'
  )
);
insert into public.erp_cash_transactions(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-fx-settlement-cash',jsonb_build_object(
  'id','r86-fx-settlement-cash','voucherNumber','R86-FX-SET','type','receipt','amount',400,'currency','USD',
  'referenceType','sales_payment','referenceId','86000000-0000-4000-8000-000000001401',
  'invoiceId','86000000-0000-4000-8000-000000000103','journalEntryId','r86-fx-payment-journal'
)),
('86000000-0000-4000-8000-000000000010','r86-fx-transfer-out',jsonb_build_object(
  'id','r86-fx-transfer-out','voucherNumber','R86-FX-OUT','type','payment','amount',400,'currency','USD',
  'category','cash_transfer','referenceType','cash_transfer','referenceId','r86-fx-transfer',
  'journalEntryId','r86-fx-source-journal'
)),
('86000000-0000-4000-8000-000000000010','r86-fx-transfer-in',jsonb_build_object(
  'id','r86-fx-transfer-in','voucherNumber','R86-FX-IN','type','receipt','amount',600000,'currency','IQD',
  'category','cash_transfer','referenceType','cash_transfer','referenceId','r86-fx-transfer',
  'journalEntryId','r86-fx-target-journal'
)),
('86000000-0000-4000-8000-000000000010','r86-fx-unrelated-cash',jsonb_build_object(
  'id','r86-fx-unrelated-cash','voucherNumber','R86-FX-KEEP','type','receipt','amount',100,'currency','USD',
  'referenceType','sales_payment','referenceId','86000000-0000-4000-8000-000000001402',
  'invoiceId','86000000-0000-4000-8000-000000000103','journalEntryId','r86-fx-unrelated-journal'
));
insert into public.erp_journal_entries(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-fx-payment-journal',jsonb_build_object(
  'entryNumber','R86-FX-PJ','referenceType','sales_payment','referenceId','86000000-0000-4000-8000-000000001401','status','posted'
)),
('86000000-0000-4000-8000-000000000010','r86-fx-source-journal',jsonb_build_object(
  'entryNumber','R86-FX-SJ','referenceType','cash_transfer_source','referenceId','r86-fx-transfer','status','posted'
)),
('86000000-0000-4000-8000-000000000010','r86-fx-target-journal',jsonb_build_object(
  'entryNumber','R86-FX-TJ','referenceType','cash_transfer_target','referenceId','r86-fx-transfer','status','posted'
)),
('86000000-0000-4000-8000-000000000010','r86-fx-unrelated-journal',jsonb_build_object(
  'entryNumber','R86-FX-KEEPJ','referenceType','sales_payment','referenceId','86000000-0000-4000-8000-000000001402','status','posted'
));
insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-fx-line-payment-a',jsonb_build_object('entryId','r86-fx-payment-journal')),
('86000000-0000-4000-8000-000000000010','r86-fx-line-source-a',jsonb_build_object('entryId','r86-fx-source-journal')),
('86000000-0000-4000-8000-000000000010','r86-fx-line-target-a',jsonb_build_object('entryId','r86-fx-target-journal')),
('86000000-0000-4000-8000-000000000010','r86-fx-line-keep-a',jsonb_build_object('entryId','r86-fx-unrelated-journal'));

-- -------------------------------------------------------------------------
-- Standalone cash transfer.
-- -------------------------------------------------------------------------
insert into public.erp_cash_transfers(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-standalone-transfer',
  jsonb_build_object('id','r86-standalone-transfer','transferNumber','R86-TR-ONLY','status','posted')
);
insert into public.erp_cash_transactions(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-transfer-only-out',jsonb_build_object(
  'id','r86-transfer-only-out','voucherNumber','R86-TR-OUT','type','payment','amount',50,'currency','USD',
  'category','cash_transfer','referenceType','cash_transfer','referenceId','r86-standalone-transfer','journalEntryId','r86-transfer-only-journal'
)),
('86000000-0000-4000-8000-000000000010','r86-transfer-only-in',jsonb_build_object(
  'id','r86-transfer-only-in','voucherNumber','R86-TR-IN','type','receipt','amount',50,'currency','USD',
  'category','cash_transfer','referenceType','cash_transfer','referenceId','r86-standalone-transfer','journalEntryId','r86-transfer-only-journal'
));
insert into public.erp_journal_entries(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-transfer-only-journal',
  jsonb_build_object('entryNumber','R86-TR-J','referenceType','cash_transfer','referenceId','r86-standalone-transfer','status','posted')
);
insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-transfer-only-line-a',jsonb_build_object('entryId','r86-transfer-only-journal')),
('86000000-0000-4000-8000-000000000010','r86-transfer-only-line-b',jsonb_build_object('entryId','r86-transfer-only-journal'));

-- -------------------------------------------------------------------------
-- Journal-entry deletion of a payment. This is the regression for the old path
-- that could route to the owning commercial document instead of the payment.
-- -------------------------------------------------------------------------
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values (
  '86000000-0000-4000-8000-000000000104',
  '86000000-0000-4000-8000-000000000010',
  'purchases','invoice','86000000-0000-4000-8000-000000000204',
  'R86-PINV-JOURNAL','approved',jsonb_build_object(
    'currency','USD','totalAmount',600,'paidAmount',600,
    'remainingAmount',0,'paymentStatus','paid',
    'payments',jsonb_build_array(jsonb_build_object(
      'paymentId','86000000-0000-4000-8000-000000001501',
      'cashTransactionId','r86-journal-route-cash',
      'journalEntryId','r86-journal-route-entry','invoiceAmount',600
    ))
  )
);
insert into public.erp_cash_transactions(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-journal-route-cash',
  jsonb_build_object(
    'id','r86-journal-route-cash','voucherNumber','R86-JR-C','type','payment','amount',600,'currency','USD',
    'referenceType','purchases_payment','referenceId','86000000-0000-4000-8000-000000001501',
    'invoiceId','86000000-0000-4000-8000-000000000104','journalEntryId','r86-journal-route-entry'
  )
);
insert into public.erp_journal_entries(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-journal-route-entry',
  jsonb_build_object(
    'entryNumber','R86-JR-J','referenceType','purchases_payment',
    'referenceId','86000000-0000-4000-8000-000000001501','status','posted'
  )
);
insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-journal-route-line-a',jsonb_build_object('entryId','r86-journal-route-entry')),
('86000000-0000-4000-8000-000000000010','r86-journal-route-line-b',jsonb_build_object('entryId','r86-journal-route-entry'));

-- -------------------------------------------------------------------------
-- Partner advance application: deleting the source financial operation must
-- delete only its allocation/application and leave the invoice document.
-- -------------------------------------------------------------------------
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values (
  '86000000-0000-4000-8000-000000000105',
  '86000000-0000-4000-8000-000000000010',
  'sales','invoice','86000000-0000-4000-8000-000000000205',
  'R86-SINV-ADV','approved',jsonb_build_object(
    'currency','USD','totalAmount',200,'paidAmount',200,
    'remainingAmount',0,'paymentStatus','paid',
    'payments',jsonb_build_array(jsonb_build_object(
      'paymentId','ADV-86000000-0000-4000-8000-000000001601',
      'advanceAllocationId','86000000-0000-4000-8000-000000001601',
      'cashTransactionId','r86-advance-cash',
      'journalEntryId','r86-advance-journal','invoiceAmount',200,
      'isNonCashApplication',true
    ))
  )
);
insert into public.erp_cash_transactions(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-advance-cash',
  jsonb_build_object(
    'id','r86-advance-cash','voucherNumber','R86-ADV-C','type','receipt','amount',200,'currency','USD',
    'referenceType','partner_advance','referenceId','r86-advance-root','journalEntryId','r86-advance-journal',
    'advanceAmount',200,'allocatedAmount',200,'unappliedAmount',0
  )
);
insert into public.erp_journal_entries(company_id,id,data) values (
  '86000000-0000-4000-8000-000000000010','r86-advance-journal',
  jsonb_build_object('entryNumber','R86-ADV-J','referenceType','partner_advance','referenceId','r86-advance-root','status','posted')
);
insert into public.erp_journal_lines(company_id,id,data) values
('86000000-0000-4000-8000-000000000010','r86-advance-line-a',jsonb_build_object('entryId','r86-advance-journal'));
insert into public.erp_partner_advance_allocations(
  id,company_id,cash_transaction_id,journal_entry_id,party_type,party_id,
  currency,target_module,target_order_id,target_invoice_id,amount
) values (
  '86000000-0000-4000-8000-000000001601',
  '86000000-0000-4000-8000-000000000010','r86-advance-cash','r86-advance-journal',
  'customer','r86-customer','USD','sales',
  '86000000-0000-4000-8000-000000000205',
  '86000000-0000-4000-8000-000000000105',200
);

set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"86000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

-- 1) Sales invoice payment deletion.
select public.erp_delete_cloud_cash_transaction(
  '86000000-0000-4000-8000-000000000010',
  'r86-sales-cash-delete'
);

do $r86_sales$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d from public.erp_commercial_workflow_documents
  where id='86000000-0000-4000-8000-000000000101';
  if d.id is null or d.is_deleted then
    raise exception 'r86_sales_invoice_business_document_deleted';
  end if;
  if public.erp_try_numeric(d.payload->>'paidAmount',-1)<>100
     or public.erp_try_numeric(d.payload->>'remainingAmount',-1)<>900
     or d.payload->>'paymentStatus'<>'partial' then
    raise exception 'r86_sales_invoice_reconciliation_failed:%',d.payload;
  end if;
  if jsonb_array_length(d.payload->'payments')<>1
     or d.payload->'payments'->0->>'paymentId'<>'86000000-0000-4000-8000-000000001102' then
    raise exception 'r86_sales_unrelated_payment_not_preserved:%',d.payload->'payments';
  end if;
  if not (select is_deleted from public.erp_cash_transactions where id='r86-sales-cash-delete')
     or not (select is_deleted from public.erp_journal_entries where id='r86-sales-journal-delete')
     or exists(select 1 from public.erp_journal_lines where not is_deleted and data->>'entryId'='r86-sales-journal-delete') then
    raise exception 'r86_sales_payment_group_orphaned';
  end if;
  if (select is_deleted from public.erp_cash_transactions where id='r86-sales-cash-keep')
     or (select is_deleted from public.erp_journal_entries where id='r86-sales-journal-keep') then
    raise exception 'r86_sales_independent_payment_deleted';
  end if;
end
$r86_sales$;

-- 2) Purchase invoice payment deletion.
select public.erp_delete_cloud_cash_transaction(
  '86000000-0000-4000-8000-000000000010',
  'r86-purchase-cash-delete'
);

do $r86_purchase$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d from public.erp_commercial_workflow_documents
  where id='86000000-0000-4000-8000-000000000102';
  if d.id is null or d.is_deleted then
    raise exception 'r86_purchase_invoice_business_document_deleted';
  end if;
  if public.erp_try_numeric(d.payload->>'paidAmount',-1)<>0
     or public.erp_try_numeric(d.payload->>'remainingAmount',-1)<>800
     or d.payload->>'paymentStatus'<>'unpaid'
     or jsonb_array_length(d.payload->'payments')<>0 then
    raise exception 'r86_purchase_invoice_reconciliation_failed:%',d.payload;
  end if;
  if not (select is_deleted from public.erp_cash_transactions where id='r86-purchase-cash-delete')
     or not (select is_deleted from public.erp_journal_entries where id='r86-purchase-journal-delete')
     or exists(select 1 from public.erp_journal_lines where not is_deleted and data->>'entryId'='r86-purchase-journal-delete') then
    raise exception 'r86_purchase_payment_group_orphaned';
  end if;
end
$r86_purchase$;

-- 3) Maintenance payment deletion.
select public.erp_delete_cloud_cash_transaction(
  '86000000-0000-4000-8000-000000000010',
  'r86-maint-cash-delete'
);

do $r86_maintenance$
declare o public.erp_maintenance_orders%rowtype;
begin
  select * into o from public.erp_maintenance_orders
  where id='86000000-0000-4000-8000-000000000301';
  if o.id is null or o.is_deleted then
    raise exception 'r86_maintenance_business_document_deleted';
  end if;
  if o.paid_amount<>200 or o.workflow_stage<>'invoice_approved' or o.status<>'approved' then
    raise exception 'r86_maintenance_reconciliation_failed:paid=% stage=% status=%',o.paid_amount,o.workflow_stage,o.status;
  end if;
  if not (select is_deleted from public.erp_maintenance_payments where id='86000000-0000-4000-8000-000000001301')
     or (select is_deleted from public.erp_maintenance_payments where id='86000000-0000-4000-8000-000000001302') then
    raise exception 'r86_maintenance_payment_scope_failed';
  end if;
  if not (select is_deleted from public.erp_cash_transactions where id='r86-maint-cash-delete')
     or not (select is_deleted from public.erp_journal_entries where id='r86-maint-journal-delete')
     or (select is_deleted from public.erp_cash_transactions where id='r86-maint-cash-keep') then
    raise exception 'r86_maintenance_financial_group_scope_failed';
  end if;
end
$r86_maintenance$;

-- 4) FX operation deletion from one cash-transfer leg.
select public.erp_delete_cloud_cash_transaction(
  '86000000-0000-4000-8000-000000000010',
  'r86-fx-transfer-out'
);

do $r86_fx$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d from public.erp_commercial_workflow_documents
  where id='86000000-0000-4000-8000-000000000103';
  if d.id is null or d.is_deleted then
    raise exception 'r86_fx_invoice_business_document_deleted';
  end if;
  if public.erp_try_numeric(d.payload->>'paidAmount',-1)<>100
     or public.erp_try_numeric(d.payload->>'remainingAmount',-1)<>900
     or d.payload->>'paymentStatus'<>'partial'
     or jsonb_array_length(d.payload->'payments')<>1
     or d.payload->'payments'->0->>'paymentId'<>'86000000-0000-4000-8000-000000001402' then
    raise exception 'r86_fx_invoice_reconciliation_failed:%',d.payload;
  end if;
  if not (select is_deleted from public.erp_cash_transfers where id='r86-fx-transfer')
     or exists(
       select 1 from public.erp_cash_transactions
       where id in ('r86-fx-settlement-cash','r86-fx-transfer-out','r86-fx-transfer-in')
         and not is_deleted
     )
     or exists(
       select 1 from public.erp_journal_entries
       where id in ('r86-fx-payment-journal','r86-fx-source-journal','r86-fx-target-journal')
         and not is_deleted
     )
     or exists(
       select 1 from public.erp_journal_lines
       where not is_deleted and data->>'entryId' in (
         'r86-fx-payment-journal','r86-fx-source-journal','r86-fx-target-journal'
       )
     ) then
    raise exception 'r86_fx_financial_group_orphaned';
  end if;
  if (select is_deleted from public.erp_cash_transactions where id='r86-fx-unrelated-cash')
     or (select is_deleted from public.erp_journal_entries where id='r86-fx-unrelated-journal') then
    raise exception 'r86_fx_unrelated_payment_deleted';
  end if;
end
$r86_fx$;

-- 5) Standalone cash transfer deletion.
select public.erp_delete_cloud_cash_transfer(
  '86000000-0000-4000-8000-000000000010',
  'r86-standalone-transfer'
);

do $r86_transfer$
begin
  if not (select is_deleted from public.erp_cash_transfers where id='r86-standalone-transfer')
     or exists(
       select 1 from public.erp_cash_transactions
       where id in ('r86-transfer-only-out','r86-transfer-only-in') and not is_deleted
     )
     or not (select is_deleted from public.erp_journal_entries where id='r86-transfer-only-journal')
     or exists(
       select 1 from public.erp_journal_lines
       where not is_deleted and data->>'entryId'='r86-transfer-only-journal'
     ) then
    raise exception 'r86_standalone_cash_transfer_group_orphaned';
  end if;
end
$r86_transfer$;

-- 6) Delete through journal entry: payment goes away, invoice stays.
select public.erp_delete_cloud_accounting_entry(
  '86000000-0000-4000-8000-000000000010',
  'r86-journal-route-entry'
);

do $r86_journal$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d from public.erp_commercial_workflow_documents
  where id='86000000-0000-4000-8000-000000000104';
  if d.id is null or d.is_deleted then
    raise exception 'r86_journal_delete_removed_invoice_document';
  end if;
  if public.erp_try_numeric(d.payload->>'paidAmount',-1)<>0
     or public.erp_try_numeric(d.payload->>'remainingAmount',-1)<>600
     or d.payload->>'paymentStatus'<>'unpaid'
     or jsonb_array_length(d.payload->'payments')<>0 then
    raise exception 'r86_journal_delete_invoice_reconciliation_failed:%',d.payload;
  end if;
  if not (select is_deleted from public.erp_cash_transactions where id='r86-journal-route-cash')
     or not (select is_deleted from public.erp_journal_entries where id='r86-journal-route-entry')
     or exists(select 1 from public.erp_journal_lines where not is_deleted and data->>'entryId'='r86-journal-route-entry') then
    raise exception 'r86_journal_delete_left_payment_orphan';
  end if;
end
$r86_journal$;

-- Extra closure: partner advance allocation/application from the same source.
select public.erp_delete_cloud_cash_transaction(
  '86000000-0000-4000-8000-000000000010',
  'r86-advance-cash'
);

do $r86_advance$
declare d public.erp_commercial_workflow_documents%rowtype;
begin
  select * into d from public.erp_commercial_workflow_documents
  where id='86000000-0000-4000-8000-000000000105';
  if d.id is null or d.is_deleted then
    raise exception 'r86_advance_delete_removed_invoice_document';
  end if;
  if public.erp_try_numeric(d.payload->>'paidAmount',-1)<>0
     or public.erp_try_numeric(d.payload->>'remainingAmount',-1)<>200
     or jsonb_array_length(d.payload->'payments')<>0 then
    raise exception 'r86_advance_invoice_reconciliation_failed:%',d.payload;
  end if;
  if not (select is_deleted from public.erp_partner_advance_allocations where id='86000000-0000-4000-8000-000000001601')
     or not (select is_deleted from public.erp_cash_transactions where id='r86-advance-cash')
     or not (select is_deleted from public.erp_journal_entries where id='r86-advance-journal') then
    raise exception 'r86_advance_allocation_or_financial_group_orphaned';
  end if;
end
$r86_advance$;

select 'R86 complete linked financial deletion PASS' as result;
rollback;
