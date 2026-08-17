-- Quality Line ERP R86
-- Complete linked financial-operation deletion.
-- Forward-only repair: deleting a cash/journal/transfer leg removes only the
-- owning financial operation group and reconciles affected business documents.
begin;

create or replace function public.erp_r86_text_array_add(
  p_values text[],
  p_value text
) returns text[]
language sql
immutable
as $$
  select case
    when nullif(btrim(coalesce(p_value,'')),'') is null
      then coalesce(p_values,'{}'::text[])
    when p_value=any(coalesce(p_values,'{}'::text[]))
      then coalesce(p_values,'{}'::text[])
    else array_append(coalesce(p_values,'{}'::text[]),p_value)
  end
$$;

create or replace function public.erp_r86_payment_matches_financial_group(
  p_payment jsonb,
  p_cash_ids text[],
  p_journal_ids text[],
  p_transfer_ids text[],
  p_payment_ids text[],
  p_allocation_ids text[]
) returns boolean
language sql
immutable
as $$
  select
    coalesce(p_payment->>'paymentId',p_payment->>'payment_id','')
      =any(coalesce(p_payment_ids,'{}'::text[]))
    or coalesce(
      p_payment->>'cashTransactionId',p_payment->>'cash_transaction_id',''
    )=any(coalesce(p_cash_ids,'{}'::text[]))
    or coalesce(
      p_payment->>'journalEntryId',p_payment->>'journal_entry_id',''
    )=any(coalesce(p_journal_ids,'{}'::text[]))
    or coalesce(
      p_payment->>'cashJournalEntryId',p_payment->>'cash_journal_entry_id',''
    )=any(coalesce(p_journal_ids,'{}'::text[]))
    or coalesce(p_payment->>'transferId',p_payment->>'transfer_id','')
      =any(coalesce(p_transfer_ids,'{}'::text[]))
    or coalesce(
      p_payment->>'advanceAllocationId',p_payment->>'advance_allocation_id',''
    )=any(coalesce(p_allocation_ids,'{}'::text[]))
$$;

revoke all on function public.erp_r86_text_array_add(text[],text)
  from public,anon,authenticated;
revoke all on function public.erp_r86_payment_matches_financial_group(
  jsonb,text[],text[],text[],text[],text[]
) from public,anon,authenticated;

create or replace function public.erp_r86_delete_linked_financial_operation(
  p_company_id uuid,
  p_cash_transaction_id text default null,
  p_journal_entry_id text default null,
  p_transfer_id text default null
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_cash_ids text[]:='{}'::text[];
  v_journal_ids text[]:='{}'::text[];
  v_transfer_ids text[]:='{}'::text[];
  v_payment_ids text[]:='{}'::text[];
  v_allocation_ids text[]:='{}'::text[];
  v_document_ids text[]:='{}'::text[];
  v_maintenance_order_ids text[]:='{}'::text[];
  v_advance_source_cash_ids text[]:='{}'::text[];
  v_found boolean:=false;
  v_cash record;
  v_journal record;
  v_transfer record;
  v_doc record;
  v_payment jsonb;
  v_maintenance record;
  v_allocation record;
  v_reference_type text;
  v_reference_id text;
  v_journal_id text;
  v_new_payments jsonb;
  v_paid numeric;
  v_total numeric;
  v_now timestamptz:=clock_timestamp();
  v_id text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );

  v_cash_ids:=public.erp_r86_text_array_add(
    v_cash_ids,p_cash_transaction_id
  );
  v_journal_ids:=public.erp_r86_text_array_add(
    v_journal_ids,p_journal_entry_id
  );
  v_transfer_ids:=public.erp_r86_text_array_add(
    v_transfer_ids,p_transfer_id
  );

  -- Resolve journal -> cash/payment/transfer before consulting any business
  -- document owner. This prevents a payment-journal delete from cascading into
  -- invoice/order deletion.
  for v_cash in
    select ct.id,ct.data
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and coalesce(
        nullif(ct.data->>'journalEntryId',''),
        nullif(ct.data->>'journal_entry_id',''),
        nullif(ct.data->>'entryId',''),
        nullif(ct.data->>'entry_id','')
      )=any(v_journal_ids)
    for update
  loop
    v_found:=true;
    v_cash_ids:=public.erp_r86_text_array_add(v_cash_ids,v_cash.id);
  end loop;

  for v_journal in
    select je.id,je.data
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and not je.is_deleted
      and je.id=any(v_journal_ids)
    for update
  loop
    v_reference_type:=lower(btrim(coalesce(
      nullif(v_journal.data->>'referenceType',''),
      nullif(v_journal.data->>'reference_type',''),
      ''
    )));
    v_reference_id:=coalesce(
      nullif(v_journal.data->>'referenceId',''),
      nullif(v_journal.data->>'reference_id','')
    );
    if v_reference_type like 'cash_transfer%' then
      v_found:=true;
      v_transfer_ids:=public.erp_r86_text_array_add(
        v_transfer_ids,v_reference_id
      );
    elsif v_reference_type like '%payment%' then
      v_found:=true;
      v_payment_ids:=public.erp_r86_text_array_add(
        v_payment_ids,v_reference_id
      );
    end if;
  end loop;

  -- Inspect cash roots and collect their journal/payment/transfer identities.
  for v_cash in
    select ct.id,ct.data
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and ct.id=any(v_cash_ids)
    for update
  loop
    v_found:=true;
    v_journal_id:=coalesce(
      nullif(v_cash.data->>'journalEntryId',''),
      nullif(v_cash.data->>'journal_entry_id',''),
      nullif(v_cash.data->>'entryId',''),
      nullif(v_cash.data->>'entry_id','')
    );
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,v_journal_id
    );
    v_reference_type:=lower(btrim(coalesce(
      nullif(v_cash.data->>'referenceType',''),
      nullif(v_cash.data->>'reference_type',''),
      ''
    )));
    v_reference_id:=coalesce(
      nullif(v_cash.data->>'referenceId',''),
      nullif(v_cash.data->>'reference_id','')
    );
    if v_reference_type like 'cash_transfer%'
       or v_reference_type in (
         'cash transfer','تحويل نقدي','تحويل بين الصناديق'
       ) then
      v_transfer_ids:=public.erp_r86_text_array_add(
        v_transfer_ids,v_reference_id
      );
    elsif v_reference_type like '%payment%' then
      v_payment_ids:=public.erp_r86_text_array_add(
        v_payment_ids,v_reference_id
      );
    end if;
  end loop;

  -- Expand from commercial payment history. The payment JSON is the canonical
  -- link between the settlement leg and an optional FX transfer.
  for v_doc in
    select d.id,d.payload
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.module in ('sales','purchases')
      and d.document_type='invoice'
      and not d.is_deleted
      and exists(
        select 1
        from jsonb_array_elements(
          case when jsonb_typeof(d.payload->'payments')='array'
            then d.payload->'payments' else '[]'::jsonb end
        ) as e(value)
        where public.erp_r86_payment_matches_financial_group(
          e.value,v_cash_ids,v_journal_ids,v_transfer_ids,
          v_payment_ids,v_allocation_ids
        )
      )
    for update
  loop
    v_found:=true;
    v_document_ids:=public.erp_r86_text_array_add(
      v_document_ids,v_doc.id::text
    );
    for v_payment in
      select e.value
      from jsonb_array_elements(
        case when jsonb_typeof(v_doc.payload->'payments')='array'
          then v_doc.payload->'payments' else '[]'::jsonb end
      ) as e(value)
      where public.erp_r86_payment_matches_financial_group(
        e.value,v_cash_ids,v_journal_ids,v_transfer_ids,
        v_payment_ids,v_allocation_ids
      )
    loop
      v_payment_ids:=public.erp_r86_text_array_add(
        v_payment_ids,coalesce(
          v_payment->>'paymentId',v_payment->>'payment_id'
        )
      );
      v_cash_ids:=public.erp_r86_text_array_add(
        v_cash_ids,coalesce(
          v_payment->>'cashTransactionId',
          v_payment->>'cash_transaction_id'
        )
      );
      v_journal_ids:=public.erp_r86_text_array_add(
        v_journal_ids,coalesce(
          v_payment->>'journalEntryId',
          v_payment->>'journal_entry_id'
        )
      );
      v_journal_ids:=public.erp_r86_text_array_add(
        v_journal_ids,coalesce(
          v_payment->>'cashJournalEntryId',
          v_payment->>'cash_journal_entry_id'
        )
      );
      v_transfer_ids:=public.erp_r86_text_array_add(
        v_transfer_ids,coalesce(
          v_payment->>'transferId',v_payment->>'transfer_id'
        )
      );
      v_allocation_ids:=public.erp_r86_text_array_add(
        v_allocation_ids,coalesce(
          v_payment->>'advanceAllocationId',
          v_payment->>'advance_allocation_id'
        )
      );
    end loop;
  end loop;

  -- Expand from maintenance payment rows and their V7.5.x payment payload.
  for v_maintenance in
    select mp.id::text as id,
           mp.maintenance_order_id::text as order_id,
           mp.cash_transaction_id,mp.journal_entry_id,
           mp.source_cash_transaction_id,
           mp.advance_allocation_id::text as advance_allocation_id,
           mp.payment_payload
    from public.erp_maintenance_payments as mp
    where mp.company_id=p_company_id
      and not mp.is_deleted
      and (
        mp.id::text=any(v_payment_ids)
        or coalesce(mp.cash_transaction_id,'')=any(v_cash_ids)
        or coalesce(mp.source_cash_transaction_id,'')=any(v_cash_ids)
        or coalesce(mp.journal_entry_id,'')=any(v_journal_ids)
        or coalesce(mp.advance_allocation_id::text,'')=any(v_allocation_ids)
        or public.erp_r86_payment_matches_financial_group(
          coalesce(mp.payment_payload,'{}'::jsonb),
          v_cash_ids,v_journal_ids,v_transfer_ids,
          v_payment_ids,v_allocation_ids
        )
      )
    for update
  loop
    v_found:=true;
    v_payment_ids:=public.erp_r86_text_array_add(
      v_payment_ids,v_maintenance.id
    );
    v_maintenance_order_ids:=public.erp_r86_text_array_add(
      v_maintenance_order_ids,v_maintenance.order_id
    );
    v_cash_ids:=public.erp_r86_text_array_add(
      v_cash_ids,v_maintenance.cash_transaction_id
    );
    v_cash_ids:=public.erp_r86_text_array_add(
      v_cash_ids,v_maintenance.source_cash_transaction_id
    );
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,v_maintenance.journal_entry_id
    );
    v_allocation_ids:=public.erp_r86_text_array_add(
      v_allocation_ids,v_maintenance.advance_allocation_id
    );
    v_payment_ids:=public.erp_r86_text_array_add(
      v_payment_ids,coalesce(
        v_maintenance.payment_payload->>'paymentId',
        v_maintenance.payment_payload->>'payment_id'
      )
    );
    v_cash_ids:=public.erp_r86_text_array_add(
      v_cash_ids,coalesce(
        v_maintenance.payment_payload->>'cashTransactionId',
        v_maintenance.payment_payload->>'cash_transaction_id'
      )
    );
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,coalesce(
        v_maintenance.payment_payload->>'journalEntryId',
        v_maintenance.payment_payload->>'journal_entry_id'
      )
    );
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,coalesce(
        v_maintenance.payment_payload->>'cashJournalEntryId',
        v_maintenance.payment_payload->>'cash_journal_entry_id'
      )
    );
    v_transfer_ids:=public.erp_r86_text_array_add(
      v_transfer_ids,coalesce(
        v_maintenance.payment_payload->>'transferId',
        v_maintenance.payment_payload->>'transfer_id'
      )
    );
  end loop;

  -- A transfer id owns both cash legs and all source/target currency journals.
  for v_transfer in
    select t.id,t.data
    from public.erp_cash_transfers as t
    where t.company_id=p_company_id
      and not t.is_deleted
      and t.id=any(v_transfer_ids)
    for update
  loop
    v_found:=true;
  end loop;

  for v_cash in
    select ct.id,ct.data
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and coalesce(
        ct.data->>'referenceId',ct.data->>'reference_id',''
      )=any(v_transfer_ids)
      and (
        lower(coalesce(
          ct.data->>'referenceType',ct.data->>'reference_type',''
        )) like 'cash_transfer%'
        or lower(coalesce(
          ct.data->>'category',''
        ))='cash_transfer'
      )
    for update
  loop
    v_found:=true;
    v_cash_ids:=public.erp_r86_text_array_add(v_cash_ids,v_cash.id);
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,coalesce(
        v_cash.data->>'journalEntryId',
        v_cash.data->>'journal_entry_id',
        v_cash.data->>'entryId',
        v_cash.data->>'entry_id'
      )
    );
  end loop;

  for v_journal in
    select je.id,je.data
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and not je.is_deleted
      and coalesce(
        je.data->>'referenceId',je.data->>'reference_id',''
      )=any(v_transfer_ids)
      and lower(coalesce(
        je.data->>'referenceType',je.data->>'reference_type',''
      )) like 'cash_transfer%'
    for update
  loop
    v_found:=true;
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,v_journal.id
    );
  end loop;

  -- Reinspect newly collected cash rows (notably settlement + FX legs).
  for v_cash in
    select ct.id,ct.data
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and ct.id=any(v_cash_ids)
    for update
  loop
    v_found:=true;
    v_journal_ids:=public.erp_r86_text_array_add(
      v_journal_ids,coalesce(
        v_cash.data->>'journalEntryId',
        v_cash.data->>'journal_entry_id',
        v_cash.data->>'entryId',
        v_cash.data->>'entry_id'
      )
    );
    v_reference_type:=lower(coalesce(
      v_cash.data->>'referenceType',v_cash.data->>'reference_type',''
    ));
    v_reference_id:=coalesce(
      v_cash.data->>'referenceId',v_cash.data->>'reference_id'
    );
    if v_reference_type like 'cash_transfer%' then
      v_transfer_ids:=public.erp_r86_text_array_add(
        v_transfer_ids,v_reference_id
      );
    elsif v_reference_type like '%payment%' then
      v_payment_ids:=public.erp_r86_text_array_add(
        v_payment_ids,v_reference_id
      );
    end if;
  end loop;

  -- One final payment-history expansion closes transfer -> payment -> settlement
  -- and journal -> payment -> FX counterpart paths.
  for v_doc in
    select d.id,d.payload
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.module in ('sales','purchases')
      and d.document_type='invoice'
      and not d.is_deleted
      and exists(
        select 1
        from jsonb_array_elements(
          case when jsonb_typeof(d.payload->'payments')='array'
            then d.payload->'payments' else '[]'::jsonb end
        ) as e(value)
        where public.erp_r86_payment_matches_financial_group(
          e.value,v_cash_ids,v_journal_ids,v_transfer_ids,
          v_payment_ids,v_allocation_ids
        )
      )
    for update
  loop
    v_found:=true;
    v_document_ids:=public.erp_r86_text_array_add(
      v_document_ids,v_doc.id::text
    );
    for v_payment in
      select e.value
      from jsonb_array_elements(
        case when jsonb_typeof(v_doc.payload->'payments')='array'
          then v_doc.payload->'payments' else '[]'::jsonb end
      ) as e(value)
      where public.erp_r86_payment_matches_financial_group(
        e.value,v_cash_ids,v_journal_ids,v_transfer_ids,
        v_payment_ids,v_allocation_ids
      )
    loop
      v_payment_ids:=public.erp_r86_text_array_add(
        v_payment_ids,coalesce(
          v_payment->>'paymentId',v_payment->>'payment_id'
        )
      );
      v_cash_ids:=public.erp_r86_text_array_add(
        v_cash_ids,coalesce(
          v_payment->>'cashTransactionId',
          v_payment->>'cash_transaction_id'
        )
      );
      v_journal_ids:=public.erp_r86_text_array_add(
        v_journal_ids,coalesce(
          v_payment->>'journalEntryId',
          v_payment->>'journal_entry_id'
        )
      );
      v_journal_ids:=public.erp_r86_text_array_add(
        v_journal_ids,coalesce(
          v_payment->>'cashJournalEntryId',
          v_payment->>'cash_journal_entry_id'
        )
      );
      v_transfer_ids:=public.erp_r86_text_array_add(
        v_transfer_ids,coalesce(
          v_payment->>'transferId',v_payment->>'transfer_id'
        )
      );
      v_allocation_ids:=public.erp_r86_text_array_add(
        v_allocation_ids,coalesce(
          v_payment->>'advanceAllocationId',
          v_payment->>'advance_allocation_id'
        )
      );
    end loop;
  end loop;

  -- Partner-advance applications are children of the source cash operation.
  for v_allocation in
    select a.id::text as id,a.cash_transaction_id,a.journal_entry_id,
           a.target_invoice_id::text as target_invoice_id,
           a.target_order_id::text as target_order_id
    from public.erp_partner_advance_allocations as a
    where a.company_id=p_company_id
      and not a.is_deleted
      and (
        a.id::text=any(v_allocation_ids)
        or a.cash_transaction_id=any(v_cash_ids)
        or coalesce(a.journal_entry_id,'')=any(v_journal_ids)
      )
    for update
  loop
    v_found:=true;
    v_allocation_ids:=public.erp_r86_text_array_add(
      v_allocation_ids,v_allocation.id
    );
    v_advance_source_cash_ids:=public.erp_r86_text_array_add(
      v_advance_source_cash_ids,v_allocation.cash_transaction_id
    );
    v_document_ids:=public.erp_r86_text_array_add(
      v_document_ids,v_allocation.target_invoice_id
    );
  end loop;

  if not v_found then
    return false;
  end if;

  -- Remove only payment objects belonging to this financial group and
  -- recompute invoice payment totals. Business invoices are never deleted.
  for v_doc in
    select d.id,d.payload
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.module in ('sales','purchases')
      and d.document_type='invoice'
      and not d.is_deleted
      and (
        d.id::text=any(v_document_ids)
        or exists(
          select 1
          from jsonb_array_elements(
            case when jsonb_typeof(d.payload->'payments')='array'
              then d.payload->'payments' else '[]'::jsonb end
          ) as e(value)
          where public.erp_r86_payment_matches_financial_group(
            e.value,v_cash_ids,v_journal_ids,v_transfer_ids,
            v_payment_ids,v_allocation_ids
          )
        )
      )
    for update
  loop
    select coalesce(jsonb_agg(e.value order by e.ordinality),'[]'::jsonb)
      into v_new_payments
    from jsonb_array_elements(
      case when jsonb_typeof(v_doc.payload->'payments')='array'
        then v_doc.payload->'payments' else '[]'::jsonb end
    ) with ordinality as e(value,ordinality)
    where not public.erp_r86_payment_matches_financial_group(
      e.value,v_cash_ids,v_journal_ids,v_transfer_ids,
      v_payment_ids,v_allocation_ids
    );

    select coalesce(sum(public.erp_try_numeric(coalesce(
      e.value->>'amountInInvoiceCurrency',
      e.value->>'amount_in_invoice_currency',
      e.value->>'invoiceAmount',
      e.value->>'invoice_amount',
      e.value->>'appliedInvoiceAmount',
      e.value->>'applied_invoice_amount',
      e.value->>'amount'
    ),0)),0)
      into v_paid
    from jsonb_array_elements(v_new_payments) as e(value);

    v_total:=public.erp_try_numeric(coalesce(
      v_doc.payload->>'totalAmount',
      v_doc.payload->>'total',
      v_doc.payload->>'invoiceAmount'
    ),0);

    update public.erp_commercial_workflow_documents as d
    set payload=d.payload||jsonb_build_object(
          'payments',v_new_payments,
          'paidAmount',least(greatest(v_paid,0),greatest(v_total,0)),
          'remainingAmount',greatest(v_total-v_paid,0),
          'paymentStatus',case
            when v_paid<=0.001 then 'unpaid'
            when v_total>0 and v_paid+0.001>=v_total then 'paid'
            else 'partial'
          end,
          'paymentUpdatedAt',v_now,
          'linkedFinancialDeletionVersion','r86'
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where d.company_id=p_company_id and d.id=v_doc.id;
  end loop;

  -- Soft-delete only the matching maintenance payment rows/applications.
  for v_maintenance in
    select mp.id::text as id,mp.maintenance_order_id::text as order_id
    from public.erp_maintenance_payments as mp
    where mp.company_id=p_company_id
      and not mp.is_deleted
      and (
        mp.id::text=any(v_payment_ids)
        or coalesce(mp.cash_transaction_id,'')=any(v_cash_ids)
        or coalesce(mp.source_cash_transaction_id,'')=any(v_cash_ids)
        or coalesce(mp.journal_entry_id,'')=any(v_journal_ids)
        or coalesce(mp.advance_allocation_id::text,'')=any(v_allocation_ids)
        or public.erp_r86_payment_matches_financial_group(
          coalesce(mp.payment_payload,'{}'::jsonb),
          v_cash_ids,v_journal_ids,v_transfer_ids,
          v_payment_ids,v_allocation_ids
        )
      )
    for update
  loop
    v_maintenance_order_ids:=public.erp_r86_text_array_add(
      v_maintenance_order_ids,v_maintenance.order_id
    );
    update public.erp_maintenance_payments as mp
    set is_deleted=true,
        deleted_at=v_now,
        updated_at=v_now,
        updated_by=auth.uid()
    where mp.company_id=p_company_id
      and mp.id::text=v_maintenance.id
      and not mp.is_deleted;
  end loop;

  update public.erp_partner_advance_allocations as a
  set is_deleted=true,
      deleted_at=v_now,
      deleted_by=auth.uid(),
      deletion_reason='R86 linked financial operation deleted'
  where a.company_id=p_company_id
    and not a.is_deleted
    and a.id::text=any(v_allocation_ids);

  -- Maintenance paid state is authoritative from the surviving payment rows.
  foreach v_id in array v_maintenance_order_ids
  loop
    select coalesce(sum(coalesce(
      mp.amount_in_order_currency,mp.amount,0
    )),0)
      into v_paid
    from public.erp_maintenance_payments as mp
    where mp.company_id=p_company_id
      and mp.maintenance_order_id::text=v_id
      and not mp.is_deleted;

    select coalesce(o.sale_price,0)
      into v_total
    from public.erp_maintenance_orders as o
    where o.company_id=p_company_id
      and o.id::text=v_id
      and not o.is_deleted
    for update;

    if found then
      v_paid:=least(greatest(v_paid,0),greatest(v_total,0));
      update public.erp_maintenance_orders as o
      set paid_amount=v_paid,
          workflow_stage=case
            when v_total>0 and v_paid+0.001>=v_total
              then 'paid'
            else 'invoice_approved'
          end,
          status=case
            when v_total>0 and v_paid+0.001>=v_total
              then 'completed'
            else 'approved'
          end,
          updated_at=v_now,
          updated_by=auth.uid()
      where o.company_id=p_company_id and o.id::text=v_id;
    end if;
  end loop;

  -- Refresh a preserved advance only when an allocation was deleted but its
  -- source cash operation itself remains active.
  foreach v_id in array v_advance_source_cash_ids
  loop
    if not (v_id=any(v_cash_ids))
       and exists(
         select 1 from public.erp_cash_transactions as ct
         where ct.company_id=p_company_id
           and ct.id=v_id and not ct.is_deleted
       ) then
      perform public.erp_v731_refresh_advance_cache(p_company_id,v_id);
    end if;
  end loop;

  -- Delete all cash-transfer legs as one group.
  update public.erp_cash_transfers as t
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=t.data||jsonb_build_object(
        'deleteReason','R86 linked financial operation deleted',
        'deletedAt',v_now
      )
  where t.company_id=p_company_id
    and not t.is_deleted
    and t.id=any(v_transfer_ids);

  update public.erp_cash_transactions as ct
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=ct.data||jsonb_build_object(
        'deleteReason','R86 linked financial operation deleted',
        'deletedAt',v_now,
        'linkedFinancialDeletionVersion','r86'
      )
  where ct.company_id=p_company_id
    and not ct.is_deleted
    and ct.id=any(v_cash_ids);

  foreach v_id in array v_journal_ids
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_id,'R86 linked financial operation deleted'
    );
  end loop;

  return true;
end;
$$;

revoke all on function public.erp_r86_delete_linked_financial_operation(
  uuid,text,text,text
) from public,anon,authenticated;

-- Preserve the previous implementations as private fallbacks so non-financial
-- accounting-entry deletion keeps its historical owner-routing behavior.
do $r86$
begin
  if to_regprocedure(
       'public.erp_delete_cloud_cash_transaction(uuid,text)'
     ) is not null
     and to_regprocedure(
       'public.erp_delete_cloud_cash_transaction_pre_r86(uuid,text)'
     ) is null then
    alter function public.erp_delete_cloud_cash_transaction(uuid,text)
      rename to erp_delete_cloud_cash_transaction_pre_r86;
  end if;

  if to_regprocedure(
       'public.erp_delete_cloud_cash_transfer(uuid,text)'
     ) is not null
     and to_regprocedure(
       'public.erp_delete_cloud_cash_transfer_pre_r86(uuid,text)'
     ) is null then
    alter function public.erp_delete_cloud_cash_transfer(uuid,text)
      rename to erp_delete_cloud_cash_transfer_pre_r86;
  end if;

  if to_regprocedure(
       'public.erp_delete_cloud_accounting_entry(uuid,text)'
     ) is not null
     and to_regprocedure(
       'public.erp_delete_cloud_accounting_entry_pre_r86(uuid,text)'
     ) is null then
    alter function public.erp_delete_cloud_accounting_entry(uuid,text)
      rename to erp_delete_cloud_accounting_entry_pre_r86;
  end if;
end
$r86$;

revoke all on function public.erp_delete_cloud_cash_transaction_pre_r86(
  uuid,text
) from public,anon,authenticated,service_role;
revoke all on function public.erp_delete_cloud_cash_transfer_pre_r86(
  uuid,text
) from public,anon,authenticated,service_role;
revoke all on function public.erp_delete_cloud_accounting_entry_pre_r86(
  uuid,text
) from public,anon,authenticated,service_role;

create or replace function public.erp_delete_cloud_cash_transaction(
  p_company_id uuid,
  p_transaction_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  if public.erp_r86_delete_linked_financial_operation(
       p_company_id,p_transaction_id,null,null
     ) then
    return;
  end if;
  perform public.erp_delete_cloud_cash_transaction_pre_r86(
    p_company_id,p_transaction_id
  );
end;
$$;

create or replace function public.erp_delete_cloud_cash_transfer(
  p_company_id uuid,
  p_transfer_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  if public.erp_r86_delete_linked_financial_operation(
       p_company_id,null,null,p_transfer_id
     ) then
    return;
  end if;
  perform public.erp_delete_cloud_cash_transfer_pre_r86(
    p_company_id,p_transfer_id
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
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  if public.erp_r86_delete_linked_financial_operation(
       p_company_id,null,p_entry_id,null
     ) then
    return;
  end if;
  perform public.erp_delete_cloud_accounting_entry_pre_r86(
    p_company_id,p_entry_id
  );
end;
$$;

revoke all on function public.erp_delete_cloud_cash_transaction(uuid,text)
  from public,anon;
revoke all on function public.erp_delete_cloud_cash_transfer(uuid,text)
  from public,anon;
revoke all on function public.erp_delete_cloud_accounting_entry(uuid,text)
  from public,anon;

grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_delete_cloud_accounting_entry(uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
