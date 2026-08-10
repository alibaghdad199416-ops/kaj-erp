-- Quality Line ERP 18.9.7 / V7.3.7
-- Atomic multi-currency maintenance invoice payments and invoice-owned reversal.
begin;

alter table public.erp_maintenance_payments
  add column if not exists payment_key text,
  add column if not exists settlement_mode text not null default 'partial',
  add column if not exists settlement_account_id text,
  add column if not exists payment_payload jsonb not null default '{}'::jsonb;

create unique index if not exists erp_maintenance_payments_active_key_uidx
  on public.erp_maintenance_payments(company_id,maintenance_order_id,payment_key)
  where not is_deleted and payment_key is not null;

create or replace function public.erp_v737_record_maintenance_payment(
  p_company_id uuid,
  p_order_id uuid,
  p_payment jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_payment_id uuid:=gen_random_uuid();
  v_payment_key text;
  v_cash_transaction_id text:=gen_random_uuid()::text;
  v_cash_account_id text;
  v_cash_ledger_id text;
  v_partner_account_id text;
  v_settlement_account_id text;
  v_journal_id text;
  v_voucher text;
  v_invoice_currency text;
  v_payment_currency text;
  v_mode text;
  v_invoice_amount numeric;
  v_cash_amount numeric;
  v_rate numeric;
  v_expected_cash numeric;
  v_difference numeric;
  v_remaining numeric;
  v_next numeric;
  v_tolerance numeric;
  v_payment_date timestamptz;
  v_lines jsonb;
  v_notes text;
  v_existing public.erp_maintenance_payments%rowtype;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cashbox.receipt']
  );
  if p_payment is null or jsonb_typeof(p_payment)<>'object' then
    raise exception 'maintenance_payment_payload_required';
  end if;

  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.pricing_type<>'paid' or o.sale_price<=0
     or o.workflow_stage not in ('invoice_approved','paid')
     or o.invoice_journal_entry_id is null then
    raise exception 'maintenance_approved_invoice_required';
  end if;

  v_payment_key:=coalesce(
    nullif(btrim(p_payment->>'paymentKey'),''),
    gen_random_uuid()::text
  );
  select * into v_existing
  from public.erp_maintenance_payments
  where company_id=p_company_id and maintenance_order_id=p_order_id
    and payment_key=v_payment_key and not is_deleted
  limit 1;
  if found then
    return jsonb_build_object(
      'paymentId',v_existing.id,'paymentKey',v_payment_key,
      'cashTransactionId',v_existing.cash_transaction_id,
      'journalEntryId',v_existing.journal_entry_id,
      'idempotent',true
    );
  end if;

  v_invoice_currency:=upper(o.currency_code);
  v_payment_currency:=upper(nullif(btrim(p_payment->>'paymentCurrency'),''));
  v_mode:=lower(coalesce(nullif(btrim(p_payment->>'settlementMode'),''),'partial'));
  v_cash_account_id:=nullif(btrim(p_payment->>'cashAccountId'),'');
  v_invoice_amount:=public.erp_try_numeric(p_payment->>'invoiceAmount',0);
  v_cash_amount:=public.erp_try_numeric(p_payment->>'cashAmount',0);
  v_rate:=public.erp_try_numeric(p_payment->>'exchangeRate',0);
  v_payment_date:=public.erp_try_timestamptz(p_payment->>'paymentDate',now());
  v_notes:=nullif(btrim(p_payment->>'notes'),'');
  v_remaining:=greatest(0,o.sale_price-coalesce(o.paid_amount,0));

  if v_invoice_currency not in ('IQD','USD')
     or v_payment_currency not in ('IQD','USD') then
    raise exception 'unsupported_currency';
  end if;
  if v_mode not in ('partial','full','settlement') then
    raise exception 'maintenance_invalid_settlement_mode';
  end if;
  if v_cash_account_id is null or v_cash_amount<=0 or v_rate<=0 or v_remaining<=0 then
    raise exception 'maintenance_invalid_payment';
  end if;
  if v_mode in ('full','settlement') then v_invoice_amount:=v_remaining; end if;
  if v_invoice_amount<=0 or v_invoice_amount>v_remaining+0.01 then
    raise exception 'maintenance_payment_exceeds_balance';
  end if;

  select ca.id,coalesce(ca.data->>'accountId',ca.data->>'account_id')
    into v_cash_account_id,v_cash_ledger_id
  from public.erp_cash_accounts as ca
  where ca.company_id=p_company_id and ca.id=v_cash_account_id
    and not ca.is_deleted
    and public.erp_try_boolean(ca.data->>'isActive',true)
    and upper(coalesce(ca.data->>'currency',''))=v_payment_currency
  for share;
  if not found or nullif(btrim(coalesce(v_cash_ledger_id,'')),'') is null then
    raise exception 'maintenance_cash_account_currency_mismatch:%',v_payment_currency;
  end if;
  perform public.erp_phase2_account_guard(
    p_company_id,v_cash_ledger_id,'asset',v_payment_currency
  );

  if o.customer_id is null then raise exception 'maintenance_customer_required_for_payment'; end if;
  v_partner_account_id:=public.erp_workflow_partner_account(
    p_company_id,'customer',o.customer_id::text,v_invoice_currency
  );

  v_expected_cash:=round(
    public.erp_v736_convert_currency(
      v_invoice_amount,v_invoice_currency,v_payment_currency,v_rate
    ),
    case when v_payment_currency='IQD' then 0 else 2 end
  );
  v_difference:=v_cash_amount-v_expected_cash;
  v_tolerance:=0.01;
  if v_mode in ('partial','full') and abs(v_difference)>v_tolerance then
    raise exception 'maintenance_cash_amount_mismatch:expected=%:actual=%',
      v_expected_cash,v_cash_amount;
  end if;

  if v_mode='settlement' then
    v_settlement_account_id:=nullif(btrim(p_payment->>'settlementAccountId'),'');
    if v_settlement_account_id is null then
      raise exception 'maintenance_settlement_account_required';
    end if;
    perform 1 from public.erp_accounts as a
    where a.organization_id=p_company_id
      and a.account_id=v_settlement_account_id and a.is_active
      and upper(coalesce(a.currency,'MULTI')) in ('MULTI',v_payment_currency)
    for share;
    if not found then raise exception 'maintenance_settlement_account_invalid'; end if;
  else
    v_difference:=0;
  end if;

  v_lines:=jsonb_build_array(
    jsonb_build_object(
      'accountId',v_cash_ledger_id,'currency',v_payment_currency,
      'debit',v_cash_amount,'credit',0,
      'description','استلام دفعة فاتورة صيانة',
      'maintenanceOrderId',o.id::text,'paymentId',v_payment_id::text
    ),
    jsonb_build_object(
      'accountId',v_partner_account_id,'currency',v_payment_currency,
      'debit',0,'credit',v_expected_cash,
      'accountCurrencyAmount',v_invoice_amount,
      'accountCurrency',v_invoice_currency,
      'description','تسوية ذمة فاتورة صيانة',
      'maintenanceOrderId',o.id::text,'paymentId',v_payment_id::text
    )
  );
  if v_mode='settlement' and abs(v_difference)>0.001 then
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'accountId',v_settlement_account_id,'currency',v_payment_currency,
      'debit',case when v_difference<0 then abs(v_difference) else 0 end,
      'credit',case when v_difference>0 then v_difference else 0 end,
      'description','فرق تسوية دفعة صيانة',
      'maintenanceOrderId',o.id::text,'paymentId',v_payment_id::text
    ));
  end if;

  v_journal_id:=public.erp_phase2_insert_journal_at(
    p_company_id,'maintenance_payment_journal',v_payment_id::text,
    public.erp_next_document_number(
      p_company_id,'maintenance_payment_journal','MPJ',v_payment_date
    ),
    'قيد دفعة فاتورة الصيانة '||coalesce(o.invoice_number,o.order_number),
    v_payment_currency,v_lines,v_payment_date
  );
  v_voucher:=public.erp_next_document_number(
    p_company_id,'maintenance_payment','MP',v_payment_date
  );

  insert into public.erp_cash_transactions(
    company_id,id,data,created_by,updated_by
  ) values(
    p_company_id,v_cash_transaction_id,jsonb_build_object(
      'id',v_cash_transaction_id,'cashAccountId',v_cash_account_id,
      'counterAccountId',v_partner_account_id,'voucherNumber',v_voucher,
      'type','receipt','currency',v_payment_currency,'amount',v_cash_amount,
      'exchangeRate',v_rate,'invoiceAmount',v_invoice_amount,
      'invoiceCurrency',v_invoice_currency,'transactionDate',v_payment_date,
      'category','maintenance_payment','referenceType','maintenance_payment',
      'referenceId',v_payment_id::text,'maintenanceOrderId',o.id::text,
      'invoiceNumber',o.invoice_number,'journalEntryId',v_journal_id,
      'settlementMode',v_mode,'settlementAccountId',v_settlement_account_id,
      'paymentKey',v_payment_key,
      'notes',coalesce(v_notes,'Maintenance invoice payment '||o.order_number)
    ),auth.uid(),auth.uid()
  );

  insert into public.erp_maintenance_payments(
    id,company_id,maintenance_order_id,amount,currency_code,exchange_rate,
    amount_in_order_currency,payment_date,notes,cash_transaction_id,
    journal_entry_id,updated_at,updated_by,payment_key,settlement_mode,
    settlement_account_id,payment_payload
  ) values(
    v_payment_id,p_company_id,o.id,v_cash_amount,v_payment_currency,v_rate,
    v_invoice_amount,v_payment_date,v_notes,v_cash_transaction_id,
    v_journal_id,now(),auth.uid(),v_payment_key,v_mode,
    v_settlement_account_id,p_payment||jsonb_build_object(
      'paymentId',v_payment_id::text,'paymentKey',v_payment_key,
      'invoiceCurrency',v_invoice_currency,'appliedInvoiceAmount',v_invoice_amount,
      'expectedCashAmount',v_expected_cash,'exchangeDifference',v_difference,
      'cashTransactionId',v_cash_transaction_id,'journalEntryId',v_journal_id
    )
  );

  v_next:=least(o.sale_price,coalesce(o.paid_amount,0)+v_invoice_amount);
  update public.erp_maintenance_orders
  set paid_amount=v_next,
      workflow_stage=case when v_next+0.001>=sale_price then 'paid' else 'invoice_approved' end,
      status=case when v_next+0.001>=sale_price then 'completed' else 'approved' end,
      updated_at=now()
  where company_id=p_company_id and id=o.id;

  return jsonb_build_object(
    'paymentId',v_payment_id,'paymentKey',v_payment_key,
    'cashTransactionId',v_cash_transaction_id,'journalEntryId',v_journal_id,
    'invoiceAmount',v_invoice_amount,'cashAmount',v_cash_amount,
    'paymentCurrency',v_payment_currency,'invoiceCurrency',v_invoice_currency,
    'settlementMode',v_mode,'remainingAmount',greatest(0,o.sale_price-v_next)
  );
end;
$$;

create or replace function public.erp_record_cloud_maintenance_payment_batch(
  p_company_id uuid,
  p_order_id uuid,
  p_payments jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_row record;
  v_mode text;
  v_count integer;
  v_results jsonb:='[]'::jsonb;
begin
  if p_payments is null or jsonb_typeof(p_payments)<>'array' then
    raise exception 'maintenance_payment_batch_required';
  end if;
  v_count:=jsonb_array_length(p_payments);
  if v_count=0 then raise exception 'maintenance_payment_batch_required'; end if;

  for v_row in
    select value,ordinality
    from jsonb_array_elements(p_payments) with ordinality
  loop
    v_mode:=lower(coalesce(nullif(btrim(v_row.value->>'settlementMode'),''),'partial'));
    if v_mode in ('full','settlement') and v_row.ordinality<>v_count then
      raise exception 'maintenance_closing_payment_must_be_last';
    end if;
    v_results:=v_results||jsonb_build_array(
      public.erp_v737_record_maintenance_payment(
        p_company_id,p_order_id,
        v_row.value||jsonb_build_object(
          'paymentKey',coalesce(
            nullif(v_row.value->>'paymentKey',''),
            p_order_id::text||'-'||md5(v_row.value::text)||'-'||v_row.ordinality::text
          )
        )
      )
    );
  end loop;
  return v_results;
end;
$$;

-- Backward-compatible single-payment endpoint. The selected cash account is
-- resolved explicitly and the same invoice-owned batch accounting is used.
create or replace function public.erp_record_cloud_maintenance_payment(
  p_company_id uuid,p_order_id uuid,p_amount numeric,
  p_currency_code text default null,p_exchange_rate numeric default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_currency text;
  v_rate numeric;
  v_invoice_amount numeric;
  v_cash_id text;
  v_result jsonb;
begin
  select * into o from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  v_currency:=upper(coalesce(nullif(btrim(p_currency_code),''),o.currency_code));
  v_rate:=coalesce(nullif(p_exchange_rate,0),nullif(o.exchange_rate,0),1);
  v_invoice_amount:=public.erp_v736_convert_currency(
    p_amount,v_currency,upper(o.currency_code),v_rate
  );
  select ca.id into v_cash_id from public.erp_cash_accounts as ca
  where ca.company_id=p_company_id and not ca.is_deleted
    and public.erp_try_boolean(ca.data->>'isActive',true)
    and upper(coalesce(ca.data->>'currency',''))=v_currency
    and nullif(coalesce(ca.data->>'accountId',ca.data->>'account_id'),'') is not null
  order by public.erp_try_boolean(
    coalesce(ca.data->>'isDefault',ca.data->>'is_default'),false
  ) desc,ca.created_at
  limit 1;
  if v_cash_id is null then raise exception 'maintenance_cash_account_required:%',v_currency; end if;
  v_result:=public.erp_v737_record_maintenance_payment(
    p_company_id,p_order_id,jsonb_build_object(
      'cashAccountId',v_cash_id,'paymentCurrency',v_currency,
      'invoiceAmount',v_invoice_amount,'cashAmount',p_amount,
      'exchangeRate',v_rate,'settlementMode','partial',
      'paymentDate',now(),'notes',p_notes,'paymentMethod','cash'
    )
  );
  return (v_result->>'paymentId')::uuid;
end;
$$;

-- Deleting a maintenance invoice preserves received cash as customer credit,
-- reverses invoice-owned journals and valuation, but leaves stock quantities
-- untouched. Stock reversal remains a separate downstream action.
create or replace function public.erp_manage_maintenance_order_component(
  p_company_id uuid,
  p_order_id uuid,
  p_component_type text,
  p_action text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_target_stage text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Maintenance component action');
  v_detached jsonb;
  v_entry jsonb;
  v_car_id text;
  v_previous_maintenance numeric;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.update','maintenance.delete']
  );
  select * into v_order from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  if p_component_type='payment' then raise exception 'payment_is_cashbox_owned'; end if;
  if p_component_type='order' and p_action='delete' then
    return public.erp_delete_cloud_maintenance_order_v3(p_company_id,p_order_id,v_reason);
  end if;
  if p_action='approve' then
    perform public.erp_advance_cloud_maintenance_workflow(p_company_id,p_order_id);
    return jsonb_build_object('ok',true,'action','approve','componentType',p_component_type,'linksUpdated',true);
  end if;
  if p_action<>'delete' then raise exception 'invalid_component_action'; end if;

  if p_component_type='invoice' then
    v_detached:=public.erp_v731_detach_maintenance_payments(
      p_company_id,p_order_id,v_reason
    );
    perform public.erp_v736_void_journal_id(p_company_id,v_order.invoice_journal_entry_id);
    for v_entry in select value from jsonb_array_elements(coalesce(v_order.cost_journal_entry_ids,'[]'::jsonb))
    loop
      perform public.erp_v736_void_journal_id(
        p_company_id,nullif(coalesce(v_entry->>'journalEntryId',v_entry#>>'{}'),'')
      );
    end loop;

    if not v_order.is_sold_car and coalesce(v_order.car_cost_added,0)<>0 then
      v_car_id:=coalesce(v_order.source_car_id,v_order.car_id::text);
      v_previous_maintenance:=public.erp_try_numeric(
        v_order.accounting_payload->>'previousCarMaintenanceCost',0
      );
      update public.erp_cars
      set data=data||jsonb_build_object(
        'maintenanceCost',v_previous_maintenance,
        'maintenance_cost',v_previous_maintenance,
        'maintenanceValuationInvoiceId',null,
        'maintenanceValuationReversedAt',now(),'updatedAt',now()
      ),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_car_id and not is_deleted;
    end if;

    v_target_stage:='stock_issue_approved';
    update public.erp_maintenance_orders
    set invoice_number=null,paid_amount=0,workflow_stage=v_target_stage,
        status='in_progress',car_cost_added=0,invoice_journal_entry_id=null,
        cost_journal_entry_ids='[]'::jsonb,
        accounting_payload=accounting_payload||jsonb_build_object(
          'invoiceDeletedAt',now(),'invoiceDeleteReason',v_reason,
          'valuationReversedAt',now(),'accountingReversedAt',now(),
          'paymentsPreserved',true
        ),updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  elsif p_component_type='stock' then
    if v_order.workflow_stage in ('invoice_draft','invoice_approved','paid','closed')
       or v_order.invoice_journal_entry_id is not null then
      raise exception 'delete_invoice_component_first';
    end if;
    perform public.erp_v66_reverse_maintenance_stock(p_company_id,p_order_id,v_reason);
    v_target_stage:='order_approved';
    update public.erp_maintenance_orders
    set stock_issue_number=null,workflow_stage=v_target_stage,
        status='approved',updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  elsif p_component_type='order_approval' then
    if v_order.workflow_stage not in ('order_approved','order_draft') then
      raise exception 'delete_downstream_components_first';
    end if;
    v_target_stage:='order_draft';
    update public.erp_maintenance_orders
    set workflow_stage=v_target_stage,status='draft',updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  else
    raise exception 'invalid_component_type';
  end if;

  return jsonb_build_object(
    'ok',true,'action','delete','componentType',p_component_type,
    'orderId',p_order_id,'workflowStage',v_target_stage,'linksUpdated',true,
    'paymentsPreserved',p_component_type='invoice','detachment',v_detached
  );
end;
$$;

revoke all on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_record_cloud_maintenance_payment_batch(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_record_cloud_maintenance_payment(uuid,uuid,numeric,text,numeric,text) from public,anon;
revoke all on function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text) from public,anon;

grant execute on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_record_cloud_maintenance_payment_batch(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_record_cloud_maintenance_payment(uuid,uuid,numeric,text,numeric,text) to authenticated,service_role;
grant execute on function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text) to authenticated,service_role;

commit;
