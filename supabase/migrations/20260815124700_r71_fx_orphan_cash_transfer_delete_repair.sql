begin;

-- R71: FX cash-transfer deletion closure for historical/partial rows.
--
-- Older cross-currency maintenance payments create a linked cashbox transfer.
-- Historical delete paths could leave the transfer header deleted while one or
-- both cash transactions remained active. The previous canonical delete RPC
-- returned immediately when the active transfer header was missing, so clicking
-- Delete on the remaining cashbox row became a no-op. FX source/target journals
-- also use cash_transfer_source / cash_transfer_target reference types and must
-- be included in orphan cleanup.

create or replace function public.erp_r71_delete_cash_transfer_core(
  p_company_id uuid,
  p_transfer_id text,
  p_reason text default null
) returns jsonb
language plpgsql
security invoker
set search_path=public
as $$
declare
  v_transfer public.erp_cash_transfers%rowtype;
  v_header_found boolean:=false;
  v_header_was_deleted boolean:=false;
  v_source_transaction_id text;
  v_target_transaction_id text;
  v_source_journal_id text;
  v_target_journal_id text;
  v_transaction record;
  v_journal record;
  v_now timestamptz:=now();
  v_reason text:=coalesce(
    nullif(btrim(coalesce(p_reason,'')),''),
    'حذف تحويل الصناديق'
  );
  v_deleted_transactions integer:=0;
  v_deleted_journals integer:=0;
begin
  if nullif(btrim(coalesce(p_transfer_id,'')),'') is null then
    raise exception 'مرجع التحويل مطلوب';
  end if;

  -- Lock the header when it exists, including already-deleted historical rows.
  -- Missing/deleted headers must never turn child deletion into a no-op.
  select t.* into v_transfer
  from public.erp_cash_transfers as t
  where t.company_id=p_company_id
    and t.id=p_transfer_id
  for update;

  v_header_found:=found;
  if v_header_found then
    v_header_was_deleted:=coalesce(v_transfer.is_deleted,false);
    v_source_transaction_id:=nullif(btrim(coalesce(
      v_transfer.data->>'sourceTransactionId',
      v_transfer.data->>'source_transaction_id',
      ''
    )), '');
    v_target_transaction_id:=nullif(btrim(coalesce(
      v_transfer.data->>'targetTransactionId',
      v_transfer.data->>'target_transaction_id',
      ''
    )), '');
    v_source_journal_id:=nullif(btrim(coalesce(
      v_transfer.data->>'sourceJournalId',
      v_transfer.data->>'source_journal_id',
      ''
    )), '');
    v_target_journal_id:=nullif(btrim(coalesce(
      v_transfer.data->>'targetJournalId',
      v_transfer.data->>'target_journal_id',
      ''
    )), '');
  end if;

  -- Delete both transfer cash legs. Current rows use referenceType=cash_transfer;
  -- historical rows may identify the transfer by category or explicit header ids.
  for v_transaction in
    select
      ct.id,
      coalesce(
        nullif(ct.data->>'journalEntryId',''),
        nullif(ct.data->>'journal_entry_id',''),
        nullif(ct.data->>'entryId',''),
        nullif(ct.data->>'entry_id','')
      ) as journal_id
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and (
        ct.id in (
          coalesce(v_source_transaction_id,'__r71_no_source__'),
          coalesce(v_target_transaction_id,'__r71_no_target__')
        )
        or (
          coalesce(ct.data->>'referenceId',ct.data->>'reference_id')=p_transfer_id
          and (
            lower(replace(btrim(coalesce(
              ct.data->>'referenceType',ct.data->>'reference_type',''
            )),' ','_')) like 'cash_transfer%'
            or lower(replace(btrim(coalesce(ct.data->>'category','')),' ','_'))='cash_transfer'
            or lower(btrim(coalesce(
              ct.data->>'referenceType',ct.data->>'reference_type',''
            ))) in ('تحويل نقدي','تحويل بين الصناديق')
          )
        )
      )
    order by ct.created_at,ct.id
    for update
  loop
    if nullif(btrim(coalesce(v_transaction.journal_id,'')),'') is not null then
      if exists(
        select 1 from public.erp_journal_entries as je
        where je.company_id=p_company_id
          and je.id=v_transaction.journal_id
          and not je.is_deleted
      ) then
        v_deleted_journals:=v_deleted_journals+1;
      end if;
      perform public.erp_v65_soft_delete_journal(
        p_company_id,v_transaction.journal_id,v_reason
      );
    end if;

    update public.erp_cash_transactions as ct
    set is_deleted=true,
        deleted_at=coalesce(ct.deleted_at,v_now),
        updated_at=v_now,
        updated_by=auth.uid(),
        data=ct.data||jsonb_build_object(
          'deleteReason',v_reason,
          'deletedAt',v_now,
          'r71CashTransferDelete',true,
          'r71RecoveredMissingOrDeletedTransferHeader',
            (not v_header_found or v_header_was_deleted)
        )
    where ct.company_id=p_company_id
      and ct.id=v_transaction.id
      and not ct.is_deleted;
    if found then
      v_deleted_transactions:=v_deleted_transactions+1;
    end if;
  end loop;

  -- Clean journal rows even when their cash-transaction row was already missing.
  -- Cross-currency transfer journals are cash_transfer_source/target, so match
  -- the entire canonical cash_transfer* family instead of only cash_transfer.
  for v_journal in
    select je.id
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and not je.is_deleted
      and (
        je.id in (
          coalesce(v_source_journal_id,'__r71_no_source_journal__'),
          coalesce(v_target_journal_id,'__r71_no_target_journal__')
        )
        or (
          coalesce(je.data->>'referenceId',je.data->>'reference_id')=p_transfer_id
          and (
            lower(replace(btrim(coalesce(
              je.data->>'referenceType',je.data->>'reference_type',''
            )),' ','_')) like 'cash_transfer%'
            or lower(btrim(coalesce(
              je.data->>'referenceType',je.data->>'reference_type',''
            ))) in ('تحويل نقدي','تحويل بين الصناديق')
          )
        )
      )
    order by je.created_at,je.id
    for update
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_journal.id,v_reason
    );
    v_deleted_journals:=v_deleted_journals+1;
  end loop;

  if v_header_found then
    update public.erp_cash_transfers as t
    set is_deleted=true,
        deleted_at=coalesce(t.deleted_at,v_now),
        updated_at=v_now,
        updated_by=auth.uid(),
        data=t.data||jsonb_build_object(
          'deleteReason',v_reason,
          'deletedAt',coalesce(t.deleted_at,v_now),
          'r71ChildCleanupAt',v_now,
          'r71ChildCleanupRecovered',v_header_was_deleted
        )
    where t.company_id=p_company_id
      and t.id=p_transfer_id;
  end if;

  return jsonb_build_object(
    'transferId',p_transfer_id,
    'headerFound',v_header_found,
    'headerWasDeleted',v_header_was_deleted,
    'deletedTransactions',v_deleted_transactions,
    'deletedJournals',v_deleted_journals,
    'deleted',true
  );
end;
$$;

revoke all on function public.erp_r71_delete_cash_transfer_core(uuid,text,text)
  from public,anon,authenticated;

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
  perform public.erp_r71_delete_cash_transfer_core(
    p_company_id,p_transfer_id,'حذف تحويل الصناديق'
  );
end;
$$;

revoke all on function public.erp_delete_cloud_cash_transfer(uuid,text)
  from public,anon;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text)
  to authenticated,service_role;

create or replace function public.erp_delete_cloud_cash_transaction(
  p_company_id uuid,
  p_transaction_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transaction public.erp_cash_transactions%rowtype;
  v_journal_id text;
  v_reference_type text;
  v_reference_id text;
  v_category text;
  v_journal_reference_type text;
  v_journal_reference_id text;
  v_transfer_id text;
  v_is_transfer boolean:=false;
  v_now timestamptz:=now();
  v_doc record;
  v_new_payments jsonb;
  v_paid numeric;
  v_total numeric;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );

  select * into v_transaction
  from public.erp_cash_transactions
  where company_id=p_company_id
    and id=p_transaction_id
    and not is_deleted
  for update;
  if not found then return; end if;

  v_journal_id:=coalesce(
    nullif(v_transaction.data->>'journalEntryId',''),
    nullif(v_transaction.data->>'journal_entry_id',''),
    nullif(v_transaction.data->>'entryId',''),
    nullif(v_transaction.data->>'entry_id','')
  );
  v_reference_type:=lower(btrim(coalesce(
    nullif(v_transaction.data->>'referenceType',''),
    nullif(v_transaction.data->>'reference_type',''),
    'manual_cash_transaction'
  )));
  v_reference_id:=coalesce(
    nullif(v_transaction.data->>'referenceId',''),
    nullif(v_transaction.data->>'reference_id','')
  );
  v_category:=lower(replace(btrim(coalesce(
    v_transaction.data->>'category',''
  )),' ','_'));

  -- Historical FX rows can lose/drift their cash reference aliases while the
  -- journal still carries the canonical transfer id. Recover it before routing.
  if v_journal_id is not null then
    select
      lower(btrim(coalesce(
        je.data->>'referenceType',je.data->>'reference_type',''
      ))),
      coalesce(je.data->>'referenceId',je.data->>'reference_id')
    into v_journal_reference_type,v_journal_reference_id
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and je.id=v_journal_id
    limit 1;
  end if;

  v_is_transfer:=
    lower(replace(v_reference_type,' ','_')) like 'cash_transfer%'
    or v_reference_type in ('تحويل نقدي','تحويل بين الصناديق')
    or v_category='cash_transfer'
    or lower(replace(coalesce(v_journal_reference_type,''),' ','_')) like 'cash_transfer%'
    or coalesce(v_journal_reference_type,'') in ('تحويل نقدي','تحويل بين الصناديق');

  if v_is_transfer then
    v_transfer_id:=coalesce(v_reference_id,v_journal_reference_id);
    if nullif(btrim(coalesce(v_transfer_id,'')),'') is not null then
      perform public.erp_delete_cloud_cash_transfer(
        p_company_id,v_transfer_id
      );
      if not exists(
        select 1 from public.erp_cash_transactions as ct
        where ct.company_id=p_company_id
          and ct.id=p_transaction_id
          and not ct.is_deleted
      ) then
        return;
      end if;
    end if;

    -- Last-resort orphan recovery: the row is unmistakably a transfer leg but
    -- has no recoverable transfer id. Delete only this leg and its exact journal
    -- rather than silently succeeding while leaving the cashbox balance wrong.
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_journal_id,'حذف حركة تحويل صندوق يتيمة'
    );
    update public.erp_cash_transactions as ct
    set is_deleted=true,
        deleted_at=v_now,
        updated_at=v_now,
        updated_by=auth.uid(),
        data=ct.data||jsonb_build_object(
          'deleteReason','حذف حركة تحويل صندوق يتيمة',
          'deletedAt',v_now,
          'r71OrphanTransferLegDelete',true
        )
    where ct.company_id=p_company_id
      and ct.id=p_transaction_id
      and not ct.is_deleted;
    return;
  end if;

  -- Existing non-transfer behavior: remove this payment from any active
  -- commercial invoice and recalculate its paid/remaining status.
  for v_doc in
    select id,payload
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and not d.is_deleted
      and d.document_type='invoice'
      and (
        d.id::text=v_reference_id
        or exists(
          select 1
          from jsonb_array_elements(
            coalesce(d.payload->'payments','[]'::jsonb)
          ) as p
          where coalesce(
            p->>'cashTransactionId',p->>'cash_transaction_id'
          )=p_transaction_id
             or (
               v_journal_id is not null
               and coalesce(
                 p->>'journalEntryId',p->>'journal_entry_id'
               )=v_journal_id
             )
        )
      )
    for update
  loop
    select coalesce(jsonb_agg(value),'[]'::jsonb)
    into v_new_payments
    from jsonb_array_elements(
      coalesce(v_doc.payload->'payments','[]'::jsonb)
    )
    where coalesce(
      value->>'cashTransactionId',value->>'cash_transaction_id'
    )<>p_transaction_id
      and (
        v_journal_id is null
        or coalesce(
          value->>'journalEntryId',value->>'journal_entry_id'
        )<>v_journal_id
      );

    select coalesce(sum(public.erp_try_numeric(coalesce(
      value->>'amountInInvoiceCurrency',
      value->>'amount_in_invoice_currency',
      value->>'invoiceAmount',
      value->>'amount'
    ),0)),0)
    into v_paid
    from jsonb_array_elements(v_new_payments) as value;

    v_total:=public.erp_try_numeric(coalesce(
      v_doc.payload->>'totalAmount',
      v_doc.payload->>'total',
      v_doc.payload->>'invoiceAmount'
    ),0);

    update public.erp_commercial_workflow_documents
    set payload=jsonb_set(
          jsonb_set(
            jsonb_set(
              payload||jsonb_build_object(
                'payments',v_new_payments,
                'paymentUpdatedAt',v_now
              ),
              '{paidAmount}',to_jsonb(v_paid),true
            ),
            '{remainingAmount}',to_jsonb(greatest(v_total-v_paid,0)),true
          ),
          '{paymentStatus}',to_jsonb(
            case
              when v_paid<=0 then 'unpaid'
              when v_paid>=v_total and v_total>0 then 'paid'
              else 'partial'
            end
          ),true
        ),
        updated_at=v_now
    where company_id=p_company_id
      and id=v_doc.id;
  end loop;

  perform public.erp_v65_soft_delete_journal(
    p_company_id,v_journal_id,'حذف سند قبض أو صرف'
  );
  update public.erp_cash_transactions
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'deleteReason','حذف سند قبض أو صرف',
        'deletedAt',v_now
      )
  where company_id=p_company_id
    and id=p_transaction_id
    and not is_deleted;
end;
$$;

revoke all on function public.erp_delete_cloud_cash_transaction(uuid,text)
  from public,anon;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  to authenticated,service_role;

-- One-time repair for the exact historical no-op shape: an already-deleted
-- transfer header with active child cash rows. Because the parent is already
-- deleted, keeping active transfer legs is always an invariant violation.
do $$
declare
  v_orphan record;
begin
  for v_orphan in
    select distinct
      ct.company_id,
      coalesce(ct.data->>'referenceId',ct.data->>'reference_id') as transfer_id
    from public.erp_cash_transactions as ct
    join public.erp_cash_transfers as tr
      on tr.company_id=ct.company_id
     and tr.id=coalesce(ct.data->>'referenceId',ct.data->>'reference_id')
    where not ct.is_deleted
      and tr.is_deleted
      and nullif(btrim(coalesce(
        ct.data->>'referenceId',ct.data->>'reference_id',''
      )),'') is not null
      and (
        lower(replace(btrim(coalesce(
          ct.data->>'referenceType',ct.data->>'reference_type',''
        )),' ','_')) like 'cash_transfer%'
        or lower(replace(btrim(coalesce(ct.data->>'category','')),' ','_'))='cash_transfer'
        or lower(btrim(coalesce(
          ct.data->>'referenceType',ct.data->>'reference_type',''
        ))) in ('تحويل نقدي','تحويل بين الصناديق')
      )
  loop
    perform public.erp_r71_delete_cash_transfer_core(
      v_orphan.company_id,
      v_orphan.transfer_id,
      'R71 historical orphan cash-transfer cleanup'
    );
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
