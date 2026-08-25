-- Quality Line ERP 18.9.26 / V7.5.6
-- Safe end-to-end multi-currency payment chain for sales, purchases and maintenance.
begin;

create or replace function public.erp_execute_secure_linked_payment_v1(
  p_company_id uuid,
  p_module text,
  p_invoice_id uuid,
  p_order_id uuid,
  p_partner_id text,
  p_invoice_currency text,
  p_payment jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_payment_id text:=gen_random_uuid()::text;
  v_cash_id text:=nullif(btrim(p_payment->>'cashAccountId'),'');
  v_linked_id text:=nullif(btrim(p_payment->>'linkedCashAccountId'),'');
  v_payment_currency text:=upper(coalesce(p_payment->>'paymentCurrency',''));
  v_invoice_currency text:=upper(coalesce(p_invoice_currency,''));
  v_invoice_amount numeric:=public.erp_try_numeric(p_payment->>'invoiceAmount',0);
  v_cash_amount numeric:=public.erp_try_numeric(p_payment->>'cashAmount',0);
  v_rate numeric:=public.erp_try_numeric(p_payment->>'exchangeRate',0);
  v_date timestamptz:=public.erp_try_timestamptz(p_payment->>'paymentDate',now());
  v_notes text:=nullif(btrim(p_payment->>'notes'),'');
  v_cash_currency text; v_linked_currency text;
  v_cash_ledger text; v_linked_ledger text; v_partner_account text;
  v_partner_type text;
  v_expected numeric; v_effective_rate numeric; v_tolerance numeric;
  v_settlement_tx text:=gen_random_uuid()::text;
  v_settlement_voucher text; v_journal_id text; v_transfer jsonb;
  v_lines jsonb; v_direction text;
begin
  if p_module not in ('sales','purchases','maintenance') then raise exception 'invalid_payment_module'; end if;
  perform public.erp_require_any_cloud_permission(
    p_company_id,case when p_module='purchases' then array['cashbox.payment'] else array['cashbox.receipt'] end);
  if v_cash_id is null or v_payment_currency not in ('IQD','USD')
     or v_invoice_currency not in ('IQD','USD') or v_invoice_amount<=0
     or v_cash_amount<=0 or v_rate<=0 then
    raise exception 'invalid_secure_payment';
  end if;

  select upper(coalesce(data->>'currency','')),
         nullif(coalesce(data->>'account_id',data->>'accountId'),'')
    into v_cash_currency,v_cash_ledger
  from public.erp_cash_accounts
  where company_id=p_company_id and id=v_cash_id and not is_deleted
    and public.erp_try_boolean(coalesce(data->>'isActive',data->>'is_active'),true)
  for share;
  if not found or v_cash_currency<>v_payment_currency or v_cash_ledger is null then
    raise exception 'payment_cashbox_currency_mismatch';
  end if;

  v_partner_type:=case when p_module='purchases' then 'supplier' else 'customer' end;
  v_partner_account:=public.erp_workflow_partner_account(
    p_company_id,v_partner_type,p_partner_id,v_invoice_currency);

  v_expected:=round(public.erp_v736_convert_currency(
    v_invoice_amount,v_invoice_currency,v_payment_currency,v_rate),
    case when v_payment_currency='IQD' then 0 else 2 end);
  v_tolerance:=greatest(0.01,abs(v_expected)*0.0001);
  if abs(v_cash_amount-v_expected)>v_tolerance then
    raise exception 'cash_amount_exchange_rate_mismatch:expected=%:actual=%',v_expected,v_cash_amount;
  end if;

  if v_payment_currency=v_invoice_currency then
    if abs(v_rate-1)>0.000001 or abs(v_cash_amount-v_invoice_amount)>v_tolerance then
      raise exception 'same_currency_payment_requires_rate_one';
    end if;
    v_linked_id:=v_cash_id;
    v_linked_ledger:=v_cash_ledger;
  else
    if v_linked_id is null then
      v_linked_id:=public.erp_resolve_linked_cash_account(p_company_id,v_cash_id,v_invoice_currency);
    end if;
    if v_linked_id is null or v_linked_id=v_cash_id then
      raise exception 'linked_invoice_currency_cashbox_required';
    end if;
    select upper(coalesce(data->>'currency','')),
           nullif(coalesce(data->>'account_id',data->>'accountId'),'')
      into v_linked_currency,v_linked_ledger
    from public.erp_cash_accounts
    where company_id=p_company_id and id=v_linked_id and not is_deleted
      and public.erp_try_boolean(coalesce(data->>'isActive',data->>'is_active'),true)
    for share;
    if not found or v_linked_currency<>v_invoice_currency or v_linked_ledger is null then
      raise exception 'linked_cashbox_must_use_invoice_currency';
    end if;
    if public.erp_resolve_linked_cash_account(p_company_id,v_cash_id,v_invoice_currency)
       is distinct from v_linked_id then
      raise exception 'cashboxes_not_linked_for_fx';
    end if;
  end if;

  v_settlement_voucher:=public.erp_next_document_number(
    p_company_id,
    case when p_module='purchases' then 'supplier_payment' when p_module='maintenance' then 'maintenance_payment' else 'customer_payment' end,
    case when p_module='purchases' then 'PY' when p_module='maintenance' then 'MP' else 'RC' end,
    v_date);

  if v_payment_currency=v_invoice_currency then
    v_direction:=case when p_module='purchases' then 'payment' else 'receipt' end;
    v_lines:=case when p_module='purchases' then jsonb_build_array(
      jsonb_build_object('accountId',v_partner_account,'currency',v_invoice_currency,'debit',v_invoice_amount,'credit',0,'description','Invoice payment'),
      jsonb_build_object('accountId',v_cash_ledger,'currency',v_invoice_currency,'debit',0,'credit',v_invoice_amount,'description','Cashbox payment')
    ) else jsonb_build_array(
      jsonb_build_object('accountId',v_cash_ledger,'currency',v_invoice_currency,'debit',v_invoice_amount,'credit',0,'description','Cashbox receipt'),
      jsonb_build_object('accountId',v_partner_account,'currency',v_invoice_currency,'debit',0,'credit',v_invoice_amount,'description','Invoice settlement')
    ) end;
    v_journal_id:=public.erp_phase2_insert_journal_at(
      p_company_id,p_module||'_payment',v_payment_id,
      public.erp_next_document_number(p_company_id,p_module||'_payment_journal','JE',v_date),
      'Invoice payment '||p_invoice_id::text,v_invoice_currency,v_lines,v_date);
    insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_settlement_tx,jsonb_build_object(
      'id',v_settlement_tx,'voucherNumber',v_settlement_voucher,'type',v_direction,
      'category',p_module||'_invoice_payment','amount',v_invoice_amount,
      'currency',v_invoice_currency,'transactionDate',v_date,'cashAccountId',v_cash_id,
      'counterAccountId',v_partner_account,'referenceType',p_module||'_payment',
      'referenceId',v_payment_id,'invoiceId',p_invoice_id::text,'orderId',p_order_id::text,
      'journalEntryId',v_journal_id,'paymentChainVersion','v756','notes',v_notes),auth.uid(),auth.uid());
  elsif p_module in ('sales','maintenance') then
    -- Receive invoice currency into the linked cashbox, then convert it into
    -- the cashbox/currency physically selected by the user.
    v_lines:=jsonb_build_array(
      jsonb_build_object('accountId',v_linked_ledger,'currency',v_invoice_currency,'debit',v_invoice_amount,'credit',0,'description','Invoice-currency receipt'),
      jsonb_build_object('accountId',v_partner_account,'currency',v_invoice_currency,'debit',0,'credit',v_invoice_amount,'description','Customer invoice settlement')
    );
    v_journal_id:=public.erp_phase2_insert_journal_at(
      p_company_id,p_module||'_payment',v_payment_id,
      public.erp_next_document_number(p_company_id,p_module||'_payment_journal','JE',v_date),
      'FX invoice receipt '||p_invoice_id::text,v_invoice_currency,v_lines,v_date);
    insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_settlement_tx,jsonb_build_object(
      'id',v_settlement_tx,'voucherNumber',v_settlement_voucher,'type','receipt',
      'category',p_module||'_invoice_settlement','amount',v_invoice_amount,
      'currency',v_invoice_currency,'transactionDate',v_date,'cashAccountId',v_linked_id,
      'counterAccountId',v_partner_account,'referenceType',p_module||'_payment',
      'referenceId',v_payment_id,'invoiceId',p_invoice_id::text,'orderId',p_order_id::text,
      'journalEntryId',v_journal_id,'paymentChainVersion','v756','notes',v_notes),auth.uid(),auth.uid());
    v_effective_rate:=v_cash_amount/v_invoice_amount;
    v_transfer:=public.erp_transfer_cloud_cash_v5(
      p_company_id,v_linked_id,v_cash_id,v_invoice_amount,v_cash_amount,
      v_effective_rate,v_date,coalesce(v_notes,'FX invoice receipt conversion'));
  else
    -- Purchase: convert the selected payment currency first, then settle the
    -- supplier from the linked cashbox in the invoice currency.
    v_effective_rate:=v_invoice_amount/v_cash_amount;
    v_transfer:=public.erp_transfer_cloud_cash_v5(
      p_company_id,v_cash_id,v_linked_id,v_cash_amount,v_invoice_amount,
      v_effective_rate,v_date,coalesce(v_notes,'FX supplier payment conversion'));
    v_lines:=jsonb_build_array(
      jsonb_build_object('accountId',v_partner_account,'currency',v_invoice_currency,'debit',v_invoice_amount,'credit',0,'description','Supplier invoice settlement'),
      jsonb_build_object('accountId',v_linked_ledger,'currency',v_invoice_currency,'debit',0,'credit',v_invoice_amount,'description','Linked cashbox payment')
    );
    v_journal_id:=public.erp_phase2_insert_journal_at(
      p_company_id,p_module||'_payment',v_payment_id,
      public.erp_next_document_number(p_company_id,p_module||'_payment_journal','JE',v_date),
      'FX supplier payment '||p_invoice_id::text,v_invoice_currency,v_lines,v_date);
    insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_settlement_tx,jsonb_build_object(
      'id',v_settlement_tx,'voucherNumber',v_settlement_voucher,'type','payment',
      'category','purchase_invoice_settlement','amount',v_invoice_amount,
      'currency',v_invoice_currency,'transactionDate',v_date,'cashAccountId',v_linked_id,
      'counterAccountId',v_partner_account,'referenceType','purchases_payment',
      'referenceId',v_payment_id,'invoiceId',p_invoice_id::text,'orderId',p_order_id::text,
      'journalEntryId',v_journal_id,'paymentChainVersion','v756','notes',v_notes),auth.uid(),auth.uid());
  end if;

  return jsonb_build_object(
    'paymentId',v_payment_id,'cashTransactionId',v_settlement_tx,
    'voucherNumber',v_settlement_voucher,'journalEntryId',v_journal_id,
    'transferId',v_transfer->>'transferId','transferNumber',v_transfer->>'transferNumber',
    'cashAccountId',v_cash_id,'linkedCashAccountId',v_linked_id,
    'paymentCurrency',v_payment_currency,'invoiceCurrency',v_invoice_currency,
    'invoiceAmount',v_invoice_amount,'cashAmount',v_cash_amount,'exchangeRate',v_rate,
    'paymentDate',v_date,'paymentChainVersion','v756');
end;
$$;

create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  p jsonb; r jsonb; v_invoice_currency text; v_partner_id text;
  v_remaining numeric; v_paid numeric; v_amount numeric;
  v_results jsonb:='[]'::jsonb; v_history jsonb;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments)=0 then
    raise exception 'payment_batch_required';
  end if;
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_invoice_required'; end if;
  v_invoice_currency:=upper(coalesce(d.payload->>'currency',''));
  if p_module='sales' then
    select customer_id into v_partner_id from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=d.parent_id and not is_deleted;
  else
    select supplier_id into v_partner_id from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=d.parent_id and not is_deleted;
  end if;
  if v_partner_id is null then raise exception 'invoice_partner_required'; end if;
  v_paid:=public.erp_try_numeric(d.payload->>'paidAmount',0);
  v_remaining:=public.erp_try_numeric(d.payload->>'remainingAmount',
    public.erp_try_numeric(d.payload->>'totalAmount',0)-v_paid);
  v_history:=coalesce(d.payload->'payments','[]'::jsonb);
  for p in select value from jsonb_array_elements(p_payments) loop
    v_amount:=public.erp_try_numeric(p->>'invoiceAmount',0);
    if v_amount<=0 or v_amount>v_remaining+0.01 then raise exception 'invalid_or_excessive_invoice_payment'; end if;
    r:=public.erp_execute_secure_linked_payment_v1(
      p_company_id,p_module,p_invoice_id,d.parent_id,v_partner_id,v_invoice_currency,p);
    v_paid:=v_paid+v_amount; v_remaining:=greatest(0,v_remaining-v_amount);
    v_history:=v_history||jsonb_build_array(r); v_results:=v_results||jsonb_build_array(r);
  end loop;
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'payments',v_history,'paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case when v_remaining<=0.001 then 'paid' when v_paid>0 then 'partial' else 'unpaid' end,
    'paymentChainVersion','v756'),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;
  return v_results;
end;
$$;

create or replace function public.erp_v737_record_maintenance_payment(
  p_company_id uuid,p_order_id uuid,p_payment jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_payment_key text; v_existing public.erp_maintenance_payments%rowtype;
  v_invoice_amount numeric; v_remaining numeric; v_next numeric; r jsonb;
  v_payment_uuid uuid;
begin
  select * into o from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.pricing_type<>'paid' or o.sale_price<=0 or o.workflow_stage not in ('invoice_approved','paid')
     or o.invoice_journal_entry_id is null then raise exception 'maintenance_approved_invoice_required'; end if;
  v_payment_key:=coalesce(nullif(btrim(p_payment->>'paymentKey'),''),gen_random_uuid()::text);
  select * into v_existing from public.erp_maintenance_payments
   where company_id=p_company_id and maintenance_order_id=p_order_id
     and payment_key=v_payment_key and not is_deleted limit 1;
  if found then return jsonb_build_object('paymentId',v_existing.id,'paymentKey',v_payment_key,'idempotent',true); end if;
  v_remaining:=greatest(0,o.sale_price-coalesce(o.paid_amount,0));
  v_invoice_amount:=public.erp_try_numeric(p_payment->>'invoiceAmount',0);
  if lower(coalesce(p_payment->>'settlementMode','partial')) in ('full','settlement') then v_invoice_amount:=v_remaining; end if;
  if v_invoice_amount<=0 or v_invoice_amount>v_remaining+0.01 then raise exception 'maintenance_payment_exceeds_balance'; end if;
  r:=public.erp_execute_secure_linked_payment_v1(
    p_company_id,'maintenance',p_order_id,p_order_id,o.customer_id::text,upper(o.currency_code),
    p_payment||jsonb_build_object('invoiceAmount',v_invoice_amount));
  v_payment_uuid:=(r->>'paymentId')::uuid;
  insert into public.erp_maintenance_payments(
    id,company_id,maintenance_order_id,amount,currency_code,exchange_rate,
    amount_in_order_currency,payment_date,notes,cash_transaction_id,journal_entry_id,
    updated_at,updated_by,payment_key,settlement_mode,settlement_account_id,payment_payload)
  values(v_payment_uuid,p_company_id,o.id,public.erp_try_numeric(p_payment->>'cashAmount',0),
    upper(p_payment->>'paymentCurrency'),public.erp_try_numeric(p_payment->>'exchangeRate',0),
    v_invoice_amount,public.erp_try_timestamptz(p_payment->>'paymentDate',now()),nullif(btrim(p_payment->>'notes'),''),
    r->>'cashTransactionId',r->>'journalEntryId',now(),auth.uid(),v_payment_key,
    lower(coalesce(p_payment->>'settlementMode','partial')),null,r||jsonb_build_object('paymentKey',v_payment_key));
  v_next:=least(o.sale_price,coalesce(o.paid_amount,0)+v_invoice_amount);
  update public.erp_maintenance_orders set paid_amount=v_next,
    workflow_stage=case when v_next+0.001>=sale_price then 'paid' else 'invoice_approved' end,
    status=case when v_next+0.001>=sale_price then 'completed' else 'approved' end,updated_at=now()
  where company_id=p_company_id and id=o.id;
  return r||jsonb_build_object('paymentKey',v_payment_key,'remainingAmount',greatest(0,o.sale_price-v_next));
end;
$$;

revoke all on function public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb) to authenticated,service_role;
revoke all on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) to authenticated,service_role;
revoke all on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) from public,anon;
grant execute on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
