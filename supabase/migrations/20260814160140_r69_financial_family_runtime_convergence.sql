begin;

-- R69 closes the real browser path that starts from an FX transfer. R68 kept
-- erp_delete_cloud_cash_transfer on its legacy transfer-only semantics, so a
-- partner advance could survive even though all rows already shared the same
-- paymentKey/transactionFamilyId.
create or replace function public.erp_r69_delete_financial_transaction_family(
  p_company_id uuid,
  p_transaction_id text default null,
  p_entry_id text default null,
  p_transfer_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_family text;
  v_payment text;
  v_transfer text:=nullif(btrim(p_transfer_id),'');
  v_seed text;
  v_seed_count integer:=0;
  v_family_evidence boolean:=false;
  v_journals text[]:='{}'::text[];
  v_result jsonb;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  if coalesce(nullif(btrim(p_transaction_id),''),nullif(btrim(p_entry_id),''),
              v_transfer) is null then
    raise exception 'financial_transaction_identity_required' using errcode='22023';
  end if;

  -- Resolve canonical identifiers only from explicit stored relationships.
  if p_transaction_id is not null then
    select nullif(coalesce(data->>'transactionFamilyId',data->>'paymentKey'),''),
           nullif(coalesce(data->>'paymentId',
             case when lower(coalesce(data->>'referenceType',''))<>'partner_advance'
                  then data->>'referenceId' end),''),
           coalesce(v_transfer,nullif(data->>'paymentTransferId',''),
             case when lower(coalesce(data->>'referenceType',''))='cash_transfer'
                  then nullif(data->>'referenceId','') end)
      into v_family,v_payment,v_transfer
    from public.erp_cash_transactions
    where company_id=p_company_id and id=p_transaction_id;
  elsif p_entry_id is not null then
    select nullif(coalesce(data->>'transactionFamilyId',data->>'paymentKey'),''),
           nullif(data->>'paymentId',''),
           coalesce(v_transfer,nullif(data->>'paymentTransferId',''),
             case when lower(coalesce(data->>'referenceType','')) like 'cash_transfer%'
                  then nullif(data->>'referenceId','') end)
      into v_family,v_payment,v_transfer
    from public.erp_journal_entries
    where company_id=p_company_id and id=p_entry_id;
  else
    select nullif(coalesce(data->>'transactionFamilyId',data->>'paymentKey'),''),
           nullif(data->>'paymentId','')
      into v_family,v_payment
    from public.erp_cash_transfers
    where company_id=p_company_id and id=v_transfer;
  end if;

  -- Historical V7.5.7 envelopes are authoritative link records. They recover
  -- families that predate R68 stamping without amount/date heuristics.
  select coalesce(v_family,max(p.value->>'paymentKey'),max(p.value->>'paymentId')),
         coalesce(v_payment,max(p.value->>'paymentId')),
         coalesce(v_transfer,max(p.value->>'transferId'))
    into v_family,v_payment,v_transfer
  from public.erp_commercial_workflow_documents d
  cross join lateral jsonb_array_elements(
    coalesce(d.payload->'payments','[]'::jsonb)
    ||coalesce(d.payload->'detachedPayments','[]'::jsonb)
  ) p(value)
  where d.company_id=p_company_id and (
    (p_transaction_id is not null and p.value->>'cashTransactionId'=p_transaction_id)
    or (p_entry_id is not null and p.value->>'journalEntryId'=p_entry_id)
    or (v_transfer is not null and p.value->>'transferId'=v_transfer)
    or (v_family is not null and p.value->>'paymentKey'=v_family)
    or (v_payment is not null and p.value->>'paymentId'=v_payment)
  );

  v_family:=coalesce(v_family,v_payment);
  v_family_evidence:=v_family is not null or v_payment is not null;

  -- Pick a business-payment seed, never an FX transfer leg. Multiple members
  -- with the same canonical family are not ambiguous; they are one family.
  select min(c.id),count(*) into v_seed,v_seed_count
  from public.erp_cash_transactions c
  where c.company_id=p_company_id and not c.is_deleted
    and lower(coalesce(c.data->>'referenceType',''))<>'cash_transfer'
    and (
      (p_transaction_id is not null and c.id=p_transaction_id)
      or (v_family is not null and
          coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family)
      or (v_payment is not null and c.data->>'paymentId'=v_payment)
      or (v_transfer is not null and c.data->>'paymentTransferId'=v_transfer)
      or (p_entry_id is not null and
          coalesce(c.data->>'journalEntryId',c.data->>'entryId')=p_entry_id)
    );

  if v_family_evidence and v_seed_count=0 then
    raise exception 'financial_family_incomplete_or_ambiguous'
      using errcode='P0001',detail=concat_ws(',',
        'family='||coalesce(v_family,''),'payment='||coalesce(v_payment,''),
        'transfer='||coalesce(v_transfer,''));
  end if;
  if not v_family_evidence and v_seed_count=0 then
    return jsonb_build_object('ok',false,'standaloneTransfer',true,
      'transferId',v_transfer);
  end if;

  -- Lock the complete resolved graph before any mutation.
  perform 1 from public.erp_cash_transactions c
   where c.company_id=p_company_id and not c.is_deleted and (
     c.id=v_seed
     or (v_family is not null and
         coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family)
     or (v_payment is not null and c.data->>'paymentId'=v_payment)
     or (v_transfer is not null and
         (c.data->>'paymentTransferId'=v_transfer
          or (lower(coalesce(c.data->>'referenceType',''))='cash_transfer'
              and c.data->>'referenceId'=v_transfer))))
   for update;
  perform 1 from public.erp_cash_transfers t
   where t.company_id=p_company_id and not t.is_deleted and (
     t.id=v_transfer or (v_family is not null and
       coalesce(t.data->>'transactionFamilyId',t.data->>'paymentKey')=v_family)
     or (v_payment is not null and t.data->>'paymentId'=v_payment))
   for update;

  select coalesce(array_agg(distinct x),array[]::text[]) into v_journals
  from (
    select coalesce(c.data->>'journalEntryId',c.data->>'entryId') x
    from public.erp_cash_transactions c
    where c.company_id=p_company_id and (
      c.id=v_seed or (v_family is not null and
        coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family)
      or (v_payment is not null and c.data->>'paymentId'=v_payment)
      or (v_transfer is not null and
        (c.data->>'paymentTransferId'=v_transfer or c.data->>'referenceId'=v_transfer)))
    union
    select je.id from public.erp_journal_entries je
    where je.company_id=p_company_id and (
      je.id=p_entry_id or (v_family is not null and
        coalesce(je.data->>'transactionFamilyId',je.data->>'paymentKey')=v_family)
      or (v_payment is not null and je.data->>'paymentId'=v_payment)
      or (v_transfer is not null and je.data->>'referenceId'=v_transfer))
  ) q where x is not null;

  v_result:=public.erp_r68_delete_financial_transaction_family(
    p_company_id,v_seed,null
  );

  -- A successful response is impossible while any resolved active leg remains.
  if exists(select 1 from public.erp_cash_transactions c
      where c.company_id=p_company_id and not c.is_deleted and (
        c.id=v_seed or (v_family is not null and
          coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family)
        or (v_payment is not null and c.data->>'paymentId'=v_payment)
        or (v_transfer is not null and
          (c.data->>'paymentTransferId'=v_transfer or c.data->>'referenceId'=v_transfer))))
    or exists(select 1 from public.erp_cash_transfers t
      where t.company_id=p_company_id and not t.is_deleted and (
        t.id=v_transfer or (v_family is not null and
          coalesce(t.data->>'transactionFamilyId',t.data->>'paymentKey')=v_family)
        or (v_payment is not null and t.data->>'paymentId'=v_payment)))
    or exists(select 1 from public.erp_journal_entries je
      where je.company_id=p_company_id and not je.is_deleted and je.id=any(v_journals))
    or exists(select 1 from public.erp_journal_lines jl
      where jl.company_id=p_company_id and not jl.is_deleted
        and coalesce(jl.data->>'entryId',jl.data->>'entry_id')=any(v_journals))
    or exists(select 1 from public.erp_partner_advance_allocations a
      where a.company_id=p_company_id and not a.is_deleted
        and a.cash_transaction_id in (select c.id from public.erp_cash_transactions c
          where c.company_id=p_company_id and (c.id=v_seed or
            (v_family is not null and coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family))))
    or exists(select 1 from public.erp_maintenance_payments mp
      where mp.company_id=p_company_id and not mp.is_deleted and (
        mp.cash_transaction_id=v_seed or mp.source_cash_transaction_id=v_seed
        or (v_family is not null and mp.payment_key=v_family)
        or mp.journal_entry_id=any(v_journals))) then
    raise exception 'financial_family_postcondition_failed'
      using errcode='P0001',detail='family='||coalesce(v_family,v_seed);
  end if;

  return v_result||jsonb_build_object('r69Postcondition',true,
    'entryId',p_entry_id,'requestedTransferId',p_transfer_id);
end;
$$;

-- Preserve true standalone transfer deletion, while payment-owned transfers
-- converge on the R69 all-or-nothing primitive.
create or replace function public.erp_r69_delete_standalone_cash_transfer(
  p_company_id uuid,p_transfer_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_now timestamptz:=now(); v_transaction record;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  perform 1 from public.erp_cash_transfers where company_id=p_company_id
    and id=p_transfer_id and not is_deleted for update;
  if not found then return; end if;
  for v_transaction in select id,coalesce(data->>'journalEntryId',data->>'entryId') journal_id
    from public.erp_cash_transactions where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',''))='cash_transfer'
      and data->>'referenceId'=p_transfer_id for update
  loop
    perform public.erp_v65_soft_delete_journal(p_company_id,v_transaction.journal_id,'حذف تحويل الصناديق');
    update public.erp_cash_transactions set is_deleted=true,deleted_at=v_now,
      updated_at=v_now,updated_by=auth.uid(),data=data||jsonb_build_object(
        'deleteReason','حذف تحويل الصناديق','deletedAt',v_now)
    where company_id=p_company_id and id=v_transaction.id and not is_deleted;
  end loop;
  for v_transaction in select id from public.erp_journal_entries
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType','')) like 'cash_transfer%'
      and data->>'referenceId'=p_transfer_id
  loop
    perform public.erp_v65_soft_delete_journal(p_company_id,v_transaction.id,'حذف تحويل الصناديق');
  end loop;
  update public.erp_cash_transfers set is_deleted=true,deleted_at=v_now,
    updated_at=v_now,updated_by=auth.uid(),data=data||jsonb_build_object(
      'deleteReason','حذف تحويل الصناديق','deletedAt',v_now)
  where company_id=p_company_id and id=p_transfer_id and not is_deleted;
end $$;

create or replace function public.erp_delete_cloud_cash_transfer(
  p_company_id uuid,p_transfer_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  v_result:=public.erp_r69_delete_financial_transaction_family(
    p_company_id,null,null,p_transfer_id
  );
  if coalesce((v_result->>'standaloneTransfer')::boolean,false) then
    perform public.erp_r69_delete_standalone_cash_transfer(p_company_id,p_transfer_id);
  end if;
end $$;

create or replace function public.erp_delete_cloud_cash_transaction(
  p_company_id uuid,p_transaction_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_type text;v_transfer text;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['accounting.delete']);
  select lower(coalesce(data->>'referenceType','')),
         nullif(coalesce(data->>'referenceId',data->>'paymentTransferId'),'')
    into v_type,v_transfer from public.erp_cash_transactions
    where company_id=p_company_id and id=p_transaction_id and not is_deleted;
  if not found then return; end if;
  if v_type='cash_transfer' and v_transfer is not null then
    perform public.erp_delete_cloud_cash_transfer(p_company_id,v_transfer);
  else
    perform public.erp_r69_delete_financial_transaction_family(
      p_company_id,p_transaction_id,null,null
    );
  end if;
end $$;

revoke all on function public.erp_r69_delete_financial_transaction_family(uuid,text,text,text)
  from public,anon,authenticated;
revoke all on function public.erp_r69_delete_standalone_cash_transfer(uuid,text)
  from public,anon,authenticated;
revoke all on function public.erp_delete_cloud_cash_transfer(uuid,text)
  from public,anon,authenticated;
revoke all on function public.erp_delete_cloud_cash_transaction(uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r69_delete_financial_transaction_family(uuid,text,text,text)
  to authenticated,service_role;
grant execute on function public.erp_r69_delete_standalone_cash_transfer(uuid,text)
  to service_role;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text)
  to authenticated,service_role;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
