\set ON_ERROR_STOP on
begin;

select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);
set local role postgres;

-- Exact browser topology: an original-currency partner advance plus two FX
-- cash legs, a transfer, and payment-owned journals. Both currency directions
-- use the real V7.5.7/R68 relational keys.
do $$
declare
  c constant uuid:='11111111-1111-4111-8111-111111111111';
  i integer; invoice_currency text; cash_currency text; family text;
  payment text; settlement text; transfer text; settlement_journal text;
begin
  for i,invoice_currency,cash_currency in select * from (values
    (1,'USD','IQD'),(2,'IQD','USD')) q(i,invoice_currency,cash_currency)
  loop
    family:='r69-family-'||i; payment:='r69-payment-'||i;
    settlement:='r69-partner-settlement-'||i;
    transfer:='r69-transfer-'||i; settlement_journal:='r69-partner-journal-'||i;

    insert into public.erp_cash_transactions(company_id,id,data) values
    (c,settlement,jsonb_build_object(
      'id',settlement,'type',case when i=1 then 'payment' else 'receipt' end,
      'amount',100,'currency',invoice_currency,'partyId','r69-partner-'||i,
      'partyType',case when i=1 then 'supplier' else 'customer' end,
      'category',case when i=1 then 'purchase_invoice_settlement' else 'sales_invoice_settlement' end,
      'referenceType','partner_advance','referenceId','r69-partner-'||i,
      'cashAccountId',case when invoice_currency='USD' then 'cash-main-usd' else 'cash-main-iqd' end,
      'journalEntryId',settlement_journal,'paymentId',payment,
      'paymentKey',family,'transactionFamilyId',family,
      'paymentTransferId',transfer,'unapplied',true,'paymentChainVersion','v757')),
    (c,'r69-fx-out-'||i,jsonb_build_object(
      'id','r69-fx-out-'||i,'type','payment','amount',150000,
      'currency',cash_currency,'referenceType','cash_transfer','referenceId',transfer,
      'cashAccountId',case when cash_currency='USD' then 'cash-main-usd' else 'cash-main-iqd' end,
      'journalEntryId','r69-fx-out-journal-'||i,'paymentId',payment,
      'paymentKey',family,'transactionFamilyId',family)),
    (c,'r69-fx-in-'||i,jsonb_build_object(
      'id','r69-fx-in-'||i,'type','receipt','amount',100,
      'currency',invoice_currency,'referenceType','cash_transfer','referenceId',transfer,
      'cashAccountId',case when invoice_currency='USD' then 'cash-main-usd' else 'cash-main-iqd' end,
      'journalEntryId','r69-fx-in-journal-'||i,'paymentId',payment,
      'paymentKey',family,'transactionFamilyId',family));

    insert into public.erp_cash_transfers(company_id,id,data) values(c,transfer,
      jsonb_build_object('id',transfer,'paymentId',payment,'paymentKey',family,
        'transactionFamilyId',family,'sourceCurrency',cash_currency,
        'targetCurrency',invoice_currency,'sourceAmount',150000,'targetAmount',100));

    insert into public.erp_journal_entries(company_id,id,data) values
    (c,settlement_journal,jsonb_build_object('id',settlement_journal,
      'referenceType','partner_advance','paymentId',payment,'paymentKey',family,
      'transactionFamilyId',family,'currency',invoice_currency,'totalDebit',100,'totalCredit',100)),
    (c,'r69-fx-out-journal-'||i,jsonb_build_object('id','r69-fx-out-journal-'||i,
      'referenceType','cash_transfer_source','referenceId',transfer,'paymentId',payment,
      'paymentKey',family,'transactionFamilyId',family,'currency',cash_currency,
      'totalDebit',150000,'totalCredit',150000)),
    (c,'r69-fx-in-journal-'||i,jsonb_build_object('id','r69-fx-in-journal-'||i,
      'referenceType','cash_transfer_target','referenceId',transfer,'paymentId',payment,
      'paymentKey',family,'transactionFamilyId',family,'currency',invoice_currency,
      'totalDebit',100,'totalCredit',100));

    insert into public.erp_journal_lines(company_id,id,data)
    select c,'r69-line-'||i||'-'||n,jsonb_build_object(
      'id','r69-line-'||i||'-'||n,'entryId',entry_id,'paymentId',payment,
      'paymentKey',family,'transactionFamilyId',family,'currency',currency,
      'accountId',case when currency='USD' then 'acc-1100' else 'acc-1101' end,
      'debit',case when n%2=1 then amount else 0 end,
      'credit',case when n%2=0 then amount else 0 end)
    from (values
      (1,settlement_journal,invoice_currency,100::numeric),
      (2,settlement_journal,invoice_currency,100::numeric),
      (3,'r69-fx-out-journal-'||i,cash_currency,150000::numeric),
      (4,'r69-fx-out-journal-'||i,cash_currency,150000::numeric),
      (5,'r69-fx-in-journal-'||i,invoice_currency,100::numeric),
      (6,'r69-fx-in-journal-'||i,invoice_currency,100::numeric)
    ) l(n,entry_id,currency,amount);
  end loop;

  insert into public.erp_cash_transactions(company_id,id,data) values(c,'r69-unrelated',
    '{"id":"r69-unrelated","type":"receipt","amount":7,"currency":"USD","cashAccountId":"cash-main-usd","referenceType":"manual_cash_transaction"}');
end $$;

set local role authenticated;
do $$
declare c constant uuid:='11111111-1111-4111-8111-111111111111';
begin
  -- Exact Cashbox transfer Delete path from the failed browser run.
  perform public.erp_delete_cloud_cash_transfer(c,'r69-transfer-1');
  -- Payment-origin FX Journal Delete must converge through the same primitive.
  perform public.erp_delete_cloud_accounting_entry(c,'r69-fx-out-journal-2');
end $$;

set local role postgres;
do $$
declare c constant uuid:='11111111-1111-4111-8111-111111111111'; family text;
begin
  foreach family in array array['r69-family-1','r69-family-2'] loop
    if exists(select 1 from public.erp_cash_transactions where company_id=c
        and not is_deleted and coalesce(data->>'transactionFamilyId',data->>'paymentKey')=family)
      or exists(select 1 from public.erp_cash_transfers where company_id=c
        and not is_deleted and coalesce(data->>'transactionFamilyId',data->>'paymentKey')=family)
      or exists(select 1 from public.erp_journal_entries where company_id=c
        and not is_deleted and coalesce(data->>'transactionFamilyId',data->>'paymentKey')=family)
      or exists(select 1 from public.erp_journal_lines where company_id=c
        and not is_deleted and coalesce(data->>'transactionFamilyId',data->>'paymentKey')=family)
      or exists(select 1 from public.erp_partner_advance_allocations where company_id=c
        and not is_deleted and cash_transaction_id like 'r69-partner-settlement-%') then
      raise exception 'R69 active family artifact remained: %',family;
    end if;
  end loop;
  if not exists(select 1 from public.erp_cash_transactions
      where company_id=c and id='r69-unrelated' and not is_deleted) then
    raise exception 'R69 touched an unrelated payment';
  end if;
  if exists(select 1 from public.erp_journal_entries je
      where je.company_id=c and je.id like 'r69-%journal-%' and not je.is_deleted)
    or exists(select 1 from public.erp_journal_lines jl
      where jl.company_id=c and jl.id like 'r69-line-%' and not jl.is_deleted) then
    raise exception 'R69 payment-owned journal artifact remained';
  end if;
end $$;

-- Active allocation denial happens before mutation even when Delete begins at
-- the FX transfer instead of the partner payment row.
insert into public.erp_cash_transactions(company_id,id,data) values
('11111111-1111-4111-8111-111111111111','r69-protected-settlement',
 '{"id":"r69-protected-settlement","type":"payment","amount":100,"currency":"USD","cashAccountId":"cash-main-usd","referenceType":"partner_advance","paymentId":"r69-protected-payment","paymentKey":"r69-protected-family","transactionFamilyId":"r69-protected-family","paymentTransferId":"r69-protected-transfer","unapplied":true}');
insert into public.erp_cash_transfers(company_id,id,data) values
('11111111-1111-4111-8111-111111111111','r69-protected-transfer',
 '{"id":"r69-protected-transfer","paymentId":"r69-protected-payment","paymentKey":"r69-protected-family","transactionFamilyId":"r69-protected-family"}');
insert into public.erp_partner_advance_allocations(
  company_id,cash_transaction_id,party_type,party_id,currency,target_module,
  target_order_id,amount
) values('11111111-1111-4111-8111-111111111111','r69-protected-settlement',
  'supplier','r69-supplier','USD','purchases',
  '69000000-0000-4000-8000-000000000001',100);
set local role authenticated;
do $$
begin
  begin
    perform public.erp_delete_cloud_cash_transfer(
      '11111111-1111-4111-8111-111111111111','r69-protected-transfer');
    raise exception 'R69 protected transfer delete unexpectedly succeeded';
  exception when others then
    if sqlerrm<>'payment_has_active_allocations' then raise; end if;
  end;
end $$;
set local role postgres;
do $$
begin
  if not exists(select 1 from public.erp_cash_transactions where
      id='r69-protected-settlement' and not is_deleted)
    or not exists(select 1 from public.erp_cash_transfers where
      id='r69-protected-transfer' and not is_deleted) then
    raise exception 'R69 protected family partially mutated before denial';
  end if;
end $$;

rollback;
\echo 'R69 financial-family runtime convergence rollback proof PASS'
