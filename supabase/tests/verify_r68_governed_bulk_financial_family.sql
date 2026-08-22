\set ON_ERROR_STOP on
begin;

select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);

-- Isolated fixtures are inserted as postgres; destructive RPCs execute as the
-- real local authenticated QA user and are rolled back at the end.
set local role postgres;

do $$
declare
  c constant uuid:='11111111-1111-4111-8111-111111111111';
  f text;
  cur text;
  inv text;
  tx text;
  j text;
  transfer text;
  i integer;
begin
  for i,cur,inv in
    select * from (values
      (1,'USD','USD'),(2,'IQD','IQD'),(3,'IQD','USD'),(4,'USD','IQD')
    ) q(i,cur,inv)
  loop
    f:='r68-family-'||i; tx:='r68-settlement-'||i; j:='r68-journal-'||i;
    insert into public.erp_cash_transactions(company_id,id,data)
    values(c,tx,jsonb_build_object(
      'id',tx,'type','receipt','amount',100,'currency',inv,
      'cashAccountId',case when inv='USD' then 'cash-main-usd' else 'cash-main-iqd' end,
      'invoiceCurrency',inv,'paymentCurrency',cur,
      'referenceType','partner_advance','paymentKey',f,
      'transactionFamilyId',f,'journalEntryId',j,'unapplied',true
    ));
    insert into public.erp_journal_entries(company_id,id,data)
    values(c,j,jsonb_build_object(
      'id',j,'referenceType','partner_advance','paymentKey',f,
      'transactionFamilyId',f,'currency',inv,'totalDebit',100,'totalCredit',100
    ));
    insert into public.erp_journal_lines(company_id,id,data) values
    (c,'r68-line-d-'||i,jsonb_build_object('entryId',j,'transactionFamilyId',f,
      'accountId',case when inv='USD' then 'acc-1100' else 'acc-1101' end,
      'currency',inv,'debit',100,'credit',0)),
    (c,'r68-line-c-'||i,jsonb_build_object('entryId',j,'transactionFamilyId',f,
      'accountId',case when inv='USD' then 'acc-1100' else 'acc-1101' end,
      'currency',inv,'debit',0,'credit',100));
    if cur<>inv then
      transfer:='r68-transfer-'||i;
      insert into public.erp_cash_transfers(company_id,id,data)
      values(c,transfer,jsonb_build_object(
        'id',transfer,'transactionFamilyId',f,'paymentKey',f,
        'sourceCurrency',cur,'targetCurrency',inv
      ));
      insert into public.erp_cash_transactions(company_id,id,data) values
      (c,'r68-fx-out-'||i,jsonb_build_object(
        'id','r68-fx-out-'||i,'type','payment','amount',150000,
        'currency',cur,'cashAccountId',case when cur='USD' then 'cash-main-usd' else 'cash-main-iqd' end,
        'referenceType','cash_transfer','referenceId',transfer,
        'transactionFamilyId',f,'paymentKey',f,
        'journalEntryId','r68-fx-source-j-'||i)),
      (c,'r68-fx-in-'||i,jsonb_build_object(
        'id','r68-fx-in-'||i,'type','receipt','amount',100,
        'currency',inv,'cashAccountId',case when inv='USD' then 'cash-main-usd' else 'cash-main-iqd' end,
        'referenceType','cash_transfer','referenceId',transfer,
        'transactionFamilyId',f,'paymentKey',f,
        'journalEntryId','r68-fx-target-j-'||i));
      insert into public.erp_journal_entries(company_id,id,data) values
      (c,'r68-fx-source-j-'||i,jsonb_build_object(
        'id','r68-fx-source-j-'||i,'referenceType','cash_transfer_source',
        'referenceId',transfer,'transactionFamilyId',f,'paymentKey',f,
        'currency',cur,'totalDebit',150000,'totalCredit',150000)),
      (c,'r68-fx-target-j-'||i,jsonb_build_object(
        'id','r68-fx-target-j-'||i,'referenceType','cash_transfer_target',
        'referenceId',transfer,'transactionFamilyId',f,'paymentKey',f,
        'currency',inv,'totalDebit',100,'totalCredit',100));
      insert into public.erp_journal_lines(company_id,id,data) values
      (c,'r68-fx-sd-'||i,jsonb_build_object('entryId','r68-fx-source-j-'||i,
        'transactionFamilyId',f,
        'accountId',case when cur='USD' then 'acc-1100' else 'acc-1101' end,
        'currency',cur,'debit',150000,'credit',0)),
      (c,'r68-fx-sc-'||i,jsonb_build_object('entryId','r68-fx-source-j-'||i,
        'transactionFamilyId',f,
        'accountId',case when cur='USD' then 'acc-1100' else 'acc-1101' end,
        'currency',cur,'debit',0,'credit',150000)),
      (c,'r68-fx-td-'||i,jsonb_build_object('entryId','r68-fx-target-j-'||i,
        'transactionFamilyId',f,
        'accountId',case when inv='USD' then 'acc-1100' else 'acc-1101' end,
        'currency',inv,'debit',100,'credit',0)),
      (c,'r68-fx-tc-'||i,jsonb_build_object('entryId','r68-fx-target-j-'||i,
        'transactionFamilyId',f,
        'accountId',case when inv='USD' then 'acc-1100' else 'acc-1101' end,
        'currency',inv,'debit',0,'credit',100));
    end if;
  end loop;
end $$;

set local role authenticated;
do $$
declare c constant uuid:='11111111-1111-4111-8111-111111111111'; r jsonb;
begin
  perform public.erp_delete_cloud_cash_transaction(c,'r68-settlement-1');
  perform public.erp_delete_cloud_accounting_entry(c,'r68-journal-2');
  perform public.erp_delete_cloud_cash_transaction(c,'r68-settlement-3');
  perform public.erp_delete_cloud_accounting_entry(c,'r68-journal-4');
  for r in select jsonb_build_object('family',f) from unnest(array[
    'r68-family-1','r68-family-2','r68-family-3','r68-family-4']) f
  loop
    if exists(select 1 from public.erp_cash_transactions
      where company_id=c and not is_deleted
        and data->>'transactionFamilyId'=r->>'family')
      or exists(select 1 from public.erp_cash_transfers
      where company_id=c and not is_deleted
        and data->>'transactionFamilyId'=r->>'family')
      or exists(select 1 from public.erp_journal_entries
      where company_id=c and not is_deleted
        and data->>'transactionFamilyId'=r->>'family')
      or exists(select 1 from public.erp_journal_lines
      where company_id=c and not is_deleted
        and data->>'transactionFamilyId'=r->>'family') then
      raise exception 'R68 active family artifact remained: %',r->>'family';
    end if;
  end loop;
  r:=public.erp_r68_delete_financial_transaction_family(
    c,'r68-settlement-3',null
  );
  if not coalesce((r->>'alreadyDeleted')::boolean,false) then
    raise exception 'R68 family retry was not idempotent: %',r;
  end if;
end $$;

-- Sales and Purchase allocations deny before any family row is changed.
set local role postgres;
insert into public.erp_cash_transactions(company_id,id,data) values
('11111111-1111-4111-8111-111111111111','r68-sales-protected',
 '{"type":"receipt","amount":100,"currency":"USD","cashAccountId":"cash-main-usd","paymentKey":"r68-sales-protected","transactionFamilyId":"r68-sales-protected","unapplied":true}'),
('11111111-1111-4111-8111-111111111111','r68-purchase-protected',
 '{"type":"payment","amount":100,"currency":"USD","cashAccountId":"cash-main-usd","paymentKey":"r68-purchase-protected","transactionFamilyId":"r68-purchase-protected","unapplied":true}');
insert into public.erp_partner_advance_allocations(
  company_id,cash_transaction_id,party_type,party_id,currency,target_module,
  target_order_id,amount
) values
('11111111-1111-4111-8111-111111111111','r68-sales-protected','customer','qa','USD','sales',
 '68000000-0000-4000-8000-000000000001',100),
('11111111-1111-4111-8111-111111111111','r68-purchase-protected','supplier','qa','USD','purchases',
 '68000000-0000-4000-8000-000000000002',100);
set local role authenticated;
do $$
declare c constant uuid:='11111111-1111-4111-8111-111111111111'; x text;
begin
  foreach x in array array['r68-sales-protected','r68-purchase-protected'] loop
    begin
      perform public.erp_r68_delete_financial_transaction_family(c,x,null);
      raise exception 'R68 protected allocation delete unexpectedly succeeded: %',x;
    exception when others then
      if sqlerrm<>'payment_has_active_allocations' then raise; end if;
    end;
  end loop;
end $$;
set local role postgres;
do $$
begin
  if (select count(*) from public.erp_cash_transactions
    where company_id='11111111-1111-4111-8111-111111111111'
      and id in ('r68-sales-protected','r68-purchase-protected')
      and not is_deleted)<>2 then
    raise exception 'R68 protected allocation family mutated before denial';
  end if;
end $$;

-- Active invoice JSON ownership independently denies even without allocation.
insert into public.erp_cash_transactions(company_id,id,data)
values('11111111-1111-4111-8111-111111111111','r68-invoice-protected',
 '{"type":"receipt","amount":100,"currency":"USD","cashAccountId":"cash-main-usd","paymentKey":"r68-invoice-protected","transactionFamilyId":"r68-invoice-protected"}');
insert into public.erp_commercial_workflow_documents(
  id,company_id,module,document_type,parent_id,document_number,status,payload
) values(
 '68000000-0000-4000-8000-000000000010',
 '11111111-1111-4111-8111-111111111111','sales','invoice',
 '68000000-0000-4000-8000-000000000011','R68-QA-SI','approved',
 '{"payments":[{"paymentKey":"r68-invoice-protected","cashTransactionId":"r68-invoice-protected"}]}'
);
set local role authenticated;
do $$
begin
  begin
    perform public.erp_r68_delete_financial_transaction_family(
      '11111111-1111-4111-8111-111111111111','r68-invoice-protected',null
    );
    raise exception 'R68 active invoice payment delete unexpectedly succeeded';
  exception when others then
    if sqlerrm<>'payment_linked_to_active_invoice' then raise; end if;
  end;
end $$;

-- Notification bulk clear creates only recipient tombstones and is retry-safe.
set local role postgres;
insert into public.erp_enterprise_notifications(company_id,id,data) values
('11111111-1111-4111-8111-111111111111','68000000-0000-4000-8000-000000000021',
 '{"titleEn":"R68 own one","titleAr":"R68","type":"warning"}'),
('11111111-1111-4111-8111-111111111111','68000000-0000-4000-8000-000000000022',
 '{"titleEn":"R68 own two","titleAr":"R68","type":"critical"}');
insert into public.erp_notification_user_states(
  company_id,notification_id,user_key,is_read
) values(
 '11111111-1111-4111-8111-111111111111',
 '68000000-0000-4000-8000-000000000021','another-user',false
);
set local role authenticated;
do $$
declare
  c constant uuid:='11111111-1111-4111-8111-111111111111';
  k text:=public.erp_r49_notification_user_key(); r jsonb;
begin
  r:=public.erp_r68_clear_cloud_notifications(c);
  if (r->>'clearedCount')::integer<2 then
    raise exception 'R68 notification clear count invalid: %',r;
  end if;
  if public.erp_r49_cloud_unread_notification_count(c)<>0 then
    raise exception 'R68 unread notification count did not reconcile';
  end if;
  if exists(select 1 from public.erp_r49_list_cloud_notifications(c,false,500,0)) then
    raise exception 'R68 own notification inbox was not cleared';
  end if;
  r:=public.erp_r68_clear_cloud_notifications(c);
  if (r->>'clearedCount')::integer<>0 then
    raise exception 'R68 notification retry was not idempotent: %',r;
  end if;
end $$;
set local role postgres;
do $$
begin
  if not exists(select 1 from public.erp_notification_user_states
    where company_id='11111111-1111-4111-8111-111111111111'
      and notification_id='68000000-0000-4000-8000-000000000021'
      and user_key='another-user' and not deleted) then
    raise exception 'R68 changed another recipient inbox';
  end if;
  if (select count(*) from public.erp_enterprise_notifications
    where company_id='11111111-1111-4111-8111-111111111111' and id in (
      '68000000-0000-4000-8000-000000000021',
      '68000000-0000-4000-8000-000000000022'))<>2 then
    raise exception 'R68 deleted shared notification events';
  end if;
end $$;

-- Bulk recycle processes only exact current-company rows; legacy NULL-company
-- archives remain outside this governed scope.
insert into public.erp_universal_recycle_bin(
  id,company_id,source_table,record_id,payload,deletion_mode
) values
('68000000-0000-4000-8000-000000000031',
 '11111111-1111-4111-8111-111111111111','r68_missing_table','eligible','{}','soft'),
('68000000-0000-4000-8000-000000000032',
 null,'r68_missing_table','legacy-other-scope','{}','soft');
set local role authenticated;
do $$
declare r jsonb;
begin
  r:=public.erp_r68_empty_recycle_bin(
    '11111111-1111-4111-8111-111111111111'
  );
  if (r->>'archiveRowsRemoved')::integer<1 then
    raise exception 'R68 bulk recycle did not process eligible current-company row: %',r;
  end if;
  if exists(select 1 from public.erp_universal_recycle_bin
    where id='68000000-0000-4000-8000-000000000031') then
    raise exception 'R68 eligible recycle row remained';
  end if;
  if not exists(select 1 from public.erp_universal_recycle_bin
    where id='68000000-0000-4000-8000-000000000032') then
    raise exception 'R68 bulk recycle crossed company scope';
  end if;
end $$;

rollback;
\echo 'R68 governed bulk and financial-family rollback proof PASS'
