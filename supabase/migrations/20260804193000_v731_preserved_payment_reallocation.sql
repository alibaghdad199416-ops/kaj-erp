-- Quality Line ERP 18.9.1 / V7.3.1
-- Preserve financial payments when operational documents are reversed and
-- allocate the remaining partner balance to later invoices for the same party.
begin;

create table if not exists public.erp_partner_advance_allocations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  cash_transaction_id text not null,
  journal_entry_id text,
  party_type text not null,
  party_id text not null,
  currency text not null,
  target_module text not null,
  target_order_id uuid not null,
  target_invoice_id uuid,
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  created_by uuid,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  deleted_by uuid,
  deletion_reason text,
  unique(company_id,cash_transaction_id,target_module,target_order_id,target_invoice_id)
);

create index if not exists erp_partner_advance_allocations_source_idx
  on public.erp_partner_advance_allocations(company_id,cash_transaction_id)
  where not is_deleted;
create index if not exists erp_partner_advance_allocations_target_idx
  on public.erp_partner_advance_allocations(company_id,target_module,target_order_id,target_invoice_id)
  where not is_deleted;
create index if not exists erp_partner_advance_allocations_party_idx
  on public.erp_partner_advance_allocations(company_id,party_type,party_id,currency)
  where not is_deleted;
create unique index if not exists erp_partner_advance_allocations_active_target_uidx
  on public.erp_partner_advance_allocations(
    company_id,cash_transaction_id,target_module,target_order_id,
    coalesce(target_invoice_id,'00000000-0000-0000-0000-000000000000'::uuid)
  )
  where not is_deleted;

alter table public.erp_partner_advance_allocations enable row level security;
drop policy if exists erp_partner_advance_allocations_select
  on public.erp_partner_advance_allocations;
create policy erp_partner_advance_allocations_select
  on public.erp_partner_advance_allocations for select to authenticated
  using (public.erp_is_company_member(company_id));
revoke insert,update,delete on public.erp_partner_advance_allocations
  from anon,authenticated;
grant select on public.erp_partner_advance_allocations to authenticated;

alter table public.erp_maintenance_payments
  add column if not exists advance_allocation_id uuid,
  add column if not exists is_advance_application boolean not null default false,
  add column if not exists source_cash_transaction_id text;
create index if not exists erp_maintenance_payments_advance_allocation_idx
  on public.erp_maintenance_payments(company_id,advance_allocation_id)
  where not is_deleted and advance_allocation_id is not null;

create or replace function public.erp_v731_advance_original_amount(
  p_data jsonb
) returns numeric
language sql
immutable
as $$
  select greatest(0,public.erp_try_numeric(coalesce(
    p_data->>'advanceAmount',
    p_data->>'advance_amount',
    p_data->>'invoiceAmount',
    p_data->>'invoice_amount',
    p_data->>'amountInOrderCurrency',
    p_data->>'amount_in_order_currency',
    p_data->>'amount'
  ),0));
$$;

create or replace function public.erp_v731_advance_allocated_amount(
  p_company_id uuid,
  p_cash_transaction_id text
) returns numeric
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(sum(a.amount),0)
  from public.erp_partner_advance_allocations as a
  where a.company_id=p_company_id
    and a.cash_transaction_id=p_cash_transaction_id
    and not a.is_deleted;
$$;

create or replace function public.erp_v731_refresh_advance_cache(
  p_company_id uuid,
  p_cash_transaction_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transaction public.erp_cash_transactions%rowtype;
  v_journal_id text;
  v_original numeric;
  v_allocated numeric;
  v_available numeric;
  v_currency text;
begin
  select ct.* into v_transaction
  from public.erp_cash_transactions as ct
  where ct.company_id=p_company_id
    and ct.id=p_cash_transaction_id
    and not ct.is_deleted
  for update;
  if not found then
    return jsonb_build_object('found',false,'available',0);
  end if;

  v_journal_id:=coalesce(
    nullif(v_transaction.data->>'journalEntryId',''),
    nullif(v_transaction.data->>'journal_entry_id',''),
    nullif(v_transaction.data->>'entryId',''),
    nullif(v_transaction.data->>'entry_id','')
  );
  select upper(coalesce(
    nullif(v_transaction.data->>'accountCurrency',''),
    nullif(v_transaction.data->>'account_currency',''),
    nullif(je.data->>'currency',''),
    nullif(v_transaction.data->>'invoiceCurrency',''),
    nullif(v_transaction.data->>'invoice_currency',''),
    nullif(v_transaction.data->>'currency',''),
    'USD'
  )) into v_currency
  from (select 1) as seed
  left join public.erp_journal_entries as je
    on je.company_id=p_company_id and je.id=v_journal_id and not je.is_deleted;

  v_original:=public.erp_v731_advance_original_amount(v_transaction.data);
  v_allocated:=public.erp_v731_advance_allocated_amount(
    p_company_id,p_cash_transaction_id
  );
  v_available:=greatest(0,v_original-v_allocated);

  update public.erp_cash_transactions as ct
  set data=ct.data||jsonb_build_object(
        'referenceType','partner_advance',
        'accountCurrency',v_currency,
        'advanceAmount',v_original,
        'allocatedAmount',v_allocated,
        'unappliedAmount',v_available,
        'unapplied',v_available>0.001,
        'advanceCacheUpdatedAt',now()
      ),
      updated_at=now(),
      updated_by=auth.uid()
  where ct.company_id=p_company_id and ct.id=p_cash_transaction_id;

  if v_journal_id is not null then
    update public.erp_journal_entries as je
    set data=je.data||jsonb_build_object(
          'referenceType','partner_advance',
          'accountCurrency',v_currency,
          'advanceAmount',v_original,
          'allocatedAmount',v_allocated,
          'unappliedAmount',v_available,
          'unapplied',v_available>0.001,
          'advanceCacheUpdatedAt',now()
        ),
        updated_at=now(),
        updated_by=auth.uid()
    where je.company_id=p_company_id and je.id=v_journal_id and not je.is_deleted;
  end if;

  return jsonb_build_object(
    'found',true,'original',v_original,'allocated',v_allocated,
    'available',v_available,'currency',v_currency
  );
end;
$$;

create or replace function public.erp_v731_normalize_order_advances(
  p_company_id uuid,
  p_order_id uuid
) returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_cash record;
  v_count integer:=0;
begin
  for v_cash in
    select ct.id
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and lower(coalesce(
        ct.data->>'referenceType',ct.data->>'reference_type',''
      ))='partner_advance'
      and coalesce(
        ct.data->>'detachedFromOrderId',
        ct.data->>'detached_from_order_id',
        ct.data->>'detachedFromMaintenanceOrderId',
        ct.data->>'detached_from_maintenance_order_id'
      )=p_order_id::text
  loop
    perform public.erp_v731_refresh_advance_cache(p_company_id,v_cash.id);
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.erp_v731_release_advance_allocations(
  p_company_id uuid,
  p_target_module text,
  p_target_order_id uuid,
  p_target_invoice_id uuid default null,
  p_reason text default null
) returns numeric
language plpgsql
security definer
set search_path=public
as $$
declare
  v_allocation record;
  v_released numeric:=0;
begin
  for v_allocation in
    select a.id,a.cash_transaction_id,a.amount
    from public.erp_partner_advance_allocations as a
    where a.company_id=p_company_id
      and a.target_module=p_target_module
      and a.target_order_id=p_target_order_id
      and (p_target_invoice_id is null or a.target_invoice_id=p_target_invoice_id)
      and not a.is_deleted
    for update
  loop
    update public.erp_partner_advance_allocations
    set is_deleted=true,deleted_at=now(),deleted_by=auth.uid(),
        deletion_reason=coalesce(p_reason,'Operational component reversed')
    where company_id=p_company_id and id=v_allocation.id;

    update public.erp_maintenance_payments
    set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id
      and advance_allocation_id=v_allocation.id
      and not is_deleted;

    perform public.erp_v731_refresh_advance_cache(
      p_company_id,v_allocation.cash_transaction_id
    );
    v_released:=v_released+v_allocation.amount;
  end loop;
  return v_released;
end;
$$;

create or replace function public.erp_v731_apply_advance_to_commercial_invoice(
  p_company_id uuid,
  p_invoice_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_partner_type text;
  v_partner_id text;
  v_currency text;
  v_remaining numeric;
  v_paid numeric;
  v_total numeric;
  v_cash record;
  v_original numeric;
  v_allocated numeric;
  v_available numeric;
  v_apply numeric;
  v_application_id uuid;
  v_payment jsonb;
  v_payload jsonb;
  v_applied_total numeric:=0;
  v_journal_id text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;

  select d.* into v_doc
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.id=p_invoice_id
    and d.document_type='invoice'
    and d.status='approved'
    and not d.is_deleted
  for update;
  if not found then
    return jsonb_build_object('applied',0,'reason','invoice_not_approved');
  end if;

  if v_doc.module='sales' then
    select o.customer_id into v_partner_id
    from public.erp_sales_orders_cloud as o
    where o.company_id=p_company_id and o.id=v_doc.parent_id and not o.is_deleted;
    v_partner_type:='customer';
  elsif v_doc.module='purchases' then
    select o.supplier_id into v_partner_id
    from public.erp_purchase_orders_cloud as o
    where o.company_id=p_company_id and o.id=v_doc.parent_id and not o.is_deleted;
    v_partner_type:='supplier';
  else
    return jsonb_build_object('applied',0,'reason','unsupported_module');
  end if;

  if nullif(v_partner_id,'') is null then
    return jsonb_build_object('applied',0,'reason','partner_missing');
  end if;

  v_payload:=v_doc.payload;
  v_currency:=upper(coalesce(nullif(v_payload->>'currency',''),'USD'));
  v_remaining:=public.erp_try_numeric(v_payload->>'remainingAmount',0);
  v_paid:=public.erp_try_numeric(v_payload->>'paidAmount',0);
  v_total:=public.erp_try_numeric(v_payload->>'totalAmount',v_paid+v_remaining);
  if v_remaining<=0.001 then
    return jsonb_build_object('applied',0,'remaining',0);
  end if;

  for v_cash in
    select ct.id,ct.data,ct.created_at,
           coalesce(
             nullif(ct.data->>'journalEntryId',''),
             nullif(ct.data->>'journal_entry_id',''),
             nullif(ct.data->>'entryId',''),
             nullif(ct.data->>'entry_id','')
           ) as journal_id,
           upper(coalesce(
             nullif(ct.data->>'accountCurrency',''),
             nullif(je.data->>'currency',''),
             nullif(ct.data->>'invoiceCurrency',''),
             nullif(ct.data->>'currency',''),
             'USD'
           )) as account_currency
    from public.erp_cash_transactions as ct
    left join public.erp_journal_entries as je
      on je.company_id=ct.company_id
     and je.id=coalesce(
       nullif(ct.data->>'journalEntryId',''),
       nullif(ct.data->>'journal_entry_id',''),
       nullif(ct.data->>'entryId',''),
       nullif(ct.data->>'entry_id','')
     )
     and not je.is_deleted
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and lower(coalesce(
        ct.data->>'referenceType',ct.data->>'reference_type',''
      ))='partner_advance'
      and lower(coalesce(
        ct.data->>'partyType',ct.data->>'party_type',''
      ))=v_partner_type
      and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=v_partner_id
    order by coalesce(
      public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),
      ct.created_at
    ),ct.id
    for update of ct
  loop
    exit when v_remaining<=0.001;
    if v_cash.account_currency<>v_currency then continue; end if;

    v_original:=public.erp_v731_advance_original_amount(v_cash.data);
    v_allocated:=public.erp_v731_advance_allocated_amount(
      p_company_id,v_cash.id
    );
    v_available:=greatest(0,v_original-v_allocated);
    if v_available<=0.001 then
      perform public.erp_v731_refresh_advance_cache(p_company_id,v_cash.id);
      continue;
    end if;

    v_apply:=least(v_available,v_remaining);
    v_application_id:=gen_random_uuid();
    insert into public.erp_partner_advance_allocations(
      id,company_id,cash_transaction_id,journal_entry_id,
      party_type,party_id,currency,target_module,target_order_id,
      target_invoice_id,amount,created_by
    ) values(
      v_application_id,p_company_id,v_cash.id,v_cash.journal_id,
      v_partner_type,v_partner_id,v_currency,v_doc.module,v_doc.parent_id,
      v_doc.id,v_apply,auth.uid()
    ) on conflict do nothing;
    if not found then continue; end if;

    v_payment:=jsonb_build_object(
      'paymentId','ADV-'||v_application_id::text,
      'paymentKey',md5(v_application_id::text),
      'advanceAllocationId',v_application_id::text,
      'cashTransactionId',v_cash.id,
      'journalEntryId',v_cash.journal_id,
      'invoiceId',v_doc.id::text,
      'invoiceCurrency',v_currency,
      'invoiceAmount',v_apply,
      'appliedInvoiceAmount',v_apply,
      'cashAmount',v_apply,
      'paymentCurrency',v_currency,
      'exchangeRate',1,
      'settlementMode','partner_advance',
      'source','preserved_partner_balance',
      'isNonCashApplication',true,
      'paymentDate',now(),
      'createdAt',now(),
      'createdBy',auth.uid()
    );
    v_payload:=jsonb_set(
      v_payload,'{payments}',
      coalesce(v_payload->'payments','[]'::jsonb)||jsonb_build_array(v_payment),
      true
    );
    v_remaining:=greatest(0,v_remaining-v_apply);
    v_paid:=least(v_total,v_paid+v_apply);
    v_applied_total:=v_applied_total+v_apply;
    perform public.erp_v731_refresh_advance_cache(p_company_id,v_cash.id);
  end loop;

  if v_applied_total>0 then
    v_payload:=jsonb_set(v_payload,'{remainingAmount}',to_jsonb(v_remaining),true);
    v_payload:=jsonb_set(v_payload,'{paidAmount}',to_jsonb(v_paid),true);
    v_payload:=jsonb_set(
      v_payload,'{paymentStatus}',
      to_jsonb((case when v_remaining<=0.001 then 'paid' else 'partial' end)::text),
      true
    );
    v_payload:=v_payload||jsonb_build_object(
      'partnerAdvanceApplied',v_applied_total,
      'partnerAdvanceAppliedAt',now()
    );
    update public.erp_commercial_workflow_documents
    set payload=v_payload,updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=p_invoice_id;

    perform public.erp_commercial_audit(
      p_company_id,v_doc.module,v_doc.parent_id,v_doc.id,v_doc.document_number,
      'apply_partner_advance','approved','approved',
      'Preserved partner balance applied automatically'
    );
  end if;

  return jsonb_build_object(
    'applied',v_applied_total,'remaining',v_remaining,
    'partyType',v_partner_type,'partyId',v_partner_id,'currency',v_currency
  );
end;
$$;

create or replace function public.erp_v731_detach_maintenance_payments(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_payment record;
  v_cash_id text;
  v_journal_id text;
  v_detached integer:=0;
  v_released numeric:=0;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Maintenance component reversed');
begin
  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id and o.id=p_order_id
  for update;
  if not found then return jsonb_build_object('detached',0,'released',0); end if;

  v_released:=public.erp_v731_release_advance_allocations(
    p_company_id,'maintenance',p_order_id,null,v_reason
  );

  for v_payment in
    select p.*
    from public.erp_maintenance_payments as p
    where p.company_id=p_company_id
      and p.maintenance_order_id=p_order_id
      and not p.is_deleted
      and not p.is_advance_application
    for update
  loop
    v_cash_id:=coalesce(v_payment.cash_transaction_id,v_payment.source_cash_transaction_id);
    v_journal_id:=v_payment.journal_entry_id;
    if v_cash_id is not null then
      update public.erp_cash_transactions as ct
      set data=(ct.data
          - 'maintenanceOrderId' - 'maintenance_order_id'
          - 'invoiceId' - 'invoice_id'
          - 'orderId' - 'order_id'
          - 'referenceId' - 'reference_id'
          - 'referenceType' - 'reference_type')||jsonb_build_object(
            'referenceType','partner_advance',
            'referenceId',coalesce(v_order.customer_id::text,v_cash_id),
            'partyType','customer',
            'partyId',v_order.customer_id::text,
            'accountCurrency',upper(v_order.currency_code),
            'advanceAmount',v_payment.amount_in_order_currency,
            'unapplied',true,
            'detachedFromMaintenanceOrderId',p_order_id::text,
            'detachedAt',now(),
            'detachmentReason',v_reason
          ),
          updated_at=now(),updated_by=auth.uid()
      where ct.company_id=p_company_id and ct.id=v_cash_id and not ct.is_deleted;
    end if;

    if v_journal_id is not null then
      update public.erp_journal_entries as je
      set data=(je.data
          - 'maintenanceOrderId' - 'maintenance_order_id'
          - 'invoiceId' - 'invoice_id'
          - 'orderId' - 'order_id'
          - 'referenceId' - 'reference_id'
          - 'referenceType' - 'reference_type')||jsonb_build_object(
            'referenceType','partner_advance',
            'referenceId',coalesce(v_order.customer_id::text,v_journal_id),
            'partyType','customer',
            'partyId',v_order.customer_id::text,
            'accountCurrency',upper(v_order.currency_code),
            'advanceAmount',v_payment.amount_in_order_currency,
            'unapplied',true,
            'detachedFromMaintenanceOrderId',p_order_id::text,
            'detachedAt',now(),
            'detachmentReason',v_reason
          ),
          updated_at=now(),updated_by=auth.uid()
      where je.company_id=p_company_id and je.id=v_journal_id and not je.is_deleted;
    end if;

    update public.erp_maintenance_payments
    set is_unapplied=true,
        detached_from_order_id=coalesce(detached_from_order_id,p_order_id),
        partner_type='customer',
        partner_id=v_order.customer_id::text,
        detached_at=coalesce(detached_at,now()),
        updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_payment.id;

    if v_cash_id is not null then
      perform public.erp_v731_refresh_advance_cache(p_company_id,v_cash_id);
    end if;
    v_detached:=v_detached+1;
  end loop;

  update public.erp_maintenance_orders
  set paid_amount=0,updated_at=now()
  where company_id=p_company_id and id=p_order_id and not is_deleted;

  return jsonb_build_object(
    'detached',v_detached,'released',v_released,
    'paymentDisposition','customer_unapplied_credit'
  );
end;
$$;

create or replace function public.erp_v731_apply_advance_to_maintenance_order(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_currency text;
  v_remaining numeric;
  v_cash record;
  v_original numeric;
  v_allocated numeric;
  v_available numeric;
  v_apply numeric;
  v_application_id uuid;
  v_payment_id uuid;
  v_applied_total numeric:=0;
begin
  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id
    and o.id=p_order_id
    and not o.is_deleted
    and o.workflow_stage in ('invoice_approved','paid','closed')
  for update;
  if not found or v_order.customer_id is null then
    return jsonb_build_object('applied',0);
  end if;

  v_currency:=upper(v_order.currency_code);
  v_remaining:=greatest(0,v_order.sale_price-v_order.paid_amount);
  if v_remaining<=0.001 then return jsonb_build_object('applied',0,'remaining',0); end if;

  for v_cash in
    select ct.id,ct.data,ct.created_at,
           coalesce(
             nullif(ct.data->>'journalEntryId',''),
             nullif(ct.data->>'journal_entry_id',''),
             nullif(ct.data->>'entryId',''),
             nullif(ct.data->>'entry_id','')
           ) as journal_id,
           upper(coalesce(
             nullif(ct.data->>'accountCurrency',''),
             nullif(je.data->>'currency',''),
             nullif(ct.data->>'invoiceCurrency',''),
             nullif(ct.data->>'currency',''),
             'USD'
           )) as account_currency
    from public.erp_cash_transactions as ct
    left join public.erp_journal_entries as je
      on je.company_id=ct.company_id
     and je.id=coalesce(
       nullif(ct.data->>'journalEntryId',''),
       nullif(ct.data->>'journal_entry_id',''),
       nullif(ct.data->>'entryId',''),
       nullif(ct.data->>'entry_id','')
     )
     and not je.is_deleted
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and lower(coalesce(
        ct.data->>'referenceType',ct.data->>'reference_type',''
      ))='partner_advance'
      and lower(coalesce(
        ct.data->>'partyType',ct.data->>'party_type',''
      ))='customer'
      and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=v_order.customer_id::text
    order by coalesce(
      public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),
      ct.created_at
    ),ct.id
    for update of ct
  loop
    exit when v_remaining<=0.001;
    if v_cash.account_currency<>v_currency then continue; end if;

    v_original:=public.erp_v731_advance_original_amount(v_cash.data);
    v_allocated:=public.erp_v731_advance_allocated_amount(p_company_id,v_cash.id);
    v_available:=greatest(0,v_original-v_allocated);
    if v_available<=0.001 then
      perform public.erp_v731_refresh_advance_cache(p_company_id,v_cash.id);
      continue;
    end if;

    v_apply:=least(v_available,v_remaining);
    v_application_id:=gen_random_uuid();
    insert into public.erp_partner_advance_allocations(
      id,company_id,cash_transaction_id,journal_entry_id,
      party_type,party_id,currency,target_module,target_order_id,
      target_invoice_id,amount,created_by
    ) values(
      v_application_id,p_company_id,v_cash.id,v_cash.journal_id,
      'customer',v_order.customer_id::text,v_currency,'maintenance',v_order.id,
      null,v_apply,auth.uid()
    ) on conflict do nothing;
    if not found then continue; end if;

    v_payment_id:=gen_random_uuid();
    insert into public.erp_maintenance_payments(
      id,company_id,maintenance_order_id,amount,currency_code,exchange_rate,
      amount_in_order_currency,payment_date,notes,cash_transaction_id,
      journal_entry_id,advance_allocation_id,is_advance_application,
      source_cash_transaction_id,is_unapplied,updated_at,updated_by
    ) values(
      v_payment_id,p_company_id,v_order.id,v_apply,v_currency,1,
      v_apply,now(),'Applied preserved customer balance',v_cash.id,
      v_cash.journal_id,v_application_id,true,v_cash.id,false,now(),auth.uid()
    );

    v_remaining:=greatest(0,v_remaining-v_apply);
    v_applied_total:=v_applied_total+v_apply;
    perform public.erp_v731_refresh_advance_cache(p_company_id,v_cash.id);
  end loop;

  if v_applied_total>0 then
    update public.erp_maintenance_orders
    set paid_amount=least(sale_price,paid_amount+v_applied_total),
        workflow_stage=case
          when paid_amount+v_applied_total+0.001>=sale_price then 'paid'
          else 'invoice_approved'
        end,
        status=case
          when paid_amount+v_applied_total+0.001>=sale_price then 'completed'
          else 'approved'
        end,
        updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  end if;

  return jsonb_build_object(
    'applied',v_applied_total,'remaining',v_remaining,
    'partyType','customer','partyId',v_order.customer_id::text,
    'currency',v_currency
  );
end;
$$;

create or replace function public.erp_v731_auto_apply_commercial_advance()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.document_type='invoice'
     and new.status='approved'
     and not new.is_deleted then
    perform public.erp_v731_apply_advance_to_commercial_invoice(
      new.company_id,new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists erp_v731_auto_apply_commercial_advance_insert
  on public.erp_commercial_workflow_documents;
create trigger erp_v731_auto_apply_commercial_advance_insert
after insert on public.erp_commercial_workflow_documents
for each row execute function public.erp_v731_auto_apply_commercial_advance();

drop trigger if exists erp_v731_auto_apply_commercial_advance_status
  on public.erp_commercial_workflow_documents;
create trigger erp_v731_auto_apply_commercial_advance_status
after update of status on public.erp_commercial_workflow_documents
for each row execute function public.erp_v731_auto_apply_commercial_advance();

create or replace function public.erp_v731_auto_apply_maintenance_advance()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if pg_trigger_depth()>1 then return new; end if;
  if new.workflow_stage in ('invoice_approved','paid','closed')
     and not new.is_deleted then
    perform public.erp_v731_apply_advance_to_maintenance_order(
      new.company_id,new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists erp_v731_auto_apply_maintenance_advance_insert
  on public.erp_maintenance_orders;
create trigger erp_v731_auto_apply_maintenance_advance_insert
after insert on public.erp_maintenance_orders
for each row execute function public.erp_v731_auto_apply_maintenance_advance();

drop trigger if exists erp_v731_auto_apply_maintenance_advance_stage
  on public.erp_maintenance_orders;
create trigger erp_v731_auto_apply_maintenance_advance_stage
after update of workflow_stage on public.erp_maintenance_orders
for each row execute function public.erp_v731_auto_apply_maintenance_advance();

-- Restore the original accounting rule: deleting an operational document never
-- deletes the cash payment. The payment is detached and remains on the partner
-- account until it is deleted from the cashbox or allocated to a later invoice.
create or replace function public.erp_delete_cloud_sales_order_v3(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_normalized integer;
begin
  perform public.erp_v731_release_advance_allocations(
    p_company_id,'sales',p_order_id,null,'Sales order deleted'
  );
  v_result:=public.erp_delete_cloud_sales_order_v2(p_company_id,p_order_id);
  v_normalized:=public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','partner_balance_preserved',
    'paymentsRequiredDeleted',false,
    'paymentsPreserved',true,
    'normalizedAdvances',v_normalized,
    'futureAllocation','same_partner_same_currency'
  );
end;
$$;

create or replace function public.erp_delete_cloud_purchase_order_v3(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transfer record;
  v_result jsonb;
  v_normalized integer;
begin
  perform public.erp_v731_release_advance_allocations(
    p_company_id,'purchases',p_order_id,null,'Purchase order deleted'
  );

  for v_transfer in
    select distinct t.id
    from public.erp_car_warehouse_transfers as t
    where t.company_id=p_company_id
      and not t.is_deleted
      and coalesce(t.data->>'carId',t.data->>'car_id') in (
        select i.item_id
        from public.erp_purchase_order_items_cloud as i
        where i.company_id=p_company_id
          and i.order_id=p_order_id
          and i.item_type='car'
      )
    order by t.id
  loop
    perform public.erp_delete_car_warehouse_transfer(
      p_company_id,v_transfer.id,'Purchase order linked cleanup'
    );
  end loop;

  v_result:=public.erp_delete_cloud_purchase_order_v2(p_company_id,p_order_id);
  v_normalized:=public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','partner_balance_preserved',
    'paymentsRequiredDeleted',false,
    'paymentsPreserved',true,
    'normalizedAdvances',v_normalized,
    'futureAllocation','same_partner_same_currency',
    'orphanVehicleTransfersCleaned',true
  );
end;
$$;

create or replace function public.erp_delete_cloud_maintenance_order_v3(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_detached jsonb;
begin
  v_detached:=public.erp_v731_detach_maintenance_payments(
    p_company_id,p_order_id,coalesce(p_reason,'Maintenance order deleted')
  );
  v_result:=public.erp_delete_cloud_maintenance_order_v2(
    p_company_id,p_order_id,p_reason
  );
  perform public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','partner_balance_preserved',
    'paymentsRequiredDeleted',false,
    'paymentsPreserved',true,
    'detachment',v_detached,
    'futureAllocation','same_customer_same_currency'
  );
end;
$$;


create or replace function public.erp_cancel_cloud_sales_workflow_invoice(
  p_company_id uuid,
  p_invoice_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Cancel sales invoice and preserve payment');
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.cancel','sales.update','sales.delete']
  );
  select d.parent_id into v_order_id
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id and d.id=p_invoice_id
    and d.module='sales' and d.document_type='invoice' and not d.is_deleted
  for update;
  if not found then raise exception 'workflow_component_not_found'; end if;

  perform public.erp_v731_release_advance_allocations(
    p_company_id,'sales',v_order_id,p_invoice_id,v_reason
  );
  perform public.erp_detach_cloud_workflow_invoice_payments(
    p_company_id,p_invoice_id,v_reason
  );
  perform public.erp_v731_normalize_order_advances(p_company_id,v_order_id);
  perform public.erp_cancel_cloud_workflow_invoice(
    p_company_id,p_invoice_id,'sales',v_reason
  );
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_workflow_invoice(
  p_company_id uuid,
  p_invoice_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order_id uuid;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Cancel purchase invoice and preserve payment');
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.cancel','purchases.update','purchases.delete']
  );
  select d.parent_id into v_order_id
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id and d.id=p_invoice_id
    and d.module='purchases' and d.document_type='invoice' and not d.is_deleted
  for update;
  if not found then raise exception 'workflow_component_not_found'; end if;

  perform public.erp_v731_release_advance_allocations(
    p_company_id,'purchases',v_order_id,p_invoice_id,v_reason
  );
  perform public.erp_detach_cloud_workflow_invoice_payments(
    p_company_id,p_invoice_id,v_reason
  );
  perform public.erp_v731_normalize_order_advances(p_company_id,v_order_id);
  perform public.erp_cancel_cloud_workflow_invoice(
    p_company_id,p_invoice_id,'purchases',v_reason
  );
end;
$$;

create or replace function public.erp_manage_commercial_order_component(
  p_company_id uuid,
  p_module text,
  p_order_id uuid,
  p_component_type text,
  p_component_id uuid,
  p_action text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_status text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Component action from order details');
  v_detached jsonb;
  v_released numeric:=0;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  if p_component_type not in ('order','logistics','invoice','payment') then raise exception 'invalid_component_type'; end if;
  if p_action not in ('approve','delete') then raise exception 'invalid_component_action'; end if;

  if p_component_type='payment' then
    raise exception 'payment_is_cashbox_owned';
  end if;

  if p_component_type='order' then
    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
      else
        perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
      end if;
      return jsonb_build_object('ok',true,'componentType','order','action','approve','status','approved');
    end if;
    if p_module='sales' then return public.erp_delete_cloud_sales_order_v3(p_company_id,p_order_id); end if;
    return public.erp_delete_cloud_purchase_order_v3(p_company_id,p_order_id);
  end if;

  select d.* into v_doc
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id and d.id=p_component_id
    and d.parent_id=p_order_id and d.module=p_module and not d.is_deleted
  for update;
  if not found then raise exception 'workflow_component_not_found'; end if;

  if p_component_type='logistics' then
    if v_doc.document_type<>(case when p_module='sales' then 'delivery' else 'receipt' end) then
      raise exception 'workflow_component_type_mismatch';
    end if;
    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_phase2_approve_sales_delivery(p_company_id,p_component_id);
      else
        perform public.erp_phase2_approve_purchase_receipt(p_company_id,p_component_id);
      end if;
    else
      if p_module='sales' then
        perform public.erp_cancel_cloud_sales_delivery(p_company_id,p_component_id);
      else
        perform public.erp_cancel_cloud_purchase_receipt(p_company_id,p_component_id);
      end if;
      update public.erp_commercial_workflow_documents
      set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
          payload=payload||jsonb_build_object('deletedFromOrderDetails',true,'deleteReason',v_reason)
      where company_id=p_company_id and id=p_component_id;
    end if;
  elsif p_component_type='invoice' then
    if v_doc.document_type<>'invoice' then raise exception 'workflow_component_type_mismatch'; end if;
    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,p_component_id);
      else
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,p_component_id);
      end if;
    else
      v_released:=public.erp_v731_release_advance_allocations(
        p_company_id,p_module,p_order_id,p_component_id,v_reason
      );
      v_detached:=public.erp_detach_cloud_workflow_invoice_payments(
        p_company_id,p_component_id,v_reason
      );
      perform public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
      if p_module='sales' then
        perform public.erp_cancel_cloud_sales_workflow_invoice(p_company_id,p_component_id,v_reason);
      else
        perform public.erp_cancel_cloud_purchase_workflow_invoice(p_company_id,p_component_id,v_reason);
      end if;
      update public.erp_commercial_workflow_documents
      set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
          payload=payload||jsonb_build_object(
            'deletedFromOrderDetails',true,'deleteReason',v_reason,
            'paymentsPreserved',true,'releasedAdvanceAmount',v_released,
            'detachedPayments',coalesce(v_detached,'[]'::jsonb)
          )
      where company_id=p_company_id and id=p_component_id;
    end if;
  end if;

  v_status:=public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,p_order_id);
  return jsonb_build_object(
    'ok',true,'module',p_module,'orderId',p_order_id,
    'componentType',p_component_type,'componentId',p_component_id,
    'action',p_action,'orderStatus',v_status,'linksUpdated',true,
    'paymentsPreserved',p_component_type='invoice' and p_action='delete'
  );
end;
$$;

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
  v_journal record;
  v_detached jsonb;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.update','maintenance.delete']
  );
  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
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
    v_target_stage:='stock_issue_approved';
    for v_journal in
      select je.id
      from public.erp_journal_entries as je
      where je.company_id=p_company_id and not je.is_deleted
        and lower(coalesce(je.data->>'referenceType',je.data->>'reference_type',''))<>'partner_advance'
        and (
          coalesce(
            je.data->>'maintenanceOrderId',je.data->>'maintenance_order_id',
            je.data->>'orderId',je.data->>'order_id'
          )=p_order_id::text
          or (
            nullif(v_order.invoice_number,'') is not null
            and coalesce(
              je.data->>'invoiceNumber',je.data->>'invoice_number',
              je.data->>'referenceId',je.data->>'reference_id'
            )=v_order.invoice_number
          )
        )
    loop
      perform public.erp_v65_soft_delete_journal(p_company_id,v_journal.id,v_reason);
    end loop;
    update public.erp_maintenance_orders
    set invoice_number=null,paid_amount=0,workflow_stage=v_target_stage,
        status='in_progress',updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  elsif p_component_type='stock' then
    if v_order.workflow_stage in ('invoice_draft','invoice_approved','paid','closed') then
      raise exception 'delete_invoice_component_first';
    end if;
    perform public.erp_v66_reverse_maintenance_stock(p_company_id,p_order_id,v_reason);
    update public.erp_maintenance_orders
    set stock_issue_number=null,workflow_stage='order_approved',status='approved',updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  elsif p_component_type='order_approval' then
    if v_order.workflow_stage not in ('order_approved','order_draft') then
      raise exception 'delete_downstream_components_first';
    end if;
    update public.erp_maintenance_orders
    set workflow_stage='order_draft',status='draft',updated_at=now()
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

-- Cashbox deletion remains the only way to remove the payment itself. When an
-- advance that was allocated to later documents is deleted, every allocation is
-- reversed and the affected maintenance orders are recalculated.
create or replace function public.erp_v731_sync_deleted_advance_cash()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order record;
begin
  if not old.is_deleted and new.is_deleted then
    for v_order in
      select distinct a.target_order_id
      from public.erp_partner_advance_allocations as a
      where a.company_id=new.company_id
        and a.cash_transaction_id=new.id
        and a.target_module='maintenance'
        and not a.is_deleted
    loop
      update public.erp_partner_advance_allocations
      set is_deleted=true,deleted_at=coalesce(new.deleted_at,now()),
          deleted_by=coalesce(new.updated_by,auth.uid()),
          deletion_reason='Source cash payment deleted'
      where company_id=new.company_id and cash_transaction_id=new.id and not is_deleted;

      update public.erp_maintenance_payments
      set is_deleted=true,deleted_at=coalesce(new.deleted_at,now()),
          updated_at=now(),updated_by=coalesce(new.updated_by,auth.uid())
      where company_id=new.company_id
        and (cash_transaction_id=new.id or source_cash_transaction_id=new.id)
        and not is_deleted;

      update public.erp_maintenance_orders as o
      set paid_amount=coalesce((
            select sum(p.amount_in_order_currency)
            from public.erp_maintenance_payments as p
            where p.company_id=o.company_id
              and p.maintenance_order_id=o.id
              and not p.is_deleted
          ),0),
          workflow_stage=case
            when coalesce((
              select sum(p.amount_in_order_currency)
              from public.erp_maintenance_payments as p
              where p.company_id=o.company_id
                and p.maintenance_order_id=o.id
                and not p.is_deleted
            ),0)+0.001>=o.sale_price and o.sale_price>0 then 'paid'
            else 'invoice_approved'
          end,
          status=case
            when coalesce((
              select sum(p.amount_in_order_currency)
              from public.erp_maintenance_payments as p
              where p.company_id=o.company_id
                and p.maintenance_order_id=o.id
                and not p.is_deleted
            ),0)+0.001>=o.sale_price and o.sale_price>0 then 'completed'
            else 'approved'
          end,
          updated_at=now()
      where o.company_id=new.company_id and o.id=v_order.target_order_id and not o.is_deleted;
    end loop;

    update public.erp_partner_advance_allocations
    set is_deleted=true,deleted_at=coalesce(new.deleted_at,now()),
        deleted_by=coalesce(new.updated_by,auth.uid()),
        deletion_reason='Source cash payment deleted'
    where company_id=new.company_id and cash_transaction_id=new.id and not is_deleted;

    update public.erp_maintenance_payments
    set is_deleted=true,deleted_at=coalesce(new.deleted_at,now()),
        updated_at=now(),updated_by=coalesce(new.updated_by,auth.uid())
    where company_id=new.company_id
      and (cash_transaction_id=new.id or source_cash_transaction_id=new.id)
      and not is_deleted;
  end if;
  return new;
end;
$$;

drop trigger if exists erp_v731_sync_deleted_advance_cash
  on public.erp_cash_transactions;
create trigger erp_v731_sync_deleted_advance_cash
after update of is_deleted on public.erp_cash_transactions
for each row execute function public.erp_v731_sync_deleted_advance_cash();

create or replace function public.erp_list_partner_unapplied_payments(
  p_company_id uuid,
  p_party_type text,
  p_party_id text,
  p_currency text
) returns setof jsonb
language sql
stable
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'transaction_id',ct.id,
    'voucher_number',coalesce(ct.data->>'voucherNumber',ct.data->>'voucher_number',ct.id),
    'transaction_date',coalesce(ct.data->>'transactionDate',ct.data->>'transaction_date',ct.created_at::text),
    'amount',greatest(0,public.erp_v731_advance_original_amount(ct.data)-coalesce(a.allocated,0)),
    'original_amount',public.erp_v731_advance_original_amount(ct.data),
    'allocated_amount',coalesce(a.allocated,0),
    'currency',upper(coalesce(ct.data->>'accountCurrency',ct.data->>'invoiceCurrency',ct.data->>'currency','USD')),
    'type',lower(coalesce(ct.data->>'type','')),
    'notes',coalesce(ct.data->>'notes',''),
    'party_type',coalesce(ct.data->>'partyType',ct.data->>'party_type'),
    'party_id',coalesce(ct.data->>'partyId',ct.data->>'party_id'),
    'detached_from_order_id',coalesce(ct.data->>'detachedFromOrderId',ct.data->>'detached_from_order_id'),
    'detached_from_maintenance_order_id',coalesce(ct.data->>'detachedFromMaintenanceOrderId',ct.data->>'detached_from_maintenance_order_id'),
    'journal_entry_id',coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id')
  )
  from public.erp_cash_transactions as ct
  left join lateral (
    select coalesce(sum(x.amount),0) as allocated
    from public.erp_partner_advance_allocations as x
    where x.company_id=ct.company_id and x.cash_transaction_id=ct.id and not x.is_deleted
  ) as a on true
  where ct.company_id=p_company_id and not ct.is_deleted
    and public.erp_is_company_member(p_company_id)
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))=lower(btrim(p_party_type))
    and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
    and upper(coalesce(ct.data->>'accountCurrency',ct.data->>'invoiceCurrency',ct.data->>'currency','USD'))=upper(coalesce(p_currency,'USD'))
    and public.erp_v731_advance_original_amount(ct.data)-coalesce(a.allocated,0)>0.001
  order by coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) desc,ct.created_at desc;
$$;

-- Existing update logic remains valid only while the advance is not allocated.
create or replace function public.erp_update_partner_unapplied_payment(
  p_company_id uuid,
  p_transaction_id text,
  p_amount numeric,
  p_transaction_date timestamptz,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transaction public.erp_cash_transactions%rowtype;
  v_journal_id text;
  v_allocated numeric;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.update']);
  if coalesce(p_amount,0)<=0 then raise exception 'payment_amount_must_be_positive'; end if;
  if p_transaction_date is null then raise exception 'payment_date_required'; end if;

  select ct.* into v_transaction
  from public.erp_cash_transactions as ct
  where ct.company_id=p_company_id and ct.id=p_transaction_id and not ct.is_deleted
  for update;
  if not found then raise exception 'partner_advance_not_found'; end if;
  if lower(coalesce(v_transaction.data->>'referenceType',v_transaction.data->>'reference_type',''))<>'partner_advance' then
    raise exception 'transaction_is_not_unapplied_partner_payment';
  end if;

  v_allocated:=public.erp_v731_advance_allocated_amount(p_company_id,p_transaction_id);
  if v_allocated>0.001 then raise exception 'advance_has_active_allocations'; end if;

  v_journal_id:=coalesce(
    nullif(v_transaction.data->>'journalEntryId',''),
    nullif(v_transaction.data->>'journal_entry_id',''),
    nullif(v_transaction.data->>'entryId',''),
    nullif(v_transaction.data->>'entry_id','')
  );

  update public.erp_cash_transactions as ct
  set data=ct.data||jsonb_build_object(
        'amount',p_amount,'advanceAmount',p_amount,'allocatedAmount',0,
        'unappliedAmount',p_amount,'transactionDate',p_transaction_date,
        'notes',coalesce(p_notes,''),'updatedAt',v_now,
        'unapplied',true,'referenceType','partner_advance'
      ),updated_at=v_now,updated_by=auth.uid()
  where ct.company_id=p_company_id and ct.id=p_transaction_id and not ct.is_deleted;

  if v_journal_id is not null then
    update public.erp_journal_entries as je
    set data=je.data||jsonb_build_object(
          'entryDate',p_transaction_date,'totalDebit',p_amount,'totalCredit',p_amount,
          'description',coalesce(nullif(p_notes,''),je.data->>'description','Partner unapplied payment'),
          'updatedAt',v_now,'referenceType','partner_advance','advanceAmount',p_amount,
          'allocatedAmount',0,'unappliedAmount',p_amount,'unapplied',true
        ),updated_at=v_now,updated_by=auth.uid()
    where je.company_id=p_company_id and je.id=v_journal_id and not je.is_deleted;

    update public.erp_journal_lines as jl
    set data=jl.data||jsonb_build_object(
          'debit',case when public.erp_try_numeric(jl.data->>'debit',0)>0 then p_amount else 0 end,
          'credit',case when public.erp_try_numeric(jl.data->>'credit',0)>0 then p_amount else 0 end,
          'description',coalesce(p_notes,''),'referenceType','partner_advance',
          'unapplied',true,'updatedAt',v_now
        ),updated_at=v_now,updated_by=auth.uid()
    where jl.company_id=p_company_id and not jl.is_deleted
      and coalesce(jl.data->>'entryId',jl.data->>'entry_id')=v_journal_id;
  end if;

  return jsonb_build_object(
    'updated',true,'transactionId',p_transaction_id,'journalEntryId',v_journal_id,
    'amount',p_amount,'transactionDate',p_transaction_date
  );
end;
$$;


create or replace function public.erp_delete_cloud_accounting_entry(
  p_company_id uuid,
  p_entry_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_entry public.erp_journal_entries%rowtype;
  v_cash_id text;
  v_ref text;
  v_reference_id text;
  v_order_id text;
  v_reference_uuid uuid;
  v_order_uuid uuid;
  v_doc record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );

  select * into v_entry
  from public.erp_journal_entries
  where company_id=p_company_id and id=p_entry_id and not is_deleted
  for update;
  if not found then return; end if;

  select ct.id into v_cash_id
  from public.erp_cash_transactions as ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and coalesce(
      ct.data->>'journalEntryId',ct.data->>'journal_entry_id',
      ct.data->>'entryId',ct.data->>'entry_id'
    )=p_entry_id
  limit 1;
  if found then
    perform public.erp_delete_cloud_cash_transaction(p_company_id,v_cash_id);
    return;
  end if;

  v_ref:=lower(btrim(coalesce(
    nullif(v_entry.data->>'referenceType',''),
    nullif(v_entry.data->>'reference_type',''),'manual'
  )));
  v_reference_id:=coalesce(
    nullif(v_entry.data->>'referenceId',''),
    nullif(v_entry.data->>'reference_id',''),
    nullif(v_entry.data->>'maintenanceOrderId',''),
    nullif(v_entry.data->>'maintenance_order_id','')
  );
  v_order_id:=coalesce(
    nullif(v_entry.data->>'orderId',''),
    nullif(v_entry.data->>'order_id','')
  );

  if v_ref in ('manual','manual_journal','manual journal','قيد يدوي','') then
    perform public.erp_v65_soft_delete_journal(
      p_company_id,p_entry_id,'Delete manual accounting entry'
    );
    return;
  end if;
  if v_ref='expense' and v_reference_id is not null then
    perform public.erp_delete_cloud_expense(p_company_id,v_reference_id);
    return;
  end if;
  if v_ref in (
    'manual_cash_transaction','cash_transaction','cash receipt','cash payment',
    'receipt','payment','سند قبض','سند صرف','partner_advance'
  ) then
    if v_cash_id is not null then
      perform public.erp_delete_cloud_cash_transaction(p_company_id,v_cash_id);
    else
      perform public.erp_v65_soft_delete_journal(
        p_company_id,p_entry_id,'Delete orphaned cash or advance entry'
      );
    end if;
    return;
  end if;

  begin v_reference_uuid:=v_reference_id::uuid;
  exception when invalid_text_representation then v_reference_uuid:=null; end;
  begin v_order_uuid:=v_order_id::uuid;
  exception when invalid_text_representation then v_order_uuid:=null; end;

  if v_reference_uuid is not null then
    select d.module,d.parent_id,d.document_type into v_doc
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id and d.id=v_reference_uuid and not d.is_deleted
    limit 1;
    if found then
      perform public.erp_manage_commercial_order_component(
        p_company_id,v_doc.module,v_doc.parent_id,
        case when v_doc.document_type='invoice' then 'invoice' else 'logistics' end,
        v_reference_uuid,'delete','Delete from linked accounting entry'
      );
      return;
    end if;
  end if;

  if coalesce(v_order_uuid,v_reference_uuid) is not null
     and exists(select 1 from public.erp_sales_orders_cloud
       where company_id=p_company_id and id=coalesce(v_order_uuid,v_reference_uuid)
         and not is_deleted) then
    perform public.erp_delete_cloud_sales_order_v3(
      p_company_id,coalesce(v_order_uuid,v_reference_uuid)
    );
    return;
  end if;
  if coalesce(v_order_uuid,v_reference_uuid) is not null
     and exists(select 1 from public.erp_purchase_orders_cloud
       where company_id=p_company_id and id=coalesce(v_order_uuid,v_reference_uuid)
         and not is_deleted) then
    perform public.erp_delete_cloud_purchase_order_v3(
      p_company_id,coalesce(v_order_uuid,v_reference_uuid)
    );
    return;
  end if;
  if coalesce(v_order_uuid,v_reference_uuid) is not null
     and exists(select 1 from public.erp_maintenance_orders
       where company_id=p_company_id and id=coalesce(v_order_uuid,v_reference_uuid)
         and not is_deleted) then
    perform public.erp_delete_cloud_maintenance_order_v3(
      p_company_id,coalesce(v_order_uuid,v_reference_uuid),
      'Delete from linked accounting entry'
    );
    return;
  end if;

  perform public.erp_v65_soft_delete_journal(
    p_company_id,p_entry_id,'Delete orphaned accounting entry'
  );
end;
$$;

-- Backfill/normalize preserved payments and apply them to approved open invoices.
do $$
declare
  v_cash record;
  v_invoice record;
  v_order record;
begin
  for v_cash in
    select ct.id,ct.company_id
    from public.erp_cash_transactions as ct
    where not ct.is_deleted
      and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
  loop
    perform public.erp_v731_refresh_advance_cache(v_cash.company_id,v_cash.id);
  end loop;

  for v_invoice in
    select d.company_id,d.id
    from public.erp_commercial_workflow_documents as d
    where d.document_type='invoice' and d.status='approved' and not d.is_deleted
      and public.erp_try_numeric(d.payload->>'remainingAmount',0)>0.001
    order by d.created_at,d.id
  loop
    perform public.erp_v731_apply_advance_to_commercial_invoice(v_invoice.company_id,v_invoice.id);
  end loop;

  for v_order in
    select o.company_id,o.id
    from public.erp_maintenance_orders as o
    where not o.is_deleted and o.workflow_stage in ('invoice_approved','paid','closed')
      and o.sale_price-o.paid_amount>0.001
    order by o.created_at,o.id
  loop
    perform public.erp_v731_apply_advance_to_maintenance_order(v_order.company_id,v_order.id);
  end loop;
end;
$$;

revoke all on function public.erp_v731_advance_allocated_amount(uuid,text) from public,anon;
revoke all on function public.erp_v731_refresh_advance_cache(uuid,text) from public,anon;
revoke all on function public.erp_v731_normalize_order_advances(uuid,uuid) from public,anon;
revoke all on function public.erp_v731_release_advance_allocations(uuid,text,uuid,uuid,text) from public,anon;
revoke all on function public.erp_v731_apply_advance_to_commercial_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_v731_detach_maintenance_payments(uuid,uuid,text) from public,anon;
revoke all on function public.erp_v731_apply_advance_to_maintenance_order(uuid,uuid) from public,anon;

grant execute on function public.erp_v731_advance_allocated_amount(uuid,text) to authenticated,service_role;
grant execute on function public.erp_v731_refresh_advance_cache(uuid,text) to authenticated,service_role;
grant execute on function public.erp_v731_normalize_order_advances(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v731_release_advance_allocations(uuid,text,uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v731_apply_advance_to_commercial_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v731_detach_maintenance_payments(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_v731_apply_advance_to_maintenance_order(uuid,uuid) to authenticated,service_role;

commit;
